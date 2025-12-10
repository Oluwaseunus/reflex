import Cocoa
import Combine

/// Detects installed and running media applications
final class MediaAppDetector: ObservableObject {
    /// All known media apps (from definitions + runtime state)
    @Published private(set) var availableApps: [MediaApp] = []

    /// Currently running media apps
    @Published private(set) var runningApps: [MediaApp] = []

    /// Installed media apps
    var installedApps: [MediaApp] {
        availableApps.filter { $0.isInstalled }
    }

    private let workspace = NSWorkspace.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadAppDefinitions()
        detectInstalledApps()
        startMonitoring()
        updateRunningApps()
    }

    /// Load app definitions from bundled JSON
    private func loadAppDefinitions() {
        guard let url = Bundle.main.url(forResource: "MediaAppDefinitions", withExtension: "json") else {
            Logger.shared.error("MediaAppDefinitions.json not found in bundle")
            loadFallbackDefinitions()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let apps = try JSONDecoder().decode([MediaApp].self, from: data)
            availableApps = apps
            Logger.shared.info("Loaded \(apps.count) app definitions from JSON")
        } catch {
            Logger.shared.error("Failed to load app definitions", error: error)
            loadFallbackDefinitions()
        }
    }

    /// Fallback definitions if JSON fails to load
    private func loadFallbackDefinitions() {
        availableApps = [
            MediaApp(id: "com.spotify.client", name: "Spotify",
                     bundleIdentifier: "com.spotify.client", icon: "music.note",
                     appleScriptName: "Spotify", supportsNowPlaying: true),
            MediaApp(id: "com.apple.Music", name: "Apple Music",
                     bundleIdentifier: "com.apple.Music", icon: "music.note.list",
                     appleScriptName: "Music", supportsNowPlaying: true),
            MediaApp(id: "org.videolan.vlc", name: "VLC",
                     bundleIdentifier: "org.videolan.vlc", icon: "play.rectangle",
                     appleScriptName: "VLC", supportsNowPlaying: true)
        ]
        Logger.shared.info("Using fallback app definitions")
    }

    /// Detect which apps are installed on the system
    private func detectInstalledApps() {
        for i in 0..<availableApps.count {
            let bundleId = availableApps[i].bundleIdentifier
            if workspace.urlForApplication(withBundleIdentifier: bundleId) != nil {
                availableApps[i].isInstalled = true
                Logger.shared.debug("Found installed: \(availableApps[i].name)")
            }
        }

        let installedCount = availableApps.filter { $0.isInstalled }.count
        Logger.shared.info("Detected \(installedCount) installed media apps")
    }

    /// Start monitoring app launches and terminations
    private func startMonitoring() {
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppLaunch(notification)
        }

        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppTerminate(notification)
        }

        Logger.shared.info("Started monitoring app launches/terminations")
    }

    /// Handle app launch notification
    private func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        if let index = availableApps.firstIndex(where: { $0.bundleIdentifier == bundleId }) {
            availableApps[index].isRunning = true
            updateRunningApps()
            Logger.shared.event("Media app launched: \(availableApps[index].name)")
        }
    }

    /// Handle app termination notification
    private func handleAppTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleId = app.bundleIdentifier else { return }

        if let index = availableApps.firstIndex(where: { $0.bundleIdentifier == bundleId }) {
            availableApps[index].isRunning = false
            updateRunningApps()
            Logger.shared.event("Media app terminated: \(availableApps[index].name)")
        }
    }

    /// Update the list of running apps
    func updateRunningApps() {
        let runningBundleIds = Set(workspace.runningApplications.compactMap { $0.bundleIdentifier })

        for i in 0..<availableApps.count {
            availableApps[i].isRunning = runningBundleIds.contains(availableApps[i].bundleIdentifier)
        }

        runningApps = availableApps.filter { $0.isRunning }
        Logger.shared.debug("Running media apps: \(runningApps.map { $0.name }.joined(separator: ", "))")
    }

    /// Get a specific app by bundle ID
    func app(withBundleId bundleId: String) -> MediaApp? {
        availableApps.first { $0.bundleIdentifier == bundleId }
    }

    /// Get favorite apps that are installed
    func favoriteApps(from preferences: PreferencesManager) -> [MediaApp] {
        availableApps.filter {
            preferences.isFavorite($0.id) && $0.isInstalled
        }
    }

    /// Refresh all app states
    func refresh() {
        detectInstalledApps()
        updateRunningApps()
    }
}
