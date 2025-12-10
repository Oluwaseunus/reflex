import Foundation

/// User preferences for the Reflex app
struct AppPreferences: Codable {
    /// Bundle IDs of user's favorite media apps
    var favoriteApps: [String] = []

    /// Bundle ID of last used media app
    var lastUsedApp: String?

    /// Automatically switch to whichever app is playing
    var autoSwitchEnabled: Bool = true

    /// Show "Now Playing" info in menu bar
    var showNowPlaying: Bool = true

    /// Show track/artist info in menu bar (requires showNowPlaying)
    var showTrackInfo: Bool = false

    /// Launch Reflex when user logs in
    var launchAtLogin: Bool = false

    /// Route volume keys through Reflex
    var enableVolumeKeys: Bool = false

    /// Fall back to system handling when no media app is available
    var fallbackToSystem: Bool = true

    /// Polling interval for playback state (seconds)
    var pollingInterval: TimeInterval = 5.0

    /// Show visual feedback when commands are sent
    var showVisualFeedback: Bool = true

    /// Play audio feedback when commands are sent
    var playAudioFeedback: Bool = false

    /// Custom keyboard shortcuts (future use)
    var customShortcuts: [String: String] = [:]

    /// App has been run before
    var hasCompletedOnboarding: Bool = false

    /// Version of preferences schema (for migrations)
    var preferencesVersion: Int = 1
}
