import Foundation

/// `GET /api/todos`: the open items in the vault note "To-Do List.md", one
/// list per `## Personal` / `## Work` section. LIVE from the hub, not part of
/// the 8 AM brief - the note is edited in Obsidian and from this app all day.
struct TodoList: Codable, Equatable, Sendable {
    var personal: [TodoItem]
    var work: [TodoItem]

    static let empty = TodoList(personal: [], work: [])

    subscript(section: TodoSection) -> [TodoItem] {
        get { section == .personal ? personal : work }
        set { if section == .personal { personal = newValue } else { work = newValue } }
    }

    var count: Int { personal.count + work.count }

    /// Drops the first item `key` names (a checked item whose Undo ran out).
    mutating func remove(_ key: TodoKey) {
        if let i = self[key.section].firstIndex(where: { $0.text == key.text }) { self[key.section].remove(at: i) }
    }
}

struct TodoItem: Codable, Equatable, Hashable, Sendable {
    let text: String
    /// YYYY-MM-DD, or nil.
    let due: String?
}

enum TodoSection: String, CaseIterable, Codable, Sendable {
    case personal, work
    var title: String { self == .personal ? "Personal" : "Work" }
}

/// How the hub names an item: its section and its text. Never a position -
/// Obsidian edits the same note, so a line number goes stale.
struct TodoKey: Hashable, Sendable {
    let section: TodoSection
    let text: String
}

/// A due date as a chip: red once it has passed, amber on the day.
struct TodoDue: Equatable {
    enum Kind { case overdue, today, later }
    let kind: Kind
    let label: String

    static func tag(_ due: String?, now: Date = Date(), calendar cal: Calendar = .current) -> TodoDue? {
        guard let due, let d = ymdDate(due, calendar: cal) else { return nil }
        let today = cal.startOfDay(for: now)
        let days = cal.dateComponents([.day], from: today, to: d).day ?? 0
        let short = d.formatted(Date.FormatStyle(calendar: cal, timeZone: cal.timeZone).month(.abbreviated).day())
        switch days {
        case ..<0: return TodoDue(kind: .overdue, label: short)
        case 0: return TodoDue(kind: .today, label: "Today")
        case 1: return TodoDue(kind: .later, label: "Tomorrow")
        default: return TodoDue(kind: .later, label: short)
        }
    }

    /// A picked date -> the note's YYYY-MM-DD, in the phone's own day.
    static func ymd(_ date: Date, calendar cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func ymdDate(_ s: String, calendar cal: Calendar) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, s.count == 10 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }
}

/// What one /api/todos call came back as.
enum TodoAnswer: Equatable, Sendable {
    case list(TodoList)
    /// 409: the item was checked, renamed or removed in Obsidian meanwhile.
    /// Carries the note as it is now.
    case gone(TodoList)
    case failed(HubError)
}

extension BriefAPI {
    static func todos(token: String, session: URLSession) async -> TodoAnswer {
        await todoCall(request("/api/todos", token: token), session: session)
    }

    static func addTodo(
        _ section: TodoSection, text: String, due: String?, token: String, session: URLSession
    ) async -> TodoAnswer {
        await todoCall(todoRequest("/api/todos", section: section, text: text, due: due, token: token), session: session)
    }

    /// Check an item off (`done`) or back on.
    static func setTodo(
        _ key: TodoKey, done: Bool, token: String, session: URLSession
    ) async -> TodoAnswer {
        let path = done ? "/api/todos/done" : "/api/todos/undone"
        return await todoCall(todoRequest(path, section: key.section, text: key.text, due: nil, token: token), session: session)
    }

    static func todoRequest(_ path: String, section: TodoSection, text: String, due: String?, token: String) -> URLRequest {
        var body = ["section": section.rawValue, "text": text]
        if let due { body["due"] = due }
        return post(path, body, token: token)
    }

    private static func todoCall(_ r: URLRequest, session: URLSession) async -> TodoAnswer {
        do {
            let (data, resp) = try await session.data(for: r)
            return classifyTodo(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch let e as URLError {
            switch e.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .notConnectedToInternet,
                .networkConnectionLost, .dnsLookupFailed, .secureConnectionFailed:
                return .failed(.unreachable)
            default:
                return .failed(.failed(0, e.localizedDescription))
            }
        } catch {
            return .failed(.failed(0, error.localizedDescription))
        }
    }

    /// Status + body -> answer. Pure, for the tests.
    static func classifyTodo(status: Int, data: Data) -> TodoAnswer {
        struct Gone: Decodable { let todos: TodoList }
        if status == 409, let g = try? JSONDecoder().decode(Gone.self, from: data) { return .gone(g.todos) }
        if status == 404 { return .failed(.failed(404, "This hub has no to-do list yet. Deploy rack-control.")) }
        switch classify(status: status, data: data, as: TodoList.self) {
        case .success(let l): return .list(l)
        case .failure(let e): return .failed(e)
        }
    }
}
