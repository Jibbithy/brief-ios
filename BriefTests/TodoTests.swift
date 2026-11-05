import XCTest

@testable import Brief

/// The To-Do tab: what /api/todos answers, how an answer is classified, and
/// the words and colour of a due chip.
final class TodoTests: XCTestCase {
    private let json = Data(
        #"{"personal":[{"text":"Buy stamps","due":"2026-10-03"},{"text":"Call the dentist","due":null}],"work":[]}"#.utf8)

    func testDecodesTheHubList() throws {
        let list = try JSONDecoder().decode(TodoList.self, from: json)
        XCTAssertEqual(list[.personal], [TodoItem(text: "Buy stamps", due: "2026-10-03"), TodoItem(text: "Call the dentist", due: nil)])
        XCTAssertEqual(list[.work], [])
        XCTAssertEqual(list.count, 2)
    }

    func testClassify200IsTheList() {
        XCTAssertEqual(BriefAPI.classifyTodo(status: 200, data: json), .list(try! JSONDecoder().decode(TodoList.self, from: json)))
    }

    func testClassify409CarriesTheCurrentList() {
        let body = Data(#"{"error":"no such open item","todos":{"personal":[],"work":[{"text":"A","due":null}]}}"#.utf8)
        XCTAssertEqual(BriefAPI.classifyTodo(status: 409, data: body), .gone(TodoList(personal: [], work: [TodoItem(text: "A", due: nil)])))
    }

    func testClassifyErrors() {
        XCTAssertEqual(BriefAPI.classifyTodo(status: 401, data: Data()), .failed(.unauthorized))
        XCTAssertEqual(
            BriefAPI.classifyTodo(status: 400, data: Data(#"{"error":"text must not be empty"}"#.utf8)),
            .failed(.failed(400, "The hub answered 400: text must not be empty")))
        // A hub without the route yet.
        XCTAssertEqual(
            BriefAPI.classifyTodo(status: 404, data: Data(#"{"error":"not found"}"#.utf8)),
            .failed(.failed(404, "This hub has no to-do list yet. Deploy rack-control.")))
        if case .failed(.failed(409, _)) = BriefAPI.classifyTodo(status: 409, data: Data("{}".utf8)) {} else {
            XCTFail("a 409 with no list is a plain failure")
        }
    }

    func testAddBodyOmitsAMissingDate() throws {
        let r = BriefAPI.todoRequest("/api/todos", section: .work, text: "Ship", due: nil, token: "t")
        let body = try JSONSerialization.jsonObject(with: r.httpBody!) as! [String: String]
        XCTAssertEqual(body, ["section": "work", "text": "Ship"])
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "x-rack-token"), "t")
        let dated = BriefAPI.todoRequest("/api/todos", section: .personal, text: "A", due: "2026-10-01", token: "t")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: dated.httpBody!) as! [String: String],
                       ["section": "personal", "text": "A", "due": "2026-10-01"])
    }

    // MARK: due chips

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }
    private func noon(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testDueChips() {
        let now = noon(2026, 9, 28)
        XCTAssertEqual(TodoDue.tag("2026-09-27", now: now, calendar: cal)?.kind, .overdue)
        XCTAssertEqual(TodoDue.tag("2026-09-28", now: now, calendar: cal), TodoDue(kind: .today, label: "Today"))
        XCTAssertEqual(TodoDue.tag("2026-09-29", now: now, calendar: cal), TodoDue(kind: .later, label: "Tomorrow"))
        XCTAssertEqual(TodoDue.tag("2026-10-03", now: now, calendar: cal)?.kind, .later)
        XCTAssertNil(TodoDue.tag(nil, now: now, calendar: cal))
        XCTAssertNil(TodoDue.tag("soon", now: now, calendar: cal))
    }

    func testDateToYmdIsLocal() {
        let late = cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 23, minute: 30))!
        XCTAssertEqual(TodoDue.ymd(late, calendar: cal), "2026-10-03")
    }

    // MARK: the store's local edits

    func testRemovingOneItemLeavesTheRest() {
        var list = TodoList(personal: [TodoItem(text: "A", due: nil), TodoItem(text: "B", due: nil)], work: [])
        list.remove(TodoKey(section: .personal, text: "A"))
        XCTAssertEqual(list[.personal], [TodoItem(text: "B", due: nil)])
        list.remove(TodoKey(section: .work, text: "B"))
        XCTAssertEqual(list[.personal].count, 1)
    }
}
