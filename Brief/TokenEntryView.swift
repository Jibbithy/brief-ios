import SwiftUI

/// The one screen that writes a credential - agents-ios TokenEntryView, with
/// the token proved against `/api/brief` instead of `/api/conversations`.
///
/// Usually never seen: the token is shared with Agents and Rack Control, so a
/// phone that has either opens Brief straight onto the brief.
struct TokenEntryView: View {
    var onClose: (() -> Void)? = nil

    @State private var typed = ""
    @State private var checking = false
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.sp4 + Theme.sp2) {
                DeckFormSection(title: "Hub token") {
                    VStack(alignment: .leading, spacing: Theme.sp2) {
                        TextField(
                            "x-rack-token", text: $typed,
                            prompt: Text("x-rack-token").foregroundStyle(Deck.muted),
                            axis: .vertical
                        )
                        .textFieldStyle(DeckFieldStyle(invalid: problem != nil, mono: true))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .lineLimit(2...4)
                        Text("On the hub host: cat /path/to/rack-hub/token")
                            .font(Deck.mono(12, .regular, relativeTo: .footnote))
                            .foregroundStyle(Deck.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Theme.sp3)
                }

                if let problem {
                    DeckErrorText(problem)
                }

                Button(checking ? "Checking…" : "Save") { Task { await check() } }
                    .buttonStyle(.deckPrimary)
                    .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
            }
            .padding(Theme.sp4)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Brief")
                    .font(Deck.title)
                    .textCase(.uppercase)
                    .foregroundStyle(Deck.ink)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let onClose {
                    Button("Cancel") { onClose() }
                        .buttonStyle(.deckGhost)
                }
            }
            .padding(.horizontal, Theme.sp4)
            .padding(.vertical, Theme.sp4)
            .deckBar(.top)
        }
        .deckGround()
    }

    /// Prove the token before storing it, so a typo never replaces a token
    /// that worked.
    private func check() async {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        checking = true
        problem = nil
        defer { checking = false }
        if await BriefAPI.validate(t) {
            HubToken.shared.saved(t)
            onClose?()
            await BriefStore.shared.refresh()
        } else {
            problem = "That token was rejected, or the rack is unreachable. Is Tailscale on?"
        }
    }
}
