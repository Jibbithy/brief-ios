import Foundation

/// `GET /api/chores`: tonight's nightly job and the day lists still ahead,
/// served live by the hub from ops/chores state (not part of the 8 AM brief).
struct ChoresPage: Codable, Equatable, Sendable {
    let today: String
    let weekly: [ChoreRow]
    let day: [ChoreRow]

    var isEmpty: Bool { weekly.isEmpty && day.isEmpty }
}

/// One chore the app can mark Done. `eventId` + `occurrence` name the
/// calendar event whose alerts go off; `textTo` is set only on day (Saturday)
/// rows, and is never trusted as the number to text - see ChoreApproval.
struct ChoreRow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let task: String
    /// "weekly" (tonight's nightly job) or "day" (a dated list, e.g. Saturday).
    let kind: String
    /// YYYY-MM-DD.
    let date: String
    /// "HH:MM" for a weekly row, nil for a day row.
    let deadline: String?
    let eventId: String
    /// "YYYY-MM-DDTHH:MM" for one night of a repeating event, "" otherwise.
    let occurrence: String
    let textTo: String?
    let done: ChoreDone?
}

struct ChoreDone: Codable, Equatable, Sendable {
    /// Epoch milliseconds.
    let at: Int64
    let steps: ChoreSteps
}

/// What each step of a Done did: "done" | "already" | "skipped" |
/// "skipped: <why>" | "failed: <message>".
struct ChoreSteps: Codable, Equatable, Sendable {
    let skylight: String
    let alerts: String
    let text: String
}

/// What `POST /api/chores/propose` hands back: the chore_done item mailgate is
/// holding, waiting for this phone's signature.
struct ChorePending: Codable, Equatable, Sendable {
    struct Message: Codable, Equatable, Sendable {
        var event_id: String
        var occurrence: String
        var date: String
        var task: String
        var skylight_ids: [String]
        var skylight_note: String
        var chat_guid: String
        var chat_name: String
        var recipients: [String]
        var text: String
    }

    let id: String
    let kind: String
    let hash: String
    let expiresAt: Int64
    let message: Message
}
