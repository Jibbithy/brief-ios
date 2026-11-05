import Foundation
import Observation
import WidgetKit

/// The brief on screen, and the one place that refreshes it.
///
/// CACHE FIRST. `init` reads the App Group copy synchronously, so the first
/// frame already has yesterday's (or this morning's) brief on it; `refresh()`
/// then replaces it when the hub answers. A failed refresh never blanks a
/// brief that is on screen - it only sets `problem`.
@MainActor
@Observable
final class BriefStore {
    static let shared = BriefStore()

    private(set) var brief: Brief?
    /// When the brief on screen was fetched.
    private(set) var updatedAt: Date?
    /// The hub answered 404 and there is nothing cached: the empty state.
    private(set) var noBriefYet = false
    private(set) var loading = false
    /// The last refresh failed. Shown over a cached brief, not instead of it.
    private(set) var problem: String?

    init() {
        if DemoMode.isActive {
            if !DemoMode.empty {
                brief = .sample()
                updatedAt = brief?.generatedAt
            } else {
                noBriefYet = true
            }
            return
        }
        brief = BriefCache.load()
        updatedAt = brief == nil ? nil : BriefCache.savedAt()
    }

    func refresh() async {
        if DemoMode.isActive || loading { return }
        let token: String
        switch TokenStore.read() {
        case .token(let t): token = t
        case .missing:
            HubToken.shared.rejected(nil)
            return
        case .locked:
            problem = "The phone is locked. Unlock it, then pull to refresh."
            return
        }
        loading = true
        defer { loading = false }
        // The chores rows are live, not in the brief: fetched alongside it.
        async let chores: Void = ChoresStore.shared.refresh(token: token)
        let result = await BriefAPI.fetch(token: token, session: BriefAPI.session(timeout: 20))
        await chores
        switch result {
        case .brief(let b, let data):
            BriefCache.save(data)
            brief = b
            updatedAt = Date()
            noBriefYet = false
            problem = nil
            WidgetCenter.shared.reloadTimelines(ofKind: Config.widgetKind)
        case .none:
            noBriefYet = brief == nil
            problem = nil
        case .unauthorized:
            // Back to the token screen (see HubToken.rejected).
            HubToken.shared.rejected(token)
            problem = result.message
        case .unreachable, .failed:
            problem = result.message
        }
    }
}
