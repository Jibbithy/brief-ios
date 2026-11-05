import CryptoKit
import XCTest

@testable import Brief

/// The chore "Done" contract. The vectors must match the signing service's own
/// tests - change one, change both.
final class ChoreTests: XCTestCase {
    private let eventId = "https://caldav.icloud.com/1/calendars/home/abc.ics"

    // MARK: fixtures

    private func weeklyRow(task: String = "dinner", textTo: String? = nil) -> ChoreRow {
        ChoreRow(
            id: "weekly:2026-09-28:dinner@2026-10-03", task: task, kind: "weekly", date: "2026-10-03",
            deadline: "20:00", eventId: eventId, occurrence: "2026-10-03T19:00", textTo: textTo, done: nil)
    }

    private func saturdayRow(task: String = "vacuum the living room") -> ChoreRow {
        ChoreRow(
            id: "day:2026-10-03:vacuum", task: task, kind: "day", date: "2026-10-03",
            deadline: nil, eventId: eventId, occurrence: "", textTo: "+15555550100", done: nil)
    }

    /// What mailgate would propose for `row`, hashed honestly.
    private func proposal(
        for row: ChoreRow, kind: String = "chore_done", skylightIds: [String] = ["sk1"],
        edit: (inout ChorePending.Message) -> Void = { _ in }
    ) -> ChorePending {
        var m = ChorePending.Message(
            event_id: row.eventId, occurrence: row.occurrence, date: row.date, task: row.task,
            skylight_ids: skylightIds, skylight_note: skylightIds.isEmpty ? "not found in Skylight" : "",
            chat_guid: "", chat_name: "", recipients: [], text: "")
        if row.textTo != nil {
            m.chat_guid = "any;-;+15555550100"
            m.chat_name = "Contact"
            m.recipients = ["+15555550100"]
            m.text = "Done with \(row.task)"
        }
        edit(&m)
        return ChorePending(
            id: "d_0123456789ab", kind: kind, hash: ChoreApproval.hash(m), expiresAt: 1_790_000_000_000, message: m)
    }

    // MARK: the pinned vectors

    private var vectorMessage: ChorePending.Message {
        ChorePending.Message(
            event_id: eventId, occurrence: "2026-10-03T19:00", date: "2026-10-03", task: "Dinner",
            skylight_ids: ["sk1", "sk2"], skylight_note: "", chat_guid: "any;-;+15555550100", chat_name: "Contact",
            recipients: ["+15555550100"], text: "Done with Dinner")
    }

    func testHashFieldsAreTheContractOrder() {
        XCTAssertEqual(
            ChoreApproval.hashFields(vectorMessage),
            [
                "chore_done", eventId, "2026-10-03T19:00", "2026-10-03", "Dinner", "sk1\nsk2",
                "any;-;+15555550100", "Contact", "+15555550100", "Done with Dinner",
            ])
    }

    func testHashMatchesThePinnedVector() {
        XCTAssertEqual(
            ChoreApproval.hash(vectorMessage), "ae9f066309d31ebdb2096aeb31149f0e47cf24c52f6ce5d31f958d4d9f77dfb6")
    }

    func testSignatureMatchesThePinnedVector() {
        let key = SymmetricKey(data: Data(repeating: 0x07, count: 32))
        XCTAssertEqual(
            ApprovalKey.sign(
                key: key, id: "d_0123456789ab",
                hash: "ae9f066309d31ebdb2096aeb31149f0e47cf24c52f6ce5d31f958d4d9f77dfb6",
                expiresAt: 1_790_000_000_000),
            "5c74c212c6b9332132d5574f5c7f05c14efe48949d8be5bec558a2411cb22920")
    }

    // MARK: decoding the hub's shapes

    func testDecodesAPageAndAPending() throws {
        let page = try JSONDecoder().decode(
            ChoresPage.self,
            from: Data(
                """
                {"today":"2026-10-03",
                 "weekly":[{"id":"w1","task":"dinner","kind":"weekly","date":"2026-10-03","deadline":"20:00",
                            "eventId":"e","occurrence":"2026-10-03T19:00","textTo":null,"done":null}],
                 "day":[{"id":"d1","task":"vacuum","kind":"day","date":"2026-10-03","deadline":null,
                         "eventId":"e","occurrence":"","textTo":"+15555550100",
                         "done":{"at":1790000000000,"steps":{"skylight":"done","alerts":"already","text":"failed: nope"}}}]}
                """.utf8))
        XCTAssertEqual(page.today, "2026-10-03")
        XCTAssertEqual(page.weekly.first?.deadline, "20:00")
        XCTAssertNil(page.weekly.first?.textTo)
        XCTAssertNil(page.weekly.first?.done)
        XCTAssertEqual(page.day.first?.done?.steps.text, "failed: nope")
        XCTAssertEqual(page.day.first?.done?.at, 1_790_000_000_000)

        let pending = try JSONDecoder().decode(
            ChorePending.self,
            from: Data(
                """
                {"pending":0,"id":"d_1","kind":"chore_done","hash":"h","expiresAt":1790000000000,
                 "message":{"event_id":"e","occurrence":"","date":"2026-10-03","task":"vacuum",
                            "skylight_ids":[],"skylight_note":"not set up","chat_guid":"","chat_name":"",
                            "recipients":[],"text":""}}
                """.utf8))
        XCTAssertEqual(pending.message.skylight_note, "not set up")
    }

    // MARK: check - accepts

    func testAcceptsAMatchingWeekly() {
        let row = weeklyRow()
        XCTAssertNil(ChoreApproval.check(row: row, pending: proposal(for: row)))
    }

    func testAcceptsAMatchingWeeklyWithNoSkylightChore() {
        let row = weeklyRow()
        XCTAssertNil(ChoreApproval.check(row: row, pending: proposal(for: row, skylightIds: [])))
    }

    func testAcceptsAMatchingSaturday() {
        let row = saturdayRow()
        XCTAssertNil(ChoreApproval.check(row: row, pending: proposal(for: row)))
    }

    func testAcceptsARecipientShownAsNameAndNumber() {
        let row = saturdayRow()
        let p = proposal(for: row) { $0.recipients = ["Contact (+15555550100)"] }
        XCTAssertNil(ChoreApproval.check(row: row, pending: p))
    }

    // MARK: check - refuses

    func testRefusesWrongKind() {
        let row = weeklyRow()
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row, kind: "imessage")))
    }

    func testRefusesADifferentTask() {
        let row = weeklyRow()
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.task = "dishes" }))
    }

    func testRefusesADifferentEventOccurrenceOrDate() {
        let row = weeklyRow()
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.event_id = "https://x/other.ics" }))
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.occurrence = "2026-10-04T19:00" }))
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.date = "2026-10-04" }))
    }

    func testRefusesATextOnAWeeklyRow() {
        let row = weeklyRow()
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.text = "Done with dinner" }))
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.chat_guid = "any;-;+15555550100" }))
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.recipients = ["+15555550100"] }))
    }

    func testRefusesATextToADifferentNumber() {
        let row = saturdayRow()
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.chat_guid = "any;-;+15555550199" }))
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.recipients = ["+15555550199"] }))
        XCTAssertNotNil(
            ChoreApproval.check(row: row, pending: proposal(for: row) { $0.recipients = ["+15555550100", "+15555550199"] }))
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.recipients = [] }))
    }

    func testRefusesARowWhoseTextToIsNotTheAppsContact() {
        // The hub retargets the ROW and mailgate texts that number honestly:
        // everything matches the row, so only the app's own constant catches it.
        let row = ChoreRow(
            id: "day:x", task: "vacuum", kind: "day", date: "2026-10-03", deadline: nil, eventId: eventId,
            occurrence: "", textTo: "+15555550199", done: nil)
        let p = proposal(for: row) {
            $0.chat_guid = "any;-;+15555550199"
            $0.recipients = ["+15555550199"]
        }
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: p))
    }

    func testRefusesARewordedText() {
        let row = saturdayRow()
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.text = "Done with everything" }))
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: proposal(for: row) { $0.text = "" }))
    }

    func testRefusesATamperedHash() {
        let row = saturdayRow()
        let honest = proposal(for: row)
        let tampered = ChorePending(
            id: honest.id, kind: honest.kind, hash: String(repeating: "0", count: 64), expiresAt: honest.expiresAt,
            message: honest.message)
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: tampered))
    }

    func testRefusesAMessageSwappedUnderAnHonestHash() {
        // The hub keeps mailgate's hash but relays different Skylight ids.
        let row = weeklyRow()
        let honest = proposal(for: row)
        var m = honest.message
        m.skylight_ids = ["someone-elses-chore"]
        let swapped = ChorePending(
            id: honest.id, kind: honest.kind, hash: honest.hash, expiresAt: honest.expiresAt, message: m)
        XCTAssertNotNil(ChoreApproval.check(row: row, pending: swapped))
    }

    // MARK: the hub answers

    func testClassifyMapsMailgateCodesToWords() {
        let r = BriefAPI.classify(
            status: 403, data: Data(#"{"error":"bad sig","code":"bad_signature"}"#.utf8), as: ChoreSteps.self)
        XCTAssertEqual(r, .failure(.failed(403, HubError.words["bad_signature"]!)))
        XCTAssertEqual(BriefAPI.classify(status: 401, data: Data(), as: ChoreSteps.self), .failure(.unauthorized))
        guard case .failure(.failed(502, let m)) = BriefAPI.classify(
            status: 502, data: Data(#"{"error":"boom"}"#.utf8), as: ChoreSteps.self)
        else { return XCTFail() }
        XCTAssertTrue(m.contains("boom"))
        XCTAssertEqual(
            BriefAPI.classify(
                status: 200, data: Data(#"{"skylight":"done","alerts":"already","text":"skipped"}"#.utf8),
                as: ChoreSteps.self),
            .success(ChoreSteps(skylight: "done", alerts: "already", text: "skipped")))
    }

    // MARK: demo rows

    func testSampleSaturdayIsTheComingSaturdayAndPassesTheCheck() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Denver")!
        // Sunday 2026-09-27 -> Saturday 2026-10-03; a Saturday is its own.
        let sunday = cal.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 9))!
        let saturday = cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9))!
        XCTAssertEqual(ChoresPage.sample(now: sunday, calendar: cal).day.first?.date, "2026-10-03")
        XCTAssertEqual(ChoresPage.sample(now: saturday, calendar: cal).day.first?.date, "2026-10-03")
        let page = ChoresPage.sample(now: sunday, calendar: cal)
        XCTAssertEqual(page.weekly.first?.occurrence, "2026-09-27T19:00")
        for row in page.weekly + page.day {
            XCTAssertNil(ChoreApproval.check(row: row, pending: proposal(for: row)), row.id)
        }
    }

    // MARK: row words

    func testRowWords() {
        XCTAssertEqual(ChoreText.title("dinner"), "Dinner")
        XCTAssertEqual(ChoreText.title("vacuum and dust, clean"), "Vacuum and dust, clean")
        XCTAssertEqual(ChoreText.weekday("2026-10-03"), Brief.parseDate("2026-10-03")!.formatted(.dateTime.weekday(.wide)))

        let ok = ChoreText.results(ChoreSteps(skylight: "done", alerts: "already", text: "done"), texts: true)
        XCTAssertEqual(ok.map(\.text), ["Skylight done", "Alerts off", "Texted contact"])
        XCTAssertFalse(ok.contains { $0.failed })

        let weekly = ChoreText.results(
            ChoreSteps(skylight: "skipped: not found in Skylight", alerts: "done", text: "skipped"), texts: false)
        XCTAssertEqual(weekly.map(\.text), ["Skylight: not found", "Alerts off"])

        let bad = ChoreText.results(
            ChoreSteps(skylight: "skipped: Skylight unreachable", alerts: "failed: 412", text: "failed: timed out"),
            texts: true)
        XCTAssertEqual(bad.map(\.text), ["Skylight: unreachable", "Alerts failed: 412", "Text to contact failed: timed out"])
        XCTAssertEqual(bad.map(\.failed), [false, true, true])

        // An answer the app doesn't know is never shown as a success.
        XCTAssertEqual(ChoreText.results(ChoreSteps(skylight: "weird", alerts: "done", text: ""), texts: false).first?.failed, true)
    }
}
