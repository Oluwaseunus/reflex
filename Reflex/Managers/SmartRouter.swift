import Foundation
import Combine

/// Intelligent router that determines which app to send media commands to
final class SmartRouter: ObservableObject {
    /// Currently active/targeted media app
    @Published private(set) var activeApp: MediaApp?

    /// Whether auto-switching is detecting a playing app
    @Published private(set) var isPolling: Bool = false

    private let appDetector: MediaAppDetector
    private let commandSender: MediaCommandSender
    private let preferences: PreferencesManager
    private let stateManager: PlaybackStateManager

    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(appDetector: MediaAppDetector,
         commandSender: MediaCommandSender,
         preferences: PreferencesManager,
         stateManager: PlaybackStateManager) {
        self.appDetector = appDetector
        self.commandSender = commandSender
        self.preferences = preferences
        self.stateManager = stateManager

        setupObservers()

        // Start polling if auto-switch is enabled
        if preferences.prefs.autoSwitchEnabled {
            startPolling()
        }
    }

    private func setupObservers() {
        // React to preference changes
        preferences.$prefs
            .map { $0.autoSwitchEnabled }
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled {
                    self?.startPolling()
                } else {
                    self?.stopPolling()
                }
            }
            .store(in: &cancellables)
    }

    /// Route a media command to the appropriate app
    func routeCommand(_ command: MediaCommand) {
        guard let targetApp = determineTargetApp() else {
            Logger.shared.routing("No target app available for command")

            // Fallback to system handling if enabled
            if preferences.prefs.fallbackToSystem {
                Logger.shared.routing("Falling back to system handling")
                // Event will pass through since we don't consume it
            }
            return
        }

        Logger.shared.routing("Routing \(command.displayName) to \(targetApp.name)")

        let success = commandSender.sendCommand(command, to: targetApp)

        if success {
            preferences.setLastUsedApp(targetApp.id)
            activeApp = targetApp

            NotificationCenter.default.post(
                name: Constants.Notifications.activeAppChanged,
                object: targetApp
            )
        }
    }

    /// Determine which app should receive the next command
    private func determineTargetApp() -> MediaApp? {
        let prefs = preferences.prefs

        // Priority 1: Auto-switch to currently playing app (if enabled)
        if prefs.autoSwitchEnabled, let playingApp = findPlayingApp() {
            Logger.shared.routing("Auto-switch: found playing app \(playingApp.name)")
            return playingApp
        }

        // Priority 2: Manually selected app (via status bar menu)
        if let selectedApp = activeApp, selectedApp.isRunning {
            Logger.shared.routing("Using manually selected app: \(selectedApp.name)")
            return selectedApp
        }

        // Priority 3: Last used app (if still running)
        if let lastUsedId = prefs.lastUsedApp,
           let lastApp = appDetector.availableApps.first(where: {
               $0.id == lastUsedId && $0.isRunning
           }) {
            Logger.shared.routing("Using last used app: \(lastApp.name)")
            return lastApp
        }

        // Priority 4: First running favorite
        let runningFavorites = appDetector.availableApps.filter {
            prefs.favoriteApps.contains($0.id) && $0.isRunning
        }
        if let firstFavorite = runningFavorites.first {
            Logger.shared.routing("Using first running favorite: \(firstFavorite.name)")
            return firstFavorite
        }

        // Priority 5: Any running media app
        if let anyRunning = appDetector.runningApps.first {
            Logger.shared.routing("Using first running app: \(anyRunning.name)")
            return anyRunning
        }

        Logger.shared.routing("No suitable target app found")
        return nil
    }

    /// Find the app that is currently playing
    private func findPlayingApp() -> MediaApp? {
        for app in appDetector.runningApps {
            if AppleScriptHelper.checkIfAppIsPlaying(app) {
                return app
            }
        }
        return nil
    }

    /// Start polling for playback state
    func startPolling() {
        guard !isPolling else { return }

        let interval = preferences.prefs.pollingInterval
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollPlaybackState()
        }

        isPolling = true
        Logger.shared.info("Started playback state polling (interval: \(interval)s)")

        // Do an immediate poll
        pollPlaybackState()
    }

    /// Stop polling for playback state
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isPolling = false
        Logger.shared.info("Stopped playback state polling")
    }

    /// Poll for current playback state and update routing/display accordingly
    private func pollPlaybackState() {
        // First check if any app is playing
        if let playingApp = findPlayingApp() {
            // Get track info if supported
            let trackInfo: (track: String?, artist: String?, album: String?)
            if playingApp.supportsNowPlaying {
                trackInfo = AppleScriptHelper.getCurrentTrack(from: playingApp)
            } else {
                trackInfo = (nil, nil, nil)
            }

            let state = PlaybackState(
                app: playingApp,
                isPlaying: true,
                trackName: trackInfo.track,
                artistName: trackInfo.artist,
                albumName: trackInfo.album,
                timestamp: Date()
            )

            stateManager.updateState(state)
            activeApp = playingApp

            Logger.shared.debug("Playback detected: \(playingApp.name) - \(trackInfo.track ?? "unknown track")")
        } else {
            // No app playing
            if stateManager.currentState?.isPlaying == true {
                stateManager.clearState()
                Logger.shared.debug("Playback stopped")
            }
        }
    }

    /// Manually select a specific app as the target
    func selectApp(_ app: MediaApp) {
        activeApp = app
        preferences.setLastUsedApp(app.id)
        Logger.shared.info("Manually selected app: \(app.name)")

        NotificationCenter.default.post(
            name: Constants.Notifications.activeAppChanged,
            object: app
        )
    }

    deinit {
        stopPolling()
    }
}
