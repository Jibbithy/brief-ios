import SwiftUI

/// Tonight's nightly job and the Saturday list, each with a Done. Hidden when
/// the hub has no chores (or no /api/chores yet).
///
/// NO CONFIRMATION: one tap sends (the user's call). What makes it safe is
/// ChoreApproval, not a dialog.
struct ChoresSection: View {
    private let store = ChoresStore.shared

    var body: some View {
        if let page = store.page, !page.isEmpty {
            VStack(alignment: .leading, spacing: Theme.sp2) {
                SectionHead(title: "Chores")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups(page).enumerated()), id: \.element.title) { i, group in
                        Text(group.title)
                            .deckLabel()
                            .padding(.horizontal, Theme.sp4)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Deck.rail)
                            .overlay(alignment: .top) {
                                if i > 0 { Rectangle().fill(Deck.line).frame(height: Deck.borderWidth) }
                            }
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(group.rows.enumerated()), id: \.element.id) { j, row in
                            if j > 0 { Rectangle().fill(Deck.hair).frame(height: Deck.borderWidth) }
                            ChoreRowView(
                                row: row, busy: store.busy.contains(row.id), problem: store.problem[row.id],
                                onDone: { Task { await store.done(row) } })
                        }
                    }
                }
                .deckCard()
            }
        }
    }

    /// "Tonight", then one group per day-list date, titled by its weekday.
    private func groups(_ page: ChoresPage) -> [(title: String, rows: [ChoreRow])] {
        var out: [(title: String, rows: [ChoreRow])] = []
        if !page.weekly.isEmpty { out.append(("Tonight", page.weekly)) }
        for date in page.day.map(\.date).reduce(into: [String](), { if !$0.contains($1) { $0.append($1) } }) {
            out.append((ChoreText.weekday(date), page.day.filter { $0.date == date }))
        }
        return out
    }
}

struct ChoreRowView: View {
    let row: ChoreRow
    let busy: Bool
    let problem: String?
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            HStack(alignment: .center, spacing: Theme.sp3) {
                DeckCheck(state: row.done == nil ? .off : .on)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ChoreText.title(row.task))
                        .font(Deck.sans(15, .bold, relativeTo: .body))
                        .foregroundStyle(row.done == nil ? Deck.ink : Deck.muted)
                        .strikethrough(row.done != nil, color: Deck.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let d = row.deadline, row.done == nil {
                        Text("By \(ChoreText.time(d))")
                            .font(Deck.mono(12, .medium, relativeTo: .footnote))
                            .textCase(.uppercase)
                            .foregroundStyle(Deck.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                trailing
            }
            if let done = row.done { results(done.steps) }
            if let problem { DeckErrorText(problem).padding(.leading, 20 + Theme.sp3) }
        }
        .padding(.vertical, Theme.sp3)
        .padding(.horizontal, Theme.sp4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var trailing: some View {
        if row.done != nil {
            EmptyView()
        } else if busy {
            ProgressView()
                .tint(Deck.ink)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Marking done")
        } else {
            Button("Done", action: onDone)
                .buttonStyle(.deck)
                .accessibilityLabel("Mark \(row.task) done")
        }
    }

    /// The good news on one muted line, each failure on its own in crit ink.
    private func results(_ steps: ChoreSteps) -> some View {
        let lines = ChoreText.results(steps, texts: row.textTo != nil)
        let ok = lines.filter { !$0.failed }.map(\.text)
        return VStack(alignment: .leading, spacing: Theme.sp1) {
            if !ok.isEmpty {
                Text(ok.joined(separator: " · "))
                    .font(Deck.mono(11, .medium, relativeTo: .caption))
                    .foregroundStyle(Deck.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(lines.filter(\.failed), id: \.text) { DeckErrorText($0.text) }
        }
        .padding(.leading, 20 + Theme.sp3)  // under the title, past the check
    }
}

/// The words on a chore row. Pure, so the tests pin them.
enum ChoreText {
    /// "dinner" -> "Dinner"; the rest as written.
    static func title(_ task: String) -> String { task.prefix(1).uppercased() + task.dropFirst() }

    /// "20:00" -> "8 PM", "19:30" -> "7:30 PM" (in the phone's locale).
    static func time(_ hhmm: String) -> String {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2, let d = Calendar.current.date(from: DateComponents(hour: p[0], minute: p[1])) else {
            return hhmm
        }
        return p[1] == 0 ? d.formatted(.dateTime.hour()) : d.formatted(.dateTime.hour().minute())
    }

    /// "2026-10-03" -> "Saturday".
    static func weekday(_ ymd: String) -> String {
        Brief.parseDate(ymd)?.formatted(.dateTime.weekday(.wide)) ?? ymd
    }

    /// One entry per step worth saying. The text step is left out for rows
    /// that never text (it is always "skipped" there).
    static func results(_ s: ChoreSteps, texts: Bool) -> [(text: String, failed: Bool)] {
        var out: [(text: String, failed: Bool)] = []
        switch outcome(s.skylight) {
        case .ok: out.append(("Skylight done", false))
        case .skipped(let why):
            let short = why.replacingOccurrences(of: " in Skylight", with: "")
                .replacingOccurrences(of: "Skylight ", with: "")
            out.append(("Skylight: \(short.isEmpty ? "skipped" : short)", false))
        case .failed(let m): out.append(("Skylight failed: \(m)", true))
        }
        switch outcome(s.alerts) {
        case .ok: out.append(("Alerts off", false))
        case .skipped(let why): out.append(("Alerts: \(why.isEmpty ? "skipped" : why)", false))
        case .failed(let m): out.append(("Alerts failed: \(m)", true))
        }
        if texts {
            switch outcome(s.text) {
            case .ok: out.append(("Texted contact", false))
            case .skipped(let why): out.append(("Text: \(why.isEmpty ? "skipped" : why)", false))
            case .failed(let m): out.append(("Text to contact failed: \(m)", true))
            }
        }
        return out
    }

    private enum Outcome { case ok, skipped(String), failed(String) }

    private static func outcome(_ step: String) -> Outcome {
        if step == "done" || step == "already" { return .ok }
        if step.hasPrefix("failed") { return .failed(detail(step, "failed")) }
        if step.hasPrefix("skipped") { return .skipped(detail(step, "skipped")) }
        return .failed(step)  // an answer this app doesn't know is not a success
    }

    private static func detail(_ step: String, _ head: String) -> String {
        String(step.dropFirst(head.count)).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    }
}
