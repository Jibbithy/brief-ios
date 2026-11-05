import Foundation
import Observation

/// The Chores section: tonight's job and the Saturday list, each with a Done.
///
/// LIVE, NOT CACHED. The rows come from `GET /api/chores` on every Brief
/// refresh (the 8 AM brief is a morning snapshot; a Saturday list lands at
/// 3 PM). A failed refresh keeps the rows on screen.
///
/// ONE TAP = ONE SIGNED ACTION: propose (the hub sends mailgate the row's own
/// fields) -> ChoreApproval.check against the row on screen -> sign with the
/// approval key Agents stored -> done. Nothing is signed that the check refused.
@MainActor
@Observable
final class ChoresStore {
    static let shared = ChoresStore()

    private(set) var page: ChoresPage?
    /// Row ids with a Done in flight.
    private(set) var busy: Set<String> = []
    /// Why a row's Done didn't go through, by row id.
    private(set) var problem: [String: String] = [:]

    init() {
        if DemoMode.isActive && !DemoMode.empty {
            page = .sample()
            if DemoMode.showsChoreStates { showStates() }
        }
    }

    /// Reads the token itself; BriefStore passes the one it already has.
    func refresh() async {
        guard !DemoMode.isActive, case .token(let t) = TokenStore.read() else { return }
        await refresh(token: t)
    }

    func refresh(token: String) async {
        if DemoMode.isActive { return }
        // 401 and unreachable are BriefStore's to report, from the same refresh.
        if case .success(let p) = await BriefAPI.chores(token: token, session: BriefAPI.session(timeout: 20)) {
            page = p
        }
    }

    func done(_ row: ChoreRow) async {
        guard !busy.contains(row.id), row.done == nil else { return }
        busy.insert(row.id)
        problem[row.id] = nil
        defer { busy.remove(row.id) }

        if DemoMode.isActive {
            try? await Task.sleep(for: .milliseconds(500))
            mark(row.id, steps: ChoreSteps(skylight: "done", alerts: "done", text: row.textTo == nil ? "skipped" : "done"))
            return
        }
        let token: String
        switch TokenStore.read() {
        case .token(let t): token = t
        case .locked:
            problem[row.id] = "The phone is locked. Unlock it, then tap Done."
            return
        case .missing:
            HubToken.shared.rejected(nil)
            return
        }
        // BEFORE proposing, so a missing key doesn't leave an item waiting in mailgate.
        guard let key = ApprovalKey.load() else {
            problem[row.id] = "Set the approval key in Agents first."
            return
        }
        let session = BriefAPI.session(timeout: 30)
        let pending: ChorePending
        switch await BriefAPI.proposeChore(id: row.id, token: token, session: session) {
        case .success(let p): pending = p
        case .failure(let e): return fail(row.id, e, token: token)
        }
        if let why = ChoreApproval.check(row: row, pending: pending) {
            problem[row.id] = "Not sent: \(why)"
            return
        }
        let sig = ApprovalKey.sign(key: key, id: pending.id, hash: pending.hash, expiresAt: pending.expiresAt)
        switch await BriefAPI.finishChore(id: row.id, approval: pending.id, sig: sig, token: token, session: session) {
        case .success(let steps): mark(row.id, steps: steps)
        case .failure(let e): return fail(row.id, e, token: token)
        }
        await refresh(token: token)
    }

    private func fail(_ id: String, _ e: HubError, token: String) {
        if e == .unauthorized { HubToken.shared.rejected(token) }
        problem[id] = e.message
    }

    /// Shows the result at once; the refresh that follows replaces it with the
    /// hub's own record.
    private func mark(_ id: String, steps: ChoreSteps) {
        guard let page else { return }
        let done = ChoreDone(at: Int64(Date().timeIntervalSince1970 * 1000), steps: steps)
        self.page = ChoresPage(
            today: page.today, weekly: page.weekly.map { $0.id == id ? $0.marked(done) : $0 },
            day: page.day.map { $0.id == id ? $0.marked(done) : $0 })
    }

    /// Demo only: every state a row can be in, for one screenshot.
    private func showStates() {
        guard let page, let dinner = page.weekly.first, page.day.count == 2 else { return }
        problem[dinner.id] = "Set the approval key in Agents first."
        busy.insert(page.day[0].id)
        mark(
            page.day[1].id,
            steps: ChoreSteps(skylight: "skipped: not found in Skylight", alerts: "done", text: "failed: iMessage timed out"))
    }
}

extension ChoreRow {
    func marked(_ done: ChoreDone) -> ChoreRow {
        ChoreRow(
            id: id, task: task, kind: kind, date: date, deadline: deadline, eventId: eventId,
            occurrence: occurrence, textTo: textTo, done: done)
    }
}

extension ChoresPage {
    /// Demo rows for `now`'s day: tonight's dinner, and the coming Saturday's
    /// list (one row already done).
    static func sample(now: Date = Date(), calendar cal: Calendar = .current) -> ChoresPage {
        let day = cal.startOfDay(for: now)
        let toSaturday = (7 - cal.component(.weekday, from: day)) % 7  // weekday 7 = Saturday
        func ymd(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        let today = ymd(day)
        let saturday = ymd(cal.date(byAdding: .day, value: toSaturday, to: day)!)
        let ev = "https://caldav.icloud.com/demo/calendars/home/"
        func dayRow(_ slug: String, _ task: String, done: ChoreDone? = nil) -> ChoreRow {
            ChoreRow(
                id: "day:\(saturday):\(slug)", task: task, kind: "day", date: saturday, deadline: nil,
                eventId: ev + "\(slug).ics", occurrence: "", textTo: ChoreApproval.contact, done: done)
        }
        return ChoresPage(
            today: today,
            weekly: [
                ChoreRow(
                    id: "weekly:\(today):dinner@\(today)", task: "dinner", kind: "weekly", date: today,
                    deadline: "20:00", eventId: ev + "dinner.ics", occurrence: "\(today)T19:00", textTo: nil, done: nil)
            ],
            day: [
                dayRow("vacuum", "vacuum the living room"),
                dayRow(
                    "trash", "take out the recycling",
                    done: ChoreDone(
                        at: Int64(day.timeIntervalSince1970 * 1000),
                        steps: ChoreSteps(skylight: "done", alerts: "done", text: "done"))),
            ])
    }
}
