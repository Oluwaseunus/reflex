import Foundation
import Security

/// Keychain-backed storage for Spotify user-auth tokens.
/// Lives in the default keychain (login) so tokens persist across rebuilds.
struct SpotifyTokenBundle: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let scope: String
}

enum SpotifyKeychain {
    private static let service = "com.reflex.app.spotify-auth"
    private static let account = "default"

    /// Base query shared by save/load/clear. Uses the legacy login keychain.
    ///
    /// The data-protection keychain (`kSecUseDataProtectionKeychain: true`)
    /// sounds nicer but requires a `keychain-access-groups` entitlement bound
    /// to a Team ID — we don't ship with one, and `./save` signs without
    /// entitlements anyway, so `SecItemAdd` fails with `errSecMissingEntitlement`
    /// and every save silently no-ops. Legacy keychain it is.
    ///
    /// The "ACL prompt on every rebuild" that motivated the data-protection
    /// switch only happens with true ad-hoc signing (signature hash changes per
    /// build). `./save` signs with a stable self-signed "Reflex Dev" cert, so
    /// the ACL binds to a stable identity and rebuilds don't re-prompt.
    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func save(_ bundle: SpotifyTokenBundle) {
        guard let data = try? JSONEncoder().encode(bundle) else {
            Logger.shared.error("Spotify keychain: save() encode failed")
            return
        }
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            Logger.shared.error("Spotify keychain: SecItemUpdate failed OSStatus=\(updateStatus)")
            return
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            Logger.shared.error("Spotify keychain: SecItemAdd failed OSStatus=\(addStatus)")
        }
    }

    static func load() -> SpotifyTokenBundle? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                Logger.shared.error("Spotify keychain: SecItemCopyMatching failed OSStatus=\(status)")
            }
            return nil
        }
        guard let data = item as? Data else {
            Logger.shared.error("Spotify keychain: load() got success but item was not Data")
            return nil
        }
        do {
            return try JSONDecoder().decode(SpotifyTokenBundle.self, from: data)
        } catch {
            Logger.shared.error("Spotify keychain: decode failed", error: error)
            return nil
        }
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
