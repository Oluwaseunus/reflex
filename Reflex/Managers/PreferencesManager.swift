import Foundation
import Combine

/// Manages user preferences persistence via UserDefaults
final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    /// Current preferences (automatically saved on change)
    @Published var prefs: AppPreferences {
        didSet {
            save()
        }
    }

    private let defaults = UserDefaults.standard
    private let key = Constants.UserDefaultsKeys.preferences

    private init() {
        // Load existing preferences or use defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            self.prefs = decoded
            Logger.shared.info("Loaded existing preferences")
        } else {
            self.prefs = AppPreferences()
            Logger.shared.info("Using default preferences")
        }
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
