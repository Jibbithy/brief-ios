import SwiftUI

/// The whole app: today's brief, top to bottom. Pull to refresh.
struct BriefView: View {
    private let store = BriefStore.shared
    @State private var showSettings = false

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sp5) {
                if let problem = store.problem {
                    DeckAlert(store.brief == nil ? .crit : .warn, message: problem)
                }
                if let brief = store.brief {
                    BriefContent(brief: brief, updatedAt: store.updatedAt)
                } else if store.noBriefYet {
                    DeckEmpty(label: "Today", title: "No brief yet.", message: "First one arrives at 8 AM.") {
                        Button("Check again") { Task { await store.refresh() } }
                            .buttonStyle(.deck)
                            .padding(.top, Theme.sp2)
                    }
                } else if store.problem == nil {
                    DeckHint("Loading today's brief…")
                }
            }
            .padding(Theme.sp4)
        }
        .onAppear {
            // Demo only: open on the payments + week sections for a screenshot.
            if DemoMode.scrollsToWeek {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(BriefContent.weekAnchor, anchor: .top) }
            }
        }
        }
        .defaultScrollAnchor(DemoMode.scrollsToEnd ? .bottom : .top)
        .refreshable { await store.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) { bar }
        .deckGround()
        .sheet(isPresented: $showSettings) {
            SettingsSheet(onClose: { showSettings = false }).deckSheet()
        }
    }

    private var bar: some View {
        HStack(spacing: Theme.sp3) {
            Text("Brief")
                .font(Deck.title)
                .textCase(.uppercase)
                .foregroundStyle(Deck.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if store.loading {
                DeckChip("Updating", kind: .plain, status: .idle)
            } else if let b = store.brief, !b.isForDay(of: Date()) {
                DeckChip("Old brief", kind: .warn)
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(DeckIconButtonStyle(.plain, side: 40))
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Theme.sp4)
        .padding(.vertical, Theme.sp3)
        .deckBar(.top)
    }
}

// MARK: - The brief

struct BriefContent: View {
    let brief: Brief
    let updatedAt: Date?
    static let weekAnchor = "week"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp5) {
            VStack(alignment: .leading, spacing: Theme.sp2) {
                Text(dateLine).deckLabel()
                Text(brief.headline)
                    .font(Deck.sans(22, .bold, relativeTo: .title2))
                    .foregroundStyle(Deck.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ChoresSection()
            WeatherCard(weather: brief.weather)
            CalendarSection(events: brief.agenda)
            EmailSection(emails: brief.emails)
            SubscriptionSection(subscriptions: brief.dueSubscriptions)
                .id(Self.weekAnchor)
            UpcomingSection(days: brief.upcomingDays)
            RackSection(rack: brief.rack)
            if !brief.errors.isEmpty { ErrorsFootnote(errors: brief.errors) }
            Text(footer)
                .font(Deck.mono(11, .regular, relativeTo: .caption))
                .foregroundStyle(Deck.muted)
        }
    }

    /// "SATURDAY · SEP 26", from the brief's own `date` (the hub's day), not
    /// the phone's clock.
    private var dateLine: String {
        guard let d = Brief.parseDate(brief.date) else { return brief.date }
        return "\(d.formatted(.dateTime.weekday(.wide))) · \(d.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var footer: String {
        var s = "Written \(brief.generatedAt.formatted(date: .omitted, time: .shortened))"
        if let updatedAt { s += " · fetched \(updatedAt.formatted(date: .omitted, time: .shortened))" }
        return s
    }
}

/// A mono section label with an optional count, over its card.
struct SectionHead: View {
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let count { Text("· \(count)") }
        }
        .deckLabel()
        .accessibilityAddTraits(.isHeader)
    }
}

struct WeatherCard: View {
    let weather: Brief.Weather?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            SectionHead(title: "Weather · \(weather?.location ?? "Anytown, US")")
            if let w = weather {
                HStack(alignment: .center, spacing: Theme.sp4) {
                    Image(systemName: WeatherGlyph.symbol(for: w.summary))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Deck.onFill)
                        .frame(width: 56, height: 56)
                        .background(Deck.warn)
                        .overlay(Rectangle().strokeBorder(Deck.line, lineWidth: Deck.borderWidth))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Brief.Weather.degrees(w.current ?? w.high))
                            .font(Deck.sans(40, .bold, relativeTo: .largeTitle))
                            .foregroundStyle(Deck.ink)
                        Text(w.summary)
                            .font(Deck.body)
                            .foregroundStyle(Deck.ink)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 6) {
                        stat("High", Brief.Weather.degrees(w.high))
                        stat("Low", Brief.Weather.degrees(w.low))
                        if let p = w.precipChance { stat("Rain", "\(Int(p.rounded()))%") }
                    }
                }
                .padding(Theme.sp4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .deckCard()
                .accessibilityElement(children: .combine)
            } else {
                unavailable("No weather in this brief.")
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).deckLabel()
            Text(value).font(Deck.number).foregroundStyle(Deck.ink)
        }
    }
}

struct CalendarSection: View {
    let events: [Brief.Event]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            SectionHead(title: "Today", count: events.count)
            if events.isEmpty {
                unavailable("Nothing on the calendar.")
            } else {
                TimelineView(.everyMinute) { ctx in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                            if i > 0 { Rectangle().fill(Deck.hair).frame(height: Deck.borderWidth) }
                            EventRow(event: e, now: DemoMode.clock(ctx.date), expanded: DemoMode.expandsDetails && i == 1)
                        }
                    }
                    .deckCard()
                }
            }
        }
    }
}

/// One event: time and title, collapsed. Tap to drop down everything the
/// calendar gave - when, where, which calendar, who, the link and the notes.
struct EventRow: View {
    let event: Brief.Event
    let now: Date
    /// Today's rows dim once over and mark the one on now; the week's do not.
    var live = true
    @State var expanded = false

    init(event: Brief.Event, now: Date, live: Bool = true, expanded: Bool = false) {
        self.event = event
        self.now = now
        self.live = live
        _expanded = State(initialValue: expanded)
    }

    private var isNow: Bool { live && !event.allDay && event.start <= now && (event.end ?? event.start) > now }
    private var isOver: Bool { live && !event.allDay && (event.end ?? event.start) <= now }

    var body: some View {
        ExpandableRow(expanded: $expanded) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.sp3) {
                Text(event.allDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                    .font(Deck.mono(12, .medium, relativeTo: .footnote))
                    .textCase(.uppercase)
                    .foregroundStyle(Deck.ink)
                    .frame(width: Theme.timeColumn, alignment: .leading)
                Text(event.title)
                    .font(Deck.sans(15, .bold, relativeTo: .body))
                    .foregroundStyle(Deck.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isNow { DeckChip("Now", kind: .accent) }
            }
        } detail: {
            DetailLine("When", when)
            if let loc = event.location, !loc.isEmpty { DetailLine("Where", loc) }
            if let c = event.calendarName, !c.isEmpty { DetailLine("Calendar", c) }
            if let o = event.organizer, !o.isEmpty { DetailLine("Organizer", o) }
            if let n = event.attendees, n > 0 { DetailLine("Invited", "\(n) \(n == 1 ? "person" : "people")") }
            if let link = event.link {
                DetailRow("Link") {
                    Link(destination: link) {
                        Text(link.host ?? link.absoluteString)
                            .font(Deck.small)
                            .foregroundStyle(Deck.blueInk)
                            .underline()
                    }
                }
            }
            if let notes = event.notes, !notes.isEmpty { DetailLine("Notes", notes) }
        }
        .background(isNow ? Deck.rail : .clear)
        .overlay(alignment: .leading) {
            if isNow { Rectangle().fill(Deck.accent).frame(width: 5) }
        }
        .opacity(isOver && !expanded ? 0.55 : 1)
    }

    /// "Sat, Sep 26 · 9:30 – 10:00 AM · 30 min", or "Sat, Sep 26 · All day".
    private var when: String {
        let day = event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        var parts = [day]
        if event.allDay {
            parts.append(event.durationText ?? "All day")
        } else {
            if let end = event.end, end > event.start {
                parts.append((event.start..<end).formatted(.interval.hour().minute()))
            } else {
                parts.append(event.start.formatted(date: .omitted, time: .shortened))
            }
            if let d = event.durationText { parts.append(d) }
        }
        return parts.joined(separator: " · ")
    }
}

/// A row that drops down its detail when tapped. The header is the whole tap
/// target; the chevron turns as the detail slides in under it.
struct ExpandableRow<Header: View, Detail: View>: View {
    @Binding var expanded: Bool
    @ViewBuilder var header: () -> Header
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.28)) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.sp2) {
                    header()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Deck.muted)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, Theme.sp3)
                .padding(.horizontal, Theme.sp4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Hides the details" : "Shows the details")

            if expanded {
                VStack(alignment: .leading, spacing: Theme.sp2) { detail() }
                    .padding(.leading, Theme.sp4 + Theme.timeColumn + Theme.sp3)
                    .padding(.trailing, Theme.sp4)
                    .padding(.bottom, Theme.sp3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

/// A mono label over its value, inside an expanded row.
struct DetailRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: () -> Value
    init(_ label: String, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.value = value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).deckLabel()
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct DetailLine: View {
    let label: String
    let text: String
    init(_ label: String, _ text: String) {
        self.label = label
        self.text = text
    }
    var body: some View {
        DetailRow(label) {
            Text(text)
                .font(Deck.small)
                .foregroundStyle(Deck.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// The seven days after today, one strip per day.
struct UpcomingSection: View {
    let days: [(day: Date, events: [Brief.Event])]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            SectionHead(title: "Next 7 days", count: days.reduce(0) { $0 + $1.events.count })
            if days.isEmpty {
                unavailable("Nothing in the week ahead.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.day) { i, group in
                        Text(group.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .deckLabel()
                            .padding(.horizontal, Theme.sp4)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Deck.rail)
                            .overlay(alignment: .top) {
                                if i > 0 { Rectangle().fill(Deck.line).frame(height: Deck.borderWidth) }
                            }
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(group.events.enumerated()), id: \.element.id) { j, e in
                            if j > 0 { Rectangle().fill(Deck.hair).frame(height: Deck.borderWidth) }
                            EventRow(event: e, now: .distantPast, live: false)
                        }
                    }
                }
                .deckCard()
            }
        }
    }
}

/// Subscription payments due this week: name, due day, amount.
struct SubscriptionSection: View {
    let subscriptions: [Brief.Subscription]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            SectionHead(title: "Payments due", count: subscriptions.count)
            if subscriptions.isEmpty {
                unavailable("No subscriptions due this week.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(subscriptions.enumerated()), id: \.element.id) { i, sub in
                        if i > 0 { Rectangle().fill(Deck.hair).frame(height: Deck.borderWidth) }
                        HStack(alignment: .firstTextBaseline, spacing: Theme.sp3) {
                            Text(dueLabel(sub))
                                .font(Deck.mono(12, .medium, relativeTo: .footnote))
                                .textCase(.uppercase)
                                .foregroundStyle(Deck.ink)
                                .frame(width: Theme.timeColumn, alignment: .leading)
                            Text(sub.name)
                                .font(Deck.sans(15, .bold, relativeTo: .body))
                                .foregroundStyle(Deck.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(sub.amountText)
                                .font(Deck.number)
                                .foregroundStyle(Deck.ink)
                        }
                        .padding(.vertical, Theme.sp3)
                        .padding(.horizontal, Theme.sp4)
                        .accessibilityElement(children: .combine)
                    }
                }
                .deckCard()
            }
        }
    }

    private func dueLabel(_ s: Brief.Subscription) -> String {
        guard let d = s.due else { return s.dueDate }
        return d.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

struct EmailSection: View {
    let emails: [Brief.Email]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            SectionHead(title: "Important email", count: emails.count)
            if emails.isEmpty {
                unavailable("Nothing that needs you.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(emails.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Rectangle().fill(Deck.hair).frame(height: Deck.borderWidth) }
                        EmailRow(email: m, expanded: DemoMode.expandsDetails && i == 0)
                    }
                }
                .deckCard()
            }
        }
    }
}

/// One important email: subject and time, collapsed. Tap for the sender,
/// when it came, why it matters and the start of the body.
struct EmailRow: View {
    let email: Brief.Email
    @State var expanded = false

    init(email: Brief.Email, expanded: Bool = false) {
        self.email = email
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        ExpandableRow(expanded: $expanded) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.sp3) {
                Text(email.receivedAt?.formatted(date: .omitted, time: .shortened) ?? "–")
                    .font(Deck.mono(12, .medium, relativeTo: .footnote))
                    .textCase(.uppercase)
                    .foregroundStyle(Deck.ink)
                    .frame(width: Theme.timeColumn, alignment: .leading)
                Text(email.subject)
                    .font(Deck.sans(15, .bold, relativeTo: .body))
                    .foregroundStyle(Deck.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            DetailLine("From", email.from)
            if let at = email.receivedAt {
                DetailLine("Received", at.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
            }
            if !email.why.isEmpty {
                DetailRow("Why") {
                    Text(email.why)
                        .font(Deck.small)
                        .foregroundStyle(Deck.accentInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let snip = email.snippet, !snip.isEmpty { DetailLine("Preview", snip) }
        }
    }
}

struct RackSection: View {
    let rack: Brief.Rack?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            SectionHead(title: "Rack")
            if let rack {
                VStack(alignment: .leading, spacing: Theme.sp3) {
                    HStack(spacing: Theme.sp2) {
                        DeckDot(rack.allUp ? .ok : .crit, size: 10)
                        Text(summary(rack))
                            .font(Deck.sans(15, .bold, relativeTo: .body))
                            .foregroundStyle(rack.allUp ? Deck.okInk : Deck.critInk)
                    }
                    if !rack.allUp {
                        FlowChips(names: rack.down)
                    }
                }
                .padding(Theme.sp4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .deckTile()
                .accessibilityElement(children: .combine)
            } else {
                unavailable("No rack status in this brief.")
            }
        }
    }

    private func summary(_ r: Brief.Rack) -> String {
        r.allUp ? "All \(r.total) up" : "\(r.down.count) of \(r.total) down"
    }
}

/// The down nodes as crit chips, wrapping onto new lines.
struct FlowChips: View {
    let names: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.sp2) { chips }
            VStack(alignment: .leading, spacing: Theme.sp2) { chips }
        }
    }
    @ViewBuilder private var chips: some View {
        ForEach(names, id: \.self) { DeckChip($0, kind: .crit, status: .crit) }
    }
}

struct ErrorsFootnote: View {
    let errors: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            SectionHead(title: "Notes")
            ForEach(errors, id: \.self) { e in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    DeckDot(.warn, size: 7)
                    Text(e)
                        .font(Deck.small)
                        .foregroundStyle(Deck.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A dashed "not in this brief" box, the Deck empty state at row height.
@MainActor
func unavailable(_ text: String) -> some View {
    Text(text)
        .font(Deck.body)
        .foregroundStyle(Deck.muted)
        .padding(Theme.sp4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Deck.line, style: StrokeStyle(lineWidth: Deck.borderWidth, dash: [6, 4])))
}

// MARK: - Settings

struct SettingsSheet: View {
    var onClose: () -> Void
    @State private var changingToken = false

    var body: some View {
        if changingToken {
            TokenEntryView(onClose: { changingToken = false })
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sp5) {
                    VStack(alignment: .leading, spacing: Theme.sp2) {
                        SectionHead(title: "Theme")
                        DeckThemePicker()
                    }
                    VStack(alignment: .leading, spacing: Theme.sp2) {
                        SectionHead(title: "Hub")
                        DeckHint("The token is shared with Agents and Rack Control. Changing it here changes it there.")
                        Button("Change token") { changingToken = true }
                            .buttonStyle(.deck)
                    }
                }
                .padding(Theme.sp4)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(Deck.title)
                        .textCase(.uppercase)
                        .foregroundStyle(Deck.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Done") { onClose() }.buttonStyle(.deckGhost)
                }
                .padding(Theme.sp4)
                .deckBar(.top)
            }
            .deckGround()
        }
    }
}
