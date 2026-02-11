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
    private let spotifyBundleId = "com.spotify.client"

    /// Last known non-zero Spotify volume (session memory)
    @Published var lastSpotifyVolume: Int = 50

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
    /// - parameter requirePlaying: when true, only apps that are actively playing are eligible
    @discardableResult
    func routeCommand(_ command: MediaCommand, requirePlaying: Bool = false) -> Bool {
        guard let targetApp = determineTargetApp(requirePlaying: requirePlaying) else {
            Logger.shared.routing("No target app available for command")

            // Fallback to system handling if enabled
            if preferences.prefs.fallbackToSystem {
                Logger.shared.routing("Falling back to system handling")
            }
            return false
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

        // We handled the key (found a target), even if sending failed
        return true
    }

    /// Determine which app should receive the next command (Spotify-first, no quick switch)
    private func determineTargetApp(requirePlaying: Bool) -> MediaApp? {
        guard let spotify = appDetector.app(withBundleId: spotifyBundleId),
              spotify.isInstalled else {
            Logger.shared.routing("Spotify not installed; no target app available")
            return nil
        }

        if requirePlaying {
            guard spotify.isRunning else {
                Logger.shared.routing("Spotify not running; letting system handle key")
                return nil
            }
            guard AppleScriptHelper.checkIfAppIsPlaying(spotify) else {
                Logger.shared.routing("Spotify not playing; letting system handle key")
                return nil
            }
        } else {
            guard spotify.isRunning else {
                Logger.shared.routing("Spotify not running; no target app for command")
                return nil
            }
        }

        return spotify
    }

    // Quick switch removed; no multi-app tie-breakers needed

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

    /// Poll for current playback state and update routing/display accordingly (Spotify-only)
    private func pollPlaybackState() {
        if let spotify = appDetector.app(withBundleId: spotifyBundleId),
           spotify.isRunning,
           AppleScriptHelper.checkIfAppIsPlaying(spotify) {
            let trackInfo: (track: String?, artist: String?, album: String?)
            if spotify.supportsNowPlaying {
                trackInfo = AppleScriptHelper.getCurrentTrack(from: spotify)
            } else {
                trackInfo = (nil, nil, nil)
            }

            if let currentVol = AppleScriptHelper.getVolume(for: spotify), currentVol > 0 {
                lastSpotifyVolume = currentVol
            }

            // Compare against previous state *before* updating currentState.
            let previousKey = "\(stateManager.currentState?.trackName ?? "")||\(stateManager.currentState?.artistName ?? "")"
            let currentKey = "\(trackInfo.track ?? "")||\(trackInfo.artist ?? "")"
            let trackChanged = previousKey != currentKey

            let state = PlaybackState(
                app: spotify,
                isPlaying: true,
                trackName: trackInfo.track,
                artistName: trackInfo.artist,
                albumName: trackInfo.album,
                timestamp: Date()
            )

            stateManager.updateState(state)
            activeApp = spotify

            Logger.shared.debug("Playback detected: \(spotify.name) - \(trackInfo.track ?? "unknown track")")

            // Fetch artwork only when track changed or missing
            if spotify.supportsNowPlaying {
                if trackChanged || stateManager.currentArtwork == nil {
                    Task {
                        if let art = await AppleScriptHelper.getArtwork(from: spotify) {
                            await MainActor.run {
                                self.stateManager.currentArtwork = art
                            }
                        }
                    }
                }
            }
        } else {
            // Preserve last known track so user can resume from the menu bar
            if let current = stateManager.currentState {
                let pausedState = PlaybackState(
                    app: current.app,
                    isPlaying: false,
                    trackName: current.trackName,
                    artistName: current.artistName,
                    albumName: current.albumName,
                    timestamp: Date()
                )
                stateManager.updateState(pausedState)
            }
        }
    }

    deinit {
        stopPolling()
    }

    // MARK: - Volume Helpers (Spotify)

    /// Toggle mute for Spotify; returns whether muted after the operation
    func toggleSpotifyMute() -> Bool? {
        guard let spotify = appDetector.app(withBundleId: spotifyBundleId),
              spotify.isRunning else { return nil }

        let currentVol = AppleScriptHelper.getVolume(for: spotify) ?? lastSpotifyVolume
        if currentVol > 0 {
            lastSpotifyVolume = currentVol
        }

        let target = currentVol > 0 ? 0 : max(lastSpotifyVolume, 10)
        let success = AppleScriptHelper.setVolume(target, for: spotify)
        guard success else { return nil }
        if target > 0 { lastSpotifyVolume = target }
        return target == 0
    }
}
