import Foundation
import Combine

/// Manages user preferences persistence via UserDefaults
final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    /// Playback observers must see the committed value, rather than @Published's willSet value.
    let committedPreferences = PassthroughSubject<AppPreferences, Never>()
    let playbackPlayerChanges = PassthroughSubject<PlaybackPlayer, Never>()
    @Published private(set) var automaticPlayer: PlaybackPlayer = .spotify
    @Published private(set) var automaticPlayerAvailable = false

    var playbackPlayer: PlaybackPlayer { prefs.selectedPlayer.player ?? automaticPlayer }

    /// Current preferences (automatically saved on change)
    @Published var prefs: AppPreferences {
        didSet {
            save()
            committedPreferences.send(prefs)
            if (oldValue.selectedPlayer.player ?? automaticPlayer) != playbackPlayer {
                playbackPlayerChanges.send(playbackPlayer)
            }
        }
    }

    private let defaults: UserDefaults
    private let key = Constants.UserDefaultsKeys.preferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Load existing preferences or use defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            self.prefs = decoded
            Logger.shared.info("Loaded existing preferences")
        } else {
            self.prefs = AppPreferences()
            Logger.shared.info("Using default preferences")
        }
        automaticPlayer = prefs.lastUsedApp.flatMap(PlaybackPlayer.init(rawValue:)) ?? .spotify
    }

    func resolveAutomaticPlayer(_ player: PlaybackPlayer?) {
        guard let player else {
            if automaticPlayerAvailable { automaticPlayerAvailable = false }
            return
        }
        let previous = playbackPlayer
        if !automaticPlayerAvailable { automaticPlayerAvailable = true }
        if automaticPlayer != player { automaticPlayer = player }
        if prefs.lastUsedApp != player.rawValue { prefs.lastUsedApp = player.rawValue }
        if previous != playbackPlayer { playbackPlayerChanges.send(playbackPlayer) }
    }

    /// Save preferences to UserDefaults
    private func save() {
        do {
            let data = try JSONEncoder().encode(prefs)
            defaults.set(data, forKey: key)
            Logger.shared.debug("Preferences saved")
        } catch {
            Logger.shared.error("Failed to save preferences", error: error)
        }
    }

    /// Reset preferences to defaults
    func reset() {
        prefs = AppPreferences()
        Logger.shared.info("Preferences reset to defaults")
    }

    // MARK: - Convenience Methods

    /// Add an app to favorites
    func addFavorite(_ appId: String) {
        if !prefs.favoriteApps.contains(appId) {
            prefs.favoriteApps.append(appId)
            Logger.shared.info("Added favorite: \(appId)")
        }
    }

    /// Remove an app from favorites
    func removeFavorite(_ appId: String) {
        prefs.favoriteApps.removeAll { $0 == appId }
        Logger.shared.info("Removed favorite: \(appId)")
    }

    /// Check if an app is a favorite
    func isFavorite(_ appId: String) -> Bool {
        prefs.favoriteApps.contains(appId)
    }

    /// Set the last used app
    func setLastUsedApp(_ appId: String) {
        prefs.lastUsedApp = appId
        Logger.shared.debug("Set last used app: \(appId)")
    }

    /// Mark onboarding as completed
    func completeOnboarding() {
        prefs.hasCompletedOnboarding = true
        Logger.shared.info("Onboarding marked as completed")
    }

    /// Check if onboarding is needed
    var needsOnboarding: Bool {
        !prefs.hasCompletedOnboarding
    }
}
