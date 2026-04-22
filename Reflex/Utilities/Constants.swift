import Foundation

/// App-wide constants
enum Constants {
    /// Notification names used throughout the app
    enum Notifications {
        static let mediaKeyPressed = Notification.Name("com.reflex.mediaKeyPressed")
        static let playbackStateChanged = Notification.Name("com.reflex.playbackStateChanged")
        static let activeAppChanged = Notification.Name("com.reflex.activeAppChanged")
        static let commandSent = Notification.Name("com.reflex.commandSent")
        static let permissionStatusChanged = Notification.Name("com.reflex.permissionStatusChanged")
    }

    /// UserDefaults keys
    enum UserDefaultsKeys {
        static let preferences = "com.reflex.preferences"
        static let hasCompletedOnboarding = "com.reflex.hasCompletedOnboarding"
        static let lastSelectedApp = "com.reflex.lastSelectedApp"
    }

    /// Media key codes (NX_KEYTYPE values)
    enum MediaKeyCodes {
        static let play: Int = 16
        static let next: Int = 17
        static let previous: Int = 18
        static let volumeUp: Int = 0
        static let volumeDown: Int = 1
        static let mute: Int = 7
        static let rewind: Int = 20
        static let fastForward: Int = 19
    }

    /// App configuration
    enum App {
        static let bundleIdentifier = "com.reflex.app"
        static let name = "Reflex"
        static let version = "1.0.0"
        static let minimumMacOSVersion = "10.15"
    }

    /// Timing constants
    enum Timing {
        static let defaultPollingInterval: TimeInterval = 5.0
        static let appleScriptTimeout: TimeInterval = 3.0
        static let feedbackAnimationDuration: TimeInterval = 0.15
        static let permissionCheckInterval: TimeInterval = 2.0
        static let staleStateThreshold: TimeInterval = 30.0
    }

    /// URLs
    enum URLs {
        static let accessibilityPreferences = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        static let automationPreferences = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    }

    /// Spotify Web API credentials. Both search and playback use the
    /// Authorization Code + PKCE flow (clientID only — no secret), so the
    /// user signs in with their own account and we never ship a client
    /// secret inside the binary. clientID is injected at build time from
    /// SPOTIFY_CLIENT_ID; see ./save.
    enum Spotify {
        static var clientID: String { SpotifySecrets.clientID }
        /// Loopback ports the app binds for the OAuth callback. Spotify
        /// allowlists the *full* redirect URI (including port), so every port
        /// here must also be registered in the Spotify dashboard under the
        /// app's Redirect URIs — as `http://127.0.0.1:<port>/callback`.
        /// First-try/fallback order: if the first port is busy (another app,
        /// or a stranded previous listener), we try the next.
        static let loopbackPorts: [UInt16] = [49472, 49473]
        static let callbackPath = "/callback"
        /// Builds the redirect URI for a given bound port.
        static func redirectURI(forPort port: UInt16) -> String {
            "http://127.0.0.1:\(port)\(callbackPath)"
        }
        /// Scopes required to control playback and read device state.
        static let userScopes = "user-modify-playback-state user-read-playback-state"
    }
}
