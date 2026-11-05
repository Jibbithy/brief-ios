import Foundation

/// A fake, offline brief so every screen can be looked at and screenshotted
/// without a hub, a token or the tailnet (same idea as agents-ios DemoMode).
///
/// ACTIVATED ONLY BY A LAUNCH ARGUMENT, AND ONLY IN A DEBUG BUILD. In release
/// every flag is a plain `false`. Nothing here touches the network, the
/// Keychain, the cache or push registration.
///
///   xcrun simctl launch <udid> com.example.brief -BriefDemo [flag]
///
///   (none)            the sample brief (Brief.sample)
///   -BriefDemoEmpty   the 404 "No brief yet" state
///   -BriefDemoToken   the token prompt, as a new install sees it
///   -BriefDemoEnd     the sample brief, scrolled to the bottom (rack, notes)
///   -BriefDemoExpand  the second event and the first email dropped open
///   -BriefDemoWeek    scrolled to the payments and the week ahead
///   -BriefDemoChores  every chore row state: a problem, busy, a failed step
///   -BriefDemoTodo    opens on the To-Do tab (sample list; edits stay local)
///
/// In any demo, Done on a chore fakes success after half a second.
enum DemoMode {
    static var isActive: Bool { has("-BriefDemo") }
    static var empty: Bool { isActive && has("-BriefDemoEmpty") }
    static var showsTokenEntry: Bool { isActive && has("-BriefDemoToken") }
    static var scrollsToEnd: Bool { isActive && has("-BriefDemoEnd") }
    static var expandsDetails: Bool { isActive && has("-BriefDemoExpand") }
    static var scrollsToWeek: Bool { isActive && has("-BriefDemoWeek") }
    static var showsChoreStates: Bool { isActive && has("-BriefDemoChores") }
    static var opensTodo: Bool { isActive && has("-BriefDemoTodo") }

    /// The clock the calendar reads. In demo mode it is pinned to 9:45 this
    /// morning, so a screenshot taken at any hour shows the standup on now and
    /// the rest of the day ahead - rather than a whole greyed-out day at night.
    static func clock(_ real: Date) -> Date {
        guard isActive else { return real }
        return Calendar.current.date(bySettingHour: 9, minute: 45, second: 0, of: real) ?? real
    }

    private static func has(_ flag: String) -> Bool {
        #if DEBUG
            return ProcessInfo.processInfo.arguments.contains(flag)
        #else
            return false
        #endif
    }
}
