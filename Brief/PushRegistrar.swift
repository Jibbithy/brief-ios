import UIKit
import UserNotifications

/// Asks for notifications, tells the hub where to send the morning push, and
/// makes a tap on it (or its arrival while open) refresh the brief.
///
/// Same shape as agents-ios PushRegistrar: called from the brief branch of
/// RootView (so the prompt lands after a token exists), re-run on every
/// appearance because a device token can change under a restore, and the
/// environment read off the embedded profile rather than guessed from DEBUG.
@MainActor
final class PushRegistrar: NSObject {
    static let shared = PushRegistrar()

    private var enabling = false

    func enable() async {
        if enabling { return }
        enabling = true
        defer { enabling = false }

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return
        }
        guard granted else { return }
        // Main thread only - see agents-ios.
        UIApplication.shared.registerForRemoteNotifications()
    }

    func received(deviceToken: Data) {
        let hex = Self.hex(deviceToken)
        Task {
            guard let token = TokenStore.load() else { return }
            _ = await BriefAPI.registerForPush(token: token, deviceToken: hex, environment: Self.apsEnvironment)
        }
    }

    /// Hex by hand: `deviceToken.description` has been "32 bytes" since iOS 13.
    nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// `{kind: "brief", date}` - the only push this bundle gets.
    nonisolated static func isBrief(_ info: [AnyHashable: Any]) -> Bool {
        (info["kind"] as? String) == "brief"
    }

    /// "sandbox" unless the embedded profile says production. A Release build
    /// installed with a development profile is still a sandbox token.
    nonisolated static var apsEnvironment: String {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let raw = try? Data(contentsOf: url),
            let start = raw.range(of: Data("<plist".utf8)),
            let end = raw.range(of: Data("</plist>".utf8))
        else { return "sandbox" }
        let plist = raw[start.lowerBound..<end.upperBound]
        guard let parsed = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
            let entitlements = parsed["Entitlements"] as? [String: Any],
            let aps = entitlements["aps-environment"] as? String
        else { return "sandbox" }
        return aps == "production" ? "production" : "sandbox"
    }
}

extension PushRegistrar: UNUserNotificationCenterDelegate {
    /// The brief landed while the app is open: show it AND refresh, so the
    /// screen is already new by the time the banner is read.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if Self.isBrief(notification.request.content.userInfo) {
            await BriefStore.shared.refresh()
        }
        return [.banner, .sound, .list]
    }

    /// Tapped: iOS opens the app; this pulls the new brief.
    // COMPLETION-HANDLER FORM, NOT `async`, ON PURPOSE. The nonisolated async
    // form finishes on a background executor, so the @objc thunk calls iOS's
    // completion handler off the main thread and UIKit aborts in
    // _updateSnapshotAndStateRestorationWithAction (crash logs 09-15..09-28):
    // every notification tap killed the app instead of opening it. The
    // delegate is called on the main thread; completion goes back there too.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        nonisolated(unsafe) let done = completionHandler
        let isBrief = Self.isBrief(response.notification.request.content.userInfo)
        Task { @MainActor in
            if isBrief { await BriefStore.shared.refresh() }
            done()
        }
    }
}

/// The APNs callbacks SwiftUI has no equivalent for.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in PushRegistrar.shared.received(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[push] registration failed: \(error.localizedDescription)")
    }

    /// A push with `content-available: 1` wakes the app in the background:
    /// fetch and cache the brief so the widget has it before anyone opens the
    /// app. Only happens if the hub sets content-available; a plain alert push
    /// is handled by the tap path above instead.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        guard PushRegistrar.isBrief(userInfo) else { return .noData }
        await BriefStore.shared.refresh()
        return .newData
    }
}
