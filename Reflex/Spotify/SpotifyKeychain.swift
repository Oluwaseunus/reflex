import Foundation
import LocalAuthentication
import Security

enum SpotifyKeychainError: LocalizedError {
    case encodeFailed
    case itemMissing
    case unexpectedData
    case decodeFailed(Error)
    case operationFailed(operation: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "Could not encode Spotify tokens for keychain storage."
        case .itemMissing:
            return "Spotify keychain item was missing after save."
        case .unexpectedData:
            return "Spotify keychain item did not contain data."
        case .decodeFailed(let error):
            return "Could not decode Spotify tokens from keychain: \(error.localizedDescription)"
        case .operationFailed(let operation, let status):
            return "\(operation) failed with OSStatus \(status): \(Self.statusDescription(status))"
        }
    }

    private static func statusDescription(_ status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "No keychain error description available"
    }
}

/// Keychain-backed storage for Spotify user-auth tokens.
/// Lives in the default keychain (login).
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
    private static func baseQuery(allowAuthenticationUI: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if allowAuthenticationUI {
            let context = LAContext()
            context.interactionNotAllowed = false
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    static func save(_ bundle: SpotifyTokenBundle) throws {
        guard let data = try? JSONEncoder().encode(bundle) else {
            throw SpotifyKeychainError.encodeFailed
        }
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw SpotifyKeychainError.operationFailed(operation: "SecItemUpdate", status: updateStatus)
        }

        try add(data)
    }

    private static func add(_ data: Data) throws {
        var add = baseQuery(allowAuthenticationUI: false)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        var addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // A duplicate after SecItemUpdate reported "not found" usually
            // means an old item exists but this build cannot access its ACL.
            // Try one authenticated cleanup pass; if that also fails, surface
            // the real keychain error instead of pretending sign-in worked.
            let deleteStatus = SecItemDelete(baseQuery() as CFDictionary)
            if deleteStatus == errSecSuccess {
                addStatus = SecItemAdd(add as CFDictionary, nil)
            }
        }

        guard addStatus == errSecSuccess else {
            throw SpotifyKeychainError.operationFailed(operation: "SecItemAdd", status: addStatus)
        }
    }

    static func load() throws -> SpotifyTokenBundle? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { return nil }
            throw SpotifyKeychainError.operationFailed(operation: "SecItemCopyMatching", status: status)
        }
        guard let data = item as? Data else {
            throw SpotifyKeychainError.unexpectedData
        }
        do {
            return try JSONDecoder().decode(SpotifyTokenBundle.self, from: data)
        } catch {
            throw SpotifyKeychainError.decodeFailed(error)
        }
    }

    static func deleteStoredTokens() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SpotifyKeychainError.operationFailed(operation: "SecItemDelete", status: status)
        }
    }

    static func clear() {
        do {
            try deleteStoredTokens()
        } catch {
            Logger.shared.error("Spotify keychain: clear failed", error: error)
        }
    }
}
