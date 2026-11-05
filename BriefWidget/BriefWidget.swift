import SwiftUI
import UIKit
import WidgetKit

@main
struct BriefWidgetBundle: WidgetBundle {
    var body: some Widget { BriefWidget() }
}

/// Small: weather + next event. Medium: adds the headline and email count.
/// Lock screen: high/low + next event (rectangular), or one line (inline).
struct BriefWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Config.widgetKind, provider: BriefProvider()) { entry in
            BriefWidgetView(entry: entry)
        }
        .configurationDisplayName("Brief")
        .description("Today's weather and your next event.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Timeline

struct BriefEntry: TimelineEntry {
    let date: Date
    let brief: Brief?
}

/// Draws from the brief the app cached in the App Group, and tries the hub
/// first when the Keychain will hand over the token - so the widget can be
/// newer than the last time the app was opened.
///
/// One entry per moment the "next event" changes (each event's start and
/// end), so the widget rolls forward through the day without a fetch; a new
/// timeline (and fetch) is asked for every 30 minutes, well inside WidgetKit's
/// daily budget. The app also reloads the widget whenever it fetches.
struct BriefProvider: TimelineProvider {
    func placeholder(in context: Context) -> BriefEntry {
        BriefEntry(date: Date(), brief: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (BriefEntry) -> Void) {
        // The gallery preview: the real brief if there is one, else the sample.
        completion(BriefEntry(date: Date(), brief: BriefCache.load() ?? .sample()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BriefEntry>) -> Void) {
        let done = UncheckedSendable(completion)
        Task {
            let brief = await Self.freshOrCached()
            done.value(Self.timeline(for: brief, now: Date()))
        }
    }

    static func freshOrCached() async -> Brief? {
        if case .token(let token) = TokenStore.read() {
            // Short: WidgetKit gives an extension seconds, not minutes.
            if case .brief(let b, let data) = await BriefAPI.fetch(token: token, session: BriefAPI.session(timeout: 8)) {
                BriefCache.save(data)
                return b
            }
        }
        return BriefCache.load()
    }

    static func timeline(for brief: Brief?, now: Date) -> Timeline<BriefEntry> {
        let refresh = now.addingTimeInterval(30 * 60)
        let changes = brief?.eventBoundaries(after: now).filter { $0 < refresh } ?? []
        let entries = [BriefEntry(date: now, brief: brief)] + changes.map { BriefEntry(date: $0, brief: brief) }
        return Timeline(entries: entries, policy: .after(refresh))
    }
}

/// WidgetKit's completion handler is not Sendable, but it is documented as
/// callable from any thread; this carries it into the fetch Task.
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

// MARK: - Views

struct BriefWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BriefEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: LockRectangular(entry: entry)
        case .accessoryInline: LockInline(entry: entry)
        case .systemMedium: MediumView(entry: entry).containerBackground(WDeck.ground, for: .widget)
        default: SmallView(entry: entry).containerBackground(WDeck.ground, for: .widget)
        }
    }
}

/// Weather block: glyph tile, current temperature, high/low.
struct WeatherBlock: View {
    let weather: Brief.Weather?

    var body: some View {
        if let w = weather {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: WeatherGlyph.symbol(for: w.summary))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WDeck.onFill)
                        .frame(width: 26, height: 26)
                        .background(WDeck.warn)
                        .overlay(Rectangle().strokeBorder(WDeck.line, lineWidth: 2))
                    Text(Brief.Weather.degrees(w.current ?? w.high))
                        .font(WDeck.sans(30, bold: true))
                        .foregroundStyle(WDeck.ink)
                        .minimumScaleFactor(0.7)
                }
                Text("H \(Brief.Weather.degrees(w.high))  L \(Brief.Weather.degrees(w.low))")
                    .font(WDeck.mono(11))
                    .foregroundStyle(WDeck.muted)
            }
        } else {
            Text("No weather").font(WDeck.mono(11)).foregroundStyle(WDeck.muted)
        }
    }
}

/// "NEXT · 9:30" over the event title, or "Nothing else today".
struct NextEventBlock: View {
    let brief: Brief
    let now: Date
    var lines = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let e = brief.nextEvent(after: now) {
                Text(e.start <= now ? "Now" : "Next · \(e.start.formatted(date: .omitted, time: .shortened))")
                    .font(WDeck.mono(10, semibold: true))
                    .textCase(.uppercase)
                    .foregroundStyle(e.start <= now ? WDeck.accentInk : WDeck.muted)
                Text(e.title)
                    .font(WDeck.sans(13, bold: true))
                    .foregroundStyle(WDeck.ink)
                    .lineLimit(lines)
            } else {
                Text("Nothing else today")
                    .font(WDeck.sans(13, bold: true))
                    .foregroundStyle(WDeck.muted)
            }
        }
    }
}

struct SmallView: View {
    let entry: BriefEntry
    var body: some View {
        if let b = entry.brief {
            VStack(alignment: .leading, spacing: 0) {
                WeatherBlock(weather: b.weather)
                Spacer(minLength: 6)
                Rectangle().fill(WDeck.line).frame(height: 2)
                Spacer(minLength: 6)
                NextEventBlock(brief: b, now: entry.date)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            NoBrief()
        }
    }
}

struct MediumView: View {
    let entry: BriefEntry
    var body: some View {
        if let b = entry.brief {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    WeatherBlock(weather: b.weather)
                    Spacer(minLength: 6)
                    NextEventBlock(brief: b, now: entry.date)
                }
                .frame(width: 124, alignment: .leading)
                Rectangle().fill(WDeck.line).frame(width: 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Text("\(b.emails.count)")
                            .font(WDeck.mono(11, semibold: true))
                            .foregroundStyle(WDeck.onFill)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(b.emails.isEmpty ? WDeck.ok : WDeck.accent)
                            .overlay(Rectangle().strokeBorder(WDeck.line, lineWidth: 1.5))
                        Text(b.emails.count == 1 ? "email" : "emails")
                            .font(WDeck.mono(10, semibold: true))
                            .textCase(.uppercase)
                            .foregroundStyle(WDeck.muted)
                    }
                    Text(b.headline)
                        .font(WDeck.sans(13, bold: false))
                        .foregroundStyle(WDeck.ink)
                        .lineLimit(5)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            NoBrief()
        }
    }
}

struct NoBrief: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Brief").font(WDeck.mono(10, semibold: true)).textCase(.uppercase).foregroundStyle(WDeck.muted)
            Text("No brief yet.").font(WDeck.sans(15, bold: true)).foregroundStyle(WDeck.ink)
            Text("First one arrives at 8 AM.").font(WDeck.sans(12, bold: false)).foregroundStyle(WDeck.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Lock screen, rectangular: "↑78° ↓52°" then the next event. System-tinted
/// (the lock screen renders accessories in its own vibrant style), Deck faces.
struct LockRectangular: View {
    let entry: BriefEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let b = entry.brief {
                HStack(spacing: 4) {
                    if let w = b.weather {
                        Image(systemName: WeatherGlyph.symbol(for: w.summary))
                        Text("H \(Brief.Weather.degrees(w.high))  L \(Brief.Weather.degrees(w.low))")
                    } else {
                        Text("No weather")
                    }
                }
                .font(WDeck.sans(15, bold: true))
                if let e = b.nextEvent(after: entry.date) {
                    Text(e.start <= entry.date ? "Now" : e.start.formatted(date: .omitted, time: .shortened))
                        .font(WDeck.mono(11, semibold: true))
                    Text(e.title).font(WDeck.sans(13, bold: false)).lineLimit(1)
                } else {
                    Text("Nothing else today").font(WDeck.sans(13, bold: false))
                }
            } else {
                Text("No brief yet").font(WDeck.sans(15, bold: true))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }
}

struct LockInline: View {
    let entry: BriefEntry
    var body: some View {
        Text(line).containerBackground(.clear, for: .widget)
    }
    private var line: String {
        guard let b = entry.brief else { return "No brief yet" }
        var parts: [String] = []
        if let w = b.weather { parts.append("\(Brief.Weather.degrees(w.high))/\(Brief.Weather.degrees(w.low))") }
        if let e = b.nextEvent(after: entry.date) {
            parts.append("\(e.start.formatted(date: .omitted, time: .shortened)) \(e.title)")
        }
        return parts.isEmpty ? "Brief" : parts.joined(separator: " · ")
    }
}

// MARK: - Deck tokens for the widget

/// The Deck Cream values the widget uses. A SUBSET COPY of DeckCream.swift's
/// tokens, because that file cannot compile here: DeckTheme.apply() reaches
/// for UIApplication.shared, which is unavailable in an app extension. The
/// hexes must match rack-os-design/ios/DeckCream.swift.
enum WDeck {
    static let ground = pair(0xf3ead3, 0x1a1714)
    static let ink = pair(0x141210, 0xf3ead3)
    static let muted = pair(0x5e5749, 0xb5aa92)
    static let line = pair(0x141210, 0xe9dfc6)
    static let accentInk = pair(0xa33210, 0xff7a5c)
    static let onFill = hex(0x141210)
    static let accent = hex(0xff5c39)
    static let ok = hex(0x20b552)
    static let warn = hex(0xffb020)

    /// Space Grotesk / IBM Plex Mono, registered through the widget's
    /// UIAppFonts. Fixed sizes: a widget is a fixed box.
    static func sans(_ size: CGFloat, bold: Bool) -> Font {
        .custom(bold ? "SpaceGrotesk-Bold" : "SpaceGrotesk-Medium", fixedSize: size)
    }
    static func mono(_ size: CGFloat, semibold: Bool = false) -> Font {
        .custom(semibold ? "IBMPlexMono-SemiBold" : "IBMPlexMono-Medium", fixedSize: size)
    }

    static func hex(_ v: UInt32) -> Color { Color(uiColor: ui(v)) }
    static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? ui(dark) : ui(light) })
    }
    static func ui(_ v: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
            blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

#if DEBUG
    #Preview(as: .systemSmall) {
        BriefWidget()
    } timeline: {
        BriefEntry(date: Date(), brief: .sample())
    }
#endif
