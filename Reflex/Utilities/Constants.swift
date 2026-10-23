import Foundation

/// App-wide constants
enum Constants {
    /// Notification names used throughout the app
    enum Notifications {
        static let playbackStateChanged = Notification.Name("com.reflex.playbackStateChanged")
        static let activeAppChanged = Notification.Name("com.reflex.activeAppChanged")
    }

    /// UserDefaults keys
    enum UserDefaultsKeys {
        static let preferences = "com.reflex.preferences"
        static let hasCompletedOnboarding = "com.reflex.hasCompletedOnboarding"
        static let lastSelectedApp = "com.reflex.lastSelectedApp"
        static let lastSettingsPane = "com.reflex.lastSettingsPane"
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
        static let staleStateThreshold: TimeInterval = 30.0
    }

    /// URLs
    enum URLs {
        static let automationPreferences = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    }
}
