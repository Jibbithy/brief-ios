import SwiftUI

@main
struct BriefApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Deck.registerFonts()
        // After the fonts: the tab bar's labels are built from them.
        DeckChrome.install()
        // Before HubToken.shared's first read. On a phone that already has
        // Agents or Rack Control, the token is already in the shared group and
        // Brief opens straight onto the brief.
        TokenStore.migrateToSharedGroup()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .deckTheme()
                .tint(Deck.accentInk)
                .onChange(of: scenePhase, initial: true) {
                    guard scenePhase == .active, !DemoMode.isActive else { return }
                    TokenStore.migrateToSharedGroup()
                    HubToken.shared.refresh()
                    // Every return to the app pulls a fresh brief behind the
                    // cached one already on screen.
                    if !HubToken.shared.needsToken {
                        Task { await BriefStore.shared.refresh() }
                        Task { await TodoStore.shared.refresh() }
                    }
                }
        }
    }
}

/// Token, then the brief. NO BIOMETRIC GATE, by design: this app opens
/// straight onto today's brief.
struct RootView: View {
    private let hub = HubToken.shared
    @State private var tab: MainTab = DemoMode.opensTodo ? .todo : .brief

    private var needsToken: Bool {
        DemoMode.isActive ? DemoMode.showsTokenEntry : hub.needsToken
    }

    var body: some View {
        if needsToken {
            TokenEntryView()
        } else {
            // Opens on the brief, every launch: it is what the app is for. To-Do
            // is the vault note "To-Do List.md", live (see TodoStore).
            TabView(selection: $tab) {
                Tab("Brief", systemImage: "sun.max", value: .brief) { BriefView() }
                Tab("To-Do", systemImage: "checklist", value: .todo) { TodoView() }
            }
            .task {
                guard !DemoMode.isActive else { return }
                await BriefStore.shared.refresh()
                await PushRegistrar.shared.enable()
            }
        }
    }
}

enum MainTab: Hashable { case brief, todo }
