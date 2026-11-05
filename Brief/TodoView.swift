import SwiftUI

/// The To-Do tab: the vault note's Personal and Work lists. Tap to check off
/// (tap again within a few seconds to undo), + to add. Pull to refresh.
struct TodoView: View {
    private let store = TodoStore.shared
    @State private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sp5) {
                if let problem = store.problem {
                    DeckAlert(store.list == nil ? .crit : .warn, message: problem)
                }
                if let list = store.list {
                    if list.count == 0 && store.checked.isEmpty {
                        DeckEmpty(
                            label: "To-Do", title: "All clear.",
                            message: "Add one with +, or in the To-Do List note in Obsidian.")
                    } else {
                        ForEach(TodoSection.allCases, id: \.self) { section in
                            TodoSectionView(section: section, items: list[section])
                        }
                    }
                } else if store.problem == nil {
                    DeckHint("Loading the to-do list…")
                }
            }
            .padding(Theme.sp4)
        }
        .refreshable { await store.refresh() }
        .safeAreaInset(edge: .top, spacing: 0) { bar }
        .deckGround()
        .sheet(isPresented: $adding) {
            AddTodoSheet(onClose: { adding = false }).deckSheet()
        }
        .task { await store.refresh() }
    }

    private var bar: some View {
        HStack(spacing: Theme.sp3) {
            Text("To-Do")
                .font(Deck.title)
                .textCase(.uppercase)
                .foregroundStyle(Deck.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if store.loading { DeckChip("Updating", kind: .plain, status: .idle) }
            Button {
                adding = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(DeckIconButtonStyle(.primary, side: 40))
            .accessibilityLabel("Add a to-do")
        }
        .padding(.horizontal, Theme.sp4)
        .padding(.vertical, Theme.sp3)
        .deckBar(.top)
    }
}

struct TodoSectionView: View {
    let section: TodoSection
    let items: [TodoItem]
    private let store = TodoStore.shared

    private var open: Int { items.filter { !store.checked.contains(TodoKey(section: section, text: $0.text)) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sp2) {
            SectionHead(title: section.title, count: open)
            if items.isEmpty {
                unavailable("Nothing here.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element) { i, item in
                        if i > 0 { Rectangle().fill(Deck.hair).frame(height: Deck.borderWidth) }
                        let key = TodoKey(section: section, text: item.text)
                        TodoRow(
                            item: item, checked: store.checked.contains(key), busy: store.busy.contains(key),
                            onTap: { Task { await store.toggle(key) } })
                    }
                }
                .deckCard()
            }
        }
    }
}

struct TodoRow: View {
    let item: TodoItem
    let checked: Bool
    let busy: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: Theme.sp3) {
                DeckCheck(state: checked ? .on : .off)
                Text(item.text)
                    .font(Deck.sans(15, .bold, relativeTo: .body))
                    .foregroundStyle(checked ? Deck.muted : Deck.ink)
                    .strikethrough(checked, color: Deck.muted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.vertical, Theme.sp3)
            .padding(.horizontal, Theme.sp4)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(checked ? "Undo" : "Check off")
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    @ViewBuilder private var trailing: some View {
        if busy {
            ProgressView().tint(Deck.ink)
        } else if checked {
            Text("Undo")
                .font(Deck.mono(12, .semibold, relativeTo: .footnote))
                .textCase(.uppercase)
                .foregroundStyle(Deck.accentInk)
        } else if let due = TodoDue.tag(item.due) {
            DeckChip(due.label, kind: due.kind == .overdue ? .crit : due.kind == .today ? .warn : .plain)
        }
    }

    private var accessibilityText: String {
        var s = item.text
        if let due = TodoDue.tag(item.due) { s += due.kind == .overdue ? ", overdue, was due \(due.label)" : ", due \(due.label)" }
        if checked { s += ", checked off" }
        return s
    }
}

// MARK: - Add

struct AddTodoSheet: View {
    var onClose: () -> Void
    private let store = TodoStore.shared
    @State private var text = ""
    @State private var section: TodoSection = .personal
    @State private var hasDue = false
    @State private var due = Date()
    @State private var saving = false
    /// Why the last Save didn't land. The sheet stays open with the text in it.
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sp5) {
                if let error { DeckAlert(.crit, message: error) }
                VStack(alignment: .leading, spacing: Theme.sp2) {
                    SectionHead(title: "To-do")
                    TextField("What needs doing?", text: $text, axis: .vertical)
                        .textFieldStyle(DeckFieldStyle())
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                }
                VStack(alignment: .leading, spacing: Theme.sp2) {
                    SectionHead(title: "List")
                    DeckSegmented(selection: $section, options: TodoSection.allCases.map { ($0, $0.title) })
                }
                VStack(alignment: .leading, spacing: Theme.sp2) {
                    SectionHead(title: "Due")
                    DeckSegmented(selection: $hasDue, options: [(false, "No date"), (true, "Pick a date")])
                    if hasDue {
                        DatePicker("Due", selection: $due, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                    }
                }
            }
            .padding(Theme.sp4)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: Theme.sp3) {
                Button("Cancel") { onClose() }.buttonStyle(.deckGhost)
                Text("Add")
                    .font(Deck.title)
                    .textCase(.uppercase)
                    .foregroundStyle(Deck.ink)
                    .frame(maxWidth: .infinity)
                if saving {
                    ProgressView().tint(Deck.ink).frame(width: 64)
                } else {
                    Button("Save") { Task { await save() } }
                        .buttonStyle(.deckPrimary)
                        .disabled(trimmed.isEmpty)
                }
            }
            .padding(Theme.sp4)
            .deckBar(.top)
        }
        .deckGround()
        .onAppear { focused = true }
    }

    private func save() async {
        guard !trimmed.isEmpty, !saving else { return }
        saving = true
        defer { saving = false }
        error = nil
        if await store.add(section, text: trimmed, due: hasDue ? TodoDue.ymd(due) : nil) {
            onClose()
        } else {
            error = store.problem ?? "The note didn't take it. Try again."
        }
    }
}
