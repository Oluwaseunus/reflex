import Foundation

/// Represents a media application that can receive playback commands
struct MediaApp: Identifiable, Codable, Equatable, Hashable {
    /// Bundle identifier (e.g., "com.spotify.client")
    let id: String

    /// Display name (e.g., "Spotify")
    let name: String

    /// Bundle identifier for app lookup
    let bundleIdentifier: String

    /// SF Symbol name for icon display
    let icon: String?

    /// Name used in AppleScript commands (e.g., "Spotify", "Music")
    let appleScriptName: String

    /// Whether the app supports querying track info
    let supportsNowPlaying: Bool

    /// User has marked this as a favorite
    var isFavorite: Bool = false

    /// App is installed on this system
    var isInstalled: Bool = false

    /// App is currently running
    var isRunning: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, bundleIdentifier, icon, appleScriptName, supportsNowPlaying
        case isFavorite, isInstalled, isRunning
    }

    init(id: String, name: String, bundleIdentifier: String, icon: String?,
         appleScriptName: String, supportsNowPlaying: Bool,
         isFavorite: Bool = false, isInstalled: Bool = false, isRunning: Bool = false) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
        self.appleScriptName = appleScriptName
        self.supportsNowPlaying = supportsNowPlaying
        self.isFavorite = isFavorite
        self.isInstalled = isInstalled
        self.isRunning = isRunning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        appleScriptName = try container.decode(String.self, forKey: .appleScriptName)
        supportsNowPlaying = try container.decode(Bool.self, forKey: .supportsNowPlaying)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isInstalled = try container.decodeIfPresent(Bool.self, forKey: .isInstalled) ?? false
        isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MediaApp, rhs: MediaApp) -> Bool {
        lhs.id == rhs.id
    }

}
