import Foundation
import Observation

/// The To-Do tab's list, and every edit the app makes to the vault note.
///
/// CACHE FIRST, like BriefStore: the last list the hub sent is kept in
/// UserDefaults and shown at launch, so the tab opens with something on it off
/// the tailnet. A failed call never blanks it - it only sets `problem`.
///
/// CHECK-OFF LINGERS. A tapped item is checked in the note at once, but stays
/// on screen struck through for `linger`, where a second tap is Undo. Then it
/// drops off locally; the next refresh agrees with the note anyway.
@MainActor
@Observable
final class TodoStore {
    static let shared = TodoStore()

    private(set) var list: TodoList?
    private(set) var loading = false
    private(set) var problem: String?
    /// Checked off in the note, still on screen with Undo.
    private(set) var checked: Set<TodoKey> = []
    /// An edit to this item is in flight.
    private(set) var busy: Set<TodoKey> = []

    private let linger: Duration = .seconds(4)
    private static let cacheKey = "todos.cache"

    init() {
        if DemoMode.isActive {
            list = DemoMode.empty ? .empty : .sample()
            return
        }
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            list = try? JSONDecoder().decode(TodoList.self, from: data)
        }
    }

    func refresh() async {
        if DemoMode.isActive || loading { return }
        guard let token = token() else { return }
        loading = true
        defer { loading = false }
        apply(await BriefAPI.todos(token: token, session: BriefAPI.session(timeout: 20)), token: token)
    }

    /// Tap on a row: check it off, or Undo if it is still lingering.
    func toggle(_ key: TodoKey) async {
        guard !busy.contains(key) else { return }
        let done = !checked.contains(key)
        busy.insert(key)
        defer { busy.remove(key) }

        if DemoMode.isActive {
            try? await Task.sleep(for: .milliseconds(250))
            return finish(key, done: done)
        }
        guard let token = token() else { return }
        switch await BriefAPI.setTodo(key, done: done, token: token, session: BriefAPI.session(timeout: 20)) {
        case .list:
            problem = nil
            finish(key, done: done)
        case let other:
            checked.remove(key)
            apply(other, token: token)
        }
    }

    /// true when the note took it; the sheet closes only then.
    func add(_ section: TodoSection, text: String, due: String?) async -> Bool {
        if DemoMode.isActive {
            list?[section].append(TodoItem(text: text, due: due))
            return true
        }
        guard let token = token() else { return false }
        let answer = await BriefAPI.addTodo(section, text: text, due: due, token: token, session: BriefAPI.session(timeout: 20))
        apply(answer, token: token)
        if case .list = answer { return true }
        return false
    }

    // MARK: -

    private func finish(_ key: TodoKey, done: Bool) {
        guard done else {
            checked.remove(key)
            return
        }
        checked.insert(key)
        Task {
            try? await Task.sleep(for: linger)
            // Still checked = nobody tapped Undo.
            guard checked.contains(key), !busy.contains(key) else { return }
            checked.remove(key)
            list?.remove(key)
            save()
        }
    }

    /// A hub answer onto the screen. Items still lingering are kept: the
    /// hub's list no longer has them, but the Undo on screen does.
    private func apply(_ answer: TodoAnswer, token: String) {
        switch answer {
        case .list(let l):
            set(l)
            problem = nil
        case .gone(let l):
            set(l)
            problem = "That item changed in Obsidian. This is the list as it is now."
        case .failed(let e):
            if e == .unauthorized { HubToken.shared.rejected(token) }
            problem = e.message
        }
    }

    private func set(_ fresh: TodoList) {
        var l = fresh
        for key in checked {
            guard let old = list?[key.section].first(where: { $0.text == key.text }),
                !l[key.section].contains(old)
            else { continue }
            l[key.section].append(old)
        }
        list = l
        save()
    }

    private func save() {
        guard !DemoMode.isActive, let list, let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    private func token() -> String? {
        switch TokenStore.read() {
        case .token(let t): return t
        case .missing:
            HubToken.shared.rejected(nil)
            return nil
        case .locked:
            problem = "The phone is locked. Unlock it, then try again."
            return nil
        }
    }
}

extension TodoList {
    /// Demo rows: one overdue, one today, one undated, and a work item.
    static func sample(now: Date = Date(), calendar cal: Calendar = .current) -> TodoList {
        func day(_ n: Int) -> String { TodoDue.ymd(cal.date(byAdding: .day, value: n, to: now)!, calendar: cal) }
        return TodoList(
            personal: [
                TodoItem(text: "Water the plants", due: day(-1)),
                TodoItem(text: "Buy stamps", due: day(0)),
                TodoItem(text: "Call the dentist", due: nil),
            ],
            work: [
                TodoItem(text: "Send client invoice", due: day(3)),
                TodoItem(text: "Review open tickets", due: nil),
            ])
    }
}
