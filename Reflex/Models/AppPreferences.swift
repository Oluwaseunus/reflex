import Foundation

enum PlaybackPlayer: String, Codable, CaseIterable, Identifiable {
    case spotify = "com.spotify.client"
    case appleMusic = "com.apple.Music"

    var id: String { rawValue }
    var name: String { self == .spotify ? "Spotify" : "Apple Music" }
    var appleScriptName: String { self == .spotify ? "Spotify" : "Music" }
}

enum PlaybackPlayerSelection: String, Codable, CaseIterable, Identifiable {
    case automatic
    case spotify = "com.spotify.client"
    case appleMusic = "com.apple.Music"

    var id: String { rawValue }
    var player: PlaybackPlayer? { PlaybackPlayer(rawValue: rawValue) }
    var name: String { player?.name ?? "Automatic" }
}

/// Style of the selection highlight in the Spotify search popup.
enum SearchHighlightStyle: String, Codable, CaseIterable {
    case accent
    case neutral
}

/// User preferences for the Reflex app
struct AppPreferences: Codable {
    enum CodingKeys: String, CodingKey {
        case selectedPlayer, favoriteApps, lastUsedApp, autoSwitchEnabled, showNowPlaying, showTrackInfo,
             showArtistInMenuBar, launchAtLogin, pollingInterval, customShortcuts,
             hasCompletedOnboarding, preferencesVersion,
             updateMenuBarWhilePopoverOpen, searchHighlightStyle, useAlbumArtworkBackground
    }

    var selectedPlayer: PlaybackPlayerSelection = .spotify

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

    /// Polling interval for playback state (seconds)
    var pollingInterval: TimeInterval = 5.0

    /// Custom keyboard shortcuts (future use)
    var customShortcuts: [String: String] = [:]

    /// Allow menu bar title to update while the popover is open
    var updateMenuBarWhilePopoverOpen: Bool = false

    /// Highlight style for the Spotify search popup selection
    var searchHighlightStyle: SearchHighlightStyle = .accent

    /// Use blurred album artwork behind the now-playing controls.
    var useAlbumArtworkBackground: Bool = true

    /// App has been run before
    var hasCompletedOnboarding: Bool = false

    /// Version of preferences schema (for migrations)
    var preferencesVersion: Int = 1

    /// Default initializer
    init() { }

    // Custom decoder to provide defaults when keys are missing (backward compatibility)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        selectedPlayer = try container.decodeIfPresent(PlaybackPlayerSelection.self, forKey: .selectedPlayer) ?? .spotify
        favoriteApps = try container.decodeIfPresent([String].self, forKey: .favoriteApps) ?? []
        lastUsedApp = try container.decodeIfPresent(String.self, forKey: .lastUsedApp)
        autoSwitchEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSwitchEnabled) ?? true
        showNowPlaying = try container.decodeIfPresent(Bool.self, forKey: .showNowPlaying) ?? true
        showTrackInfo = try container.decodeIfPresent(Bool.self, forKey: .showTrackInfo) ?? false
        showArtistInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showArtistInMenuBar) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        pollingInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .pollingInterval) ?? 5.0
        customShortcuts = try container.decodeIfPresent([String: String].self, forKey: .customShortcuts) ?? [:]
        updateMenuBarWhilePopoverOpen = try container.decodeIfPresent(Bool.self, forKey: .updateMenuBarWhilePopoverOpen) ?? false
        searchHighlightStyle = try container.decodeIfPresent(SearchHighlightStyle.self, forKey: .searchHighlightStyle) ?? .accent
        useAlbumArtworkBackground = try container.decodeIfPresent(Bool.self, forKey: .useAlbumArtworkBackground) ?? true
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        preferencesVersion = try container.decodeIfPresent(Int.self, forKey: .preferencesVersion) ?? 1
    }
}
