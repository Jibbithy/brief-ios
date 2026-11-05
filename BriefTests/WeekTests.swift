import XCTest

@testable import Brief

/// The week view, the expandable details and the subscriptions section:
/// what the hub added after the first release, and how the app reads it.
final class WeekTests: XCTestCase {
    private func decode(_ json: String) throws -> Brief {
        try Brief.decode(Data(json.utf8))
    }

    private let day = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_790_431_200))
    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        day.addingTimeInterval(TimeInterval(d * 86400 + h * 3600 + m * 60))
    }

    func testWeekFieldsDecode() throws {
        let b = try decode(
            """
            { "version": 1, "generatedAt": "2026-09-26T14:00:00Z", "date": "2026-09-26", "headline": "h",
              "calendar": [ { "title": "Review", "start": "2026-09-26T16:00:00Z", "end": "2026-09-26T17:30:00Z",
                              "allDay": false, "location": "Room 4", "notes": "Agenda:\\n- Q3",
                              "calendar": "Work", "url": "https://meet.example/abc",
                              "organizer": "host@example.com", "attendees": 5 } ],
              "upcoming": [ { "title": "Dentist", "start": "2026-09-28T21:00:00Z", "end": null, "allDay": false,
                              "location": null, "notes": null, "calendar": "Home", "url": null,
                              "organizer": null, "attendees": 0 } ],
              "emails": [ { "from": "Jo <jo@example.com>", "subject": "Invoice", "why": "Due Friday",
                            "receivedAt": "2026-09-26T12:00:00Z", "snippet": "Please pay by Friday." } ],
              "subscriptions": [ { "name": "StreamCo", "amount": 15.49, "currency": "USD",
                                   "dueDate": "2026-09-30", "source": "ledger" } ],
              "rack": null, "errors": [] }
            """)
        let e = b.calendar[0]
        XCTAssertEqual(e.notes, "Agenda:\n- Q3")
        XCTAssertEqual(e.calendarName, "Work")
        XCTAssertEqual(e.url, "https://meet.example/abc")
        XCTAssertEqual(e.organizer, "host@example.com")
        XCTAssertEqual(e.attendees, 5)
        XCTAssertEqual(b.upcoming.map(\.title), ["Dentist"])
        XCTAssertEqual(b.upcoming[0].calendarName, "Home")
        XCTAssertEqual(b.emails[0].snippet, "Please pay by Friday.")
        XCTAssertEqual(b.subscriptions, [Brief.Subscription(name: "StreamCo", amount: 15.49, currency: "USD", dueDate: "2026-09-30", source: "ledger")])
    }

    func testBriefFromBeforeTheWeekViewStillDecodes() throws {
        let b = try decode(
            """
            { "version": 1, "generatedAt": "2026-09-26T14:00:00Z", "date": "2026-09-26", "headline": "h",
              "calendar": [ { "title": "Standup", "start": "2026-09-26T15:30:00Z", "end": null, "allDay": false, "location": null } ],
              "emails": [ { "from": "a", "subject": "b", "why": "c", "receivedAt": null } ],
              "rack": null, "errors": [] }
            """)
        XCTAssertTrue(b.upcoming.isEmpty)
        XCTAssertTrue(b.subscriptions.isEmpty)
        let e = b.calendar[0]
        XCTAssertNil(e.notes)
        XCTAssertNil(e.calendarName)
        XCTAssertNil(e.link)
        XCTAssertNil(e.organizer)
        XCTAssertNil(e.attendees)
        XCTAssertNil(b.emails[0].snippet)
    }

    func testABadSubscriptionCostsOnlyItself() throws {
        let b = try decode(
            """
            { "generatedAt": "2026-09-26T14:00:00Z", "date": "2026-09-26", "headline": "h",
              "subscriptions": [ { "name": "Bad", "amount": "lots" },
                                 { "name": "MusicCo", "amount": 11.99, "currency": "USD", "dueDate": "2026-09-28", "source": "ledger" } ] }
            """)
        XCTAssertEqual(b.subscriptions.map(\.name), ["MusicCo"])
    }

    func testOnlyAWebURLIsALink() {
        func ev(_ u: String?) -> Brief.Event { Brief.Event(title: "x", start: day, url: u) }
        XCTAssertEqual(ev("https://meet.example/a").link?.absoluteString, "https://meet.example/a")
        XCTAssertEqual(ev("http://x.example").link?.host, "x.example")
        XCTAssertNil(ev("javascript:alert(1)").link)
        XCTAssertNil(ev("tel:5551234").link)
        XCTAssertNil(ev("").link)
        XCTAssertNil(ev(nil).link)
    }

    func testDurationText() {
        XCTAssertEqual(Brief.Event(title: "x", start: at(0, 9), end: at(0, 9, 30)).durationText, "30 min")
        XCTAssertEqual(Brief.Event(title: "x", start: at(0, 9), end: at(0, 10)).durationText, "1 hr")
        XCTAssertEqual(Brief.Event(title: "x", start: at(0, 9), end: at(0, 10, 45)).durationText, "1 hr 45 min")
        XCTAssertNil(Brief.Event(title: "x", start: at(0, 9)).durationText)
        XCTAssertEqual(Brief.Event(title: "x", start: at(0, 0), end: at(1, 0), allDay: true).durationText, "All day")
        XCTAssertEqual(Brief.Event(title: "x", start: at(0, 0), end: at(3, 0), allDay: true).durationText, "3 days")
    }

    func testUpcomingGroupsByDayInReadingOrder() {
        let b = Brief(
            generatedAt: at(0, 8), date: "x", headline: "", weather: nil, calendar: [],
            upcoming: [
                Brief.Event(title: "Tue 8", start: at(2, 8)),
                Brief.Event(title: "Mon 9", start: at(1, 9)),
                Brief.Event(title: "Tue all day", start: at(2, 0), allDay: true),
                Brief.Event(title: "Mon 7", start: at(1, 7)),
            ],
            emails: [], rack: nil)
        let days = b.upcomingDays
        XCTAssertEqual(days.map(\.day), [at(1, 0), at(2, 0)])
        XCTAssertEqual(days.map { $0.events.map(\.title) }, [["Mon 7", "Mon 9"], ["Tue all day", "Tue 8"]])
    }

    func testSubscriptionsSoonestFirstWithMoneyText() {
        let b = Brief(
            generatedAt: at(0, 8), date: "x", headline: "", weather: nil, calendar: [], emails: [],
            subscriptions: [
                Brief.Subscription(name: "B", amount: 15.49, currency: "USD", dueDate: "2026-10-01", source: "ledger"),
                Brief.Subscription(name: "A", amount: 1200, currency: "USD", dueDate: "2026-09-28", source: "ledger"),
            ],
            rack: nil)
        XCTAssertEqual(b.dueSubscriptions.map(\.name), ["A", "B"])
        XCTAssertEqual(b.dueSubscriptions[1].amountText, "$15.49")
        XCTAssertEqual(b.dueSubscriptions[0].amountText, "$1,200.00")
        let c = Calendar.current.dateComponents([.year, .month, .day], from: b.dueSubscriptions[0].due!)
        XCTAssertEqual([c.year, c.month, c.day], [2026, 9, 28])
    }

    func testSampleHasAWeekAndPayments() {
        let s = Brief.sample(now: at(0, 9))
        XCTAssertFalse(s.upcoming.isEmpty)
        XCTAssertFalse(s.subscriptions.isEmpty)
        XCTAssertTrue(s.upcoming.allSatisfy { $0.start >= at(1, 0) && $0.start < at(8, 0) })
        XCTAssertTrue(s.calendar.contains { $0.notes != nil && $0.link != nil })
        XCTAssertTrue(s.emails.allSatisfy { $0.snippet != nil })
    }
}
