import CryptoKit
import Foundation

/// The phone's side of a chore Done: nothing is signed unless the item
/// mailgate is holding is exactly the row on screen.
///
/// SAME RULE AS EVERY AGENTS CARD: the hub runs as atlas and is not trusted to
/// relay the right item, so the hash is recomputed here (mailgate's
/// src/kinds.js `chore_done`, byte for byte) and the signature covers THAT.
/// The contact's number lives here, not in the row, so a hub can't retarget the text.
enum ChoreApproval {
    static let contact = "+15555550100"

    static func hashFields(_ m: ChorePending.Message) -> [String] {
        [
            "chore_done", m.event_id, m.occurrence, m.date, m.task, m.skylight_ids.joined(separator: "\n"),
            m.chat_guid, m.chat_name, m.recipients.joined(separator: "\n"), m.text,
        ]
    }

    /// Length-prefixed SHA-256, hex - "<utf8 byte count>:<field>" concatenated.
    static func hash(_ m: ChorePending.Message) -> String {
        let input = hashFields(m).map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// nil = safe to sign; otherwise why not, in words for the row.
    static func check(row: ChoreRow, pending p: ChorePending) -> String? {
        let m = p.message
        guard p.kind == "chore_done" else { return "The hub proposed something that isn't a chore." }
        guard m.event_id == row.eventId, m.occurrence == row.occurrence, m.date == row.date else {
            return "The hub proposed a different calendar event."
        }
        guard m.task == row.task else { return "The hub proposed a different chore." }
        if let to = row.textTo {
            guard to == contact else { return "That chore would text someone other than the contact." }
            guard m.text == "Done with \(row.task)" else { return "The text to the contact was reworded." }
            guard m.chat_guid.hasSuffix(";-;\(contact)"), m.recipients.count == 1,
                let r = m.recipients.first, r == contact || r.hasSuffix("(\(contact))")
            else { return "The text would go to someone other than the contact." }
        } else {
            guard m.chat_guid.isEmpty, m.recipients.isEmpty, m.text.isEmpty else {
                return "The hub added a text this chore doesn't send."
            }
        }
        guard hash(m) == p.hash else { return "What the hub showed doesn't match what mailgate holds." }
        return nil
    }
}
