import CryptoKit
import Foundation
import Security

/// The key that proves a human said "done". mailgate holds the other copy in
/// a root-only file, unreadable by the atlas user, so neither Claude nor the hub
/// can make a signature.
///
/// READ ONLY, and byte-compatible with agents-ios Agents/Mail/ApprovalKey.swift:
/// the key is pasted once into Agents, which stores it with no access group -
/// so in its FIRST keychain group, the shared com.example.shared. That is
/// Brief's first and only group, so the same query finds it here.
enum ApprovalKey {
    private static var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.example.agents.mail-approval",
            kSecAttrAccount as String: "mailgate-approval-key",
        ]
    }

    /// Hex HMAC-SHA256 of "<id>.<hash>.<expiresAt>", the same bytes mailgate's
    /// src/approval.js signs.
    static func sign(key: SymmetricKey, id: String, hash: String, expiresAt: Int64) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data("\(id).\(hash).\(expiresAt)".utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    static func load() -> SymmetricKey? {
        var q = base
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
            let data = out as? Data, data.count == 32
        else { return nil }
        return SymmetricKey(data: data)
    }
}
