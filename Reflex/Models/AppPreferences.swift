import Foundation

/// User preferences for the Reflex app
struct AppPreferences: Codable {
    enum CodingKeys: String, CodingKey {
        case favoriteApps, lastUsedApp, autoSwitchEnabled, showNowPlaying, showTrackInfo,
             showArtistInMenuBar, launchAtLogin, enableVolumeKeys, fallbackToSystem,
             pollingInterval, showVisualFeedback, playAudioFeedback, customShortcuts,
             hasCompletedOnboarding, preferencesVersion, restoreFocusOnClose,
             updateMenuBarWhilePopoverOpen
    }

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

    /// Include artist name next to track title in the menu bar (requires showTrackInfo)
    var showArtistInMenuBar: Bool = false

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

    /// Return focus to previous app when closing popover from menu bar
    var restoreFocusOnClose: Bool = true

    /// Allow menu bar title to update while the popover is open
    var updateMenuBarWhilePopoverOpen: Bool = false

    /// App has been run before
    var hasCompletedOnboarding: Bool = false

    /// Version of preferences schema (for migrations)
    var preferencesVersion: Int = 1

    /// Default initializer
    init() { }

    // Custom decoder to provide defaults when keys are missing (backward compatibility)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        favoriteApps = try container.decodeIfPresent([String].self, forKey: .favoriteApps) ?? []
        lastUsedApp = try container.decodeIfPresent(String.self, forKey: .lastUsedApp)
        autoSwitchEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSwitchEnabled) ?? true
        showNowPlaying = try container.decodeIfPresent(Bool.self, forKey: .showNowPlaying) ?? true
        showTrackInfo = try container.decodeIfPresent(Bool.self, forKey: .showTrackInfo) ?? false
        showArtistInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showArtistInMenuBar) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        enableVolumeKeys = try container.decodeIfPresent(Bool.self, forKey: .enableVolumeKeys) ?? false
        fallbackToSystem = try container.decodeIfPresent(Bool.self, forKey: .fallbackToSystem) ?? true
        pollingInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .pollingInterval) ?? 5.0
        showVisualFeedback = try container.decodeIfPresent(Bool.self, forKey: .showVisualFeedback) ?? true
        playAudioFeedback = try container.decodeIfPresent(Bool.self, forKey: .playAudioFeedback) ?? false
        customShortcuts = try container.decodeIfPresent([String: String].self, forKey: .customShortcuts) ?? [:]
        restoreFocusOnClose = try container.decodeIfPresent(Bool.self, forKey: .restoreFocusOnClose) ?? true
        updateMenuBarWhilePopoverOpen = try container.decodeIfPresent(Bool.self, forKey: .updateMenuBarWhilePopoverOpen) ?? false
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        preferencesVersion = try container.decodeIfPresent(Int.self, forKey: .preferencesVersion) ?? 1
    }
}
