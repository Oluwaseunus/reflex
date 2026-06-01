import Foundation
import Combine
import AppKit

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
    private var startupPollTimer: Timer?
    private var suppressSpotifyPollingUntil: Date?
    private var cancellables = Set<AnyCancellable>()
    private let spotifyStartupPollQuietPeriod = SpotifyPlaybackStartupGuard.quietPeriod

    // MARK: - Thread-safe cached state (read from CGEvent tap thread)

    private var _spotifyIsPlaying = false
    private var _spotifyPlayingLock = os_unfair_lock()

    /// Thread-safe: is Spotify currently playing?
    var isSpotifyPlaying: Bool {
        os_unfair_lock_lock(&_spotifyPlayingLock)
        defer { os_unfair_lock_unlock(&_spotifyPlayingLock) }
        return _spotifyIsPlaying
    }

    private func setSpotifyPlaying(_ playing: Bool) {
        os_unfair_lock_lock(&_spotifyPlayingLock)
        _spotifyIsPlaying = playing
        os_unfair_lock_unlock(&_spotifyPlayingLock)
    }

    private var _spotifyIsRunning = false
    private var _spotifyRunningLock = os_unfair_lock()

    /// Thread-safe: is Spotify currently running?
    var isSpotifyRunning: Bool {
        os_unfair_lock_lock(&_spotifyRunningLock)
        defer { os_unfair_lock_unlock(&_spotifyRunningLock) }
        return _spotifyIsRunning
    }

    private func setSpotifyRunning(_ running: Bool) {
        os_unfair_lock_lock(&_spotifyRunningLock)
        _spotifyIsRunning = running
        os_unfair_lock_unlock(&_spotifyRunningLock)
    }

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

        NotificationCenter.default.publisher(for: Constants.Notifications.spotifyPlaybackStartDispatched)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let item = notification.userInfo?[Constants.NotificationUserInfo.spotifyPlaybackItem] as? MediaSearchResult
                self?.deferSpotifyStartupPoll(for: item)
            }
            .store(in: &cancellables)
    }

    private func deferSpotifyStartupPoll(for item: MediaSearchResult?) {
        SpotifyPlaybackStartupGuard.suppressReadsForStartup()
        suppressSpotifyPollingUntil = Date().addingTimeInterval(spotifyStartupPollQuietPeriod)
        startupPollTimer?.invalidate()
        startupPollTimer = Timer.scheduledTimer(withTimeInterval: spotifyStartupPollQuietPeriod, repeats: false) { [weak self] _ in
            guard let self else { return }
            suppressSpotifyPollingUntil = nil
            refreshSpotifyPlaybackState(reason: "startup quiet period ended")
        }
        startupPollTimer?.tolerance = 0.25
        if let spotify = appDetector.app(withBundleId: spotifyBundleId), spotify.isRunning {
            setSpotifyRunning(true)
            setSpotifyPlaying(true)
            if let item {
                publishOptimisticSpotifyState(spotify: spotify, item: item)
            }
        }
        Logger.shared.debug("Paused Spotify playback polling during track startup")
    }

    private func publishOptimisticSpotifyState(spotify: MediaApp, item: MediaSearchResult) {
        stateManager.dismissedTrackKey = nil
        stateManager.currentArtwork = nil
        stateManager.updateState(PlaybackState(
            app: spotify,
            isPlaying: true,
            trackName: item.title,
            artistName: item.artistName,
            albumName: item.albumName,
            timestamp: Date()
        ))
        activeApp = spotify
        Logger.shared.debug("Optimistically updated Spotify display: \(item.title)")
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

    /// Restart the currently loaded Spotify track by seeking to position 0,
    /// preserving play/pause state. Currently **not wired up** — retained for
    /// a potential future reintroduction of the media-key "previous-while-
    /// paused" flow (see PREV_WHILE_PAUSED_PLAN.md).
    @available(*, deprecated, message: "Not currently in use. Popover ⏮ button uses replayCurrentSpotifyTrack(resumePlayback:) instead.")
    @discardableResult
    func restartCurrentSpotifyTrack() -> Bool {
        guard let spotify = appDetector.app(withBundleId: spotifyBundleId),
              spotify.isInstalled else {
            Logger.shared.routing("Restart-current-track: Spotify not installed")
            return false
        }
        guard spotify.isRunning else {
            Logger.shared.routing("Restart-current-track: Spotify not running")
            return false
        }

        Logger.shared.routing("Restart-current-track: seeking Spotify to 0")
        let success = AppleScriptHelper.setPlaybackPosition(0, for: spotify)

        if success {
            preferences.setLastUsedApp(spotify.id)
            activeApp = spotify

            NotificationCenter.default.post(
                name: Constants.Notifications.activeAppChanged,
                object: spotify
            )
        }

        return success
    }

    /// Skip to the previous Spotify track and immediately start playback,
    /// fused into a single AppleScript `tell` block. Used by the popover
    /// ⏮ button when the track is paused and the position is within the
    /// restart-threshold window (see `NowPlayingCard.restartThresholdSeconds`),
    /// so the behavior matches Spotify's own paused ⏮ click (which auto-plays
    /// the previous track).
    /// - Returns: `true` if the command was issued, `false` otherwise.
    @discardableResult
    func skipToPreviousSpotifyTrackAndPlay() -> Bool {
        guard let spotify = appDetector.app(withBundleId: spotifyBundleId),
              spotify.isInstalled else {
            Logger.shared.routing("Skip-to-previous-and-play: Spotify not installed")
            return false
        }
        guard spotify.isRunning else {
            Logger.shared.routing("Skip-to-previous-and-play: Spotify not running")
            return false
        }

        Logger.shared.routing("Skip-to-previous-and-play: previous track + play")
        let success = AppleScriptHelper.previousTrackAndPlaySpotify(for: spotify)

        if success {
            preferences.setLastUsedApp(spotify.id)
            activeApp = spotify

            NotificationCenter.default.post(
                name: Constants.Notifications.activeAppChanged,
                object: spotify
            )
        }

        return success
    }

    /// Replay the currently loaded Spotify track.
    /// - When `resumePlayback` is `true`, seek to 0 **and** start playback,
    ///   fused into a single AppleScript `tell` block to avoid a race with
    ///   any intervening playback-context change.
    /// - When `false`, seek to 0 only, leaving Spotify's play state alone
    ///   (used when Spotify is already playing and we just want the scrubber
    ///   to jump back).
    /// - Returns: `true` if the command was issued, `false` otherwise.
    @discardableResult
    func replayCurrentSpotifyTrack(resumePlayback: Bool) -> Bool {
        guard let spotify = appDetector.app(withBundleId: spotifyBundleId),
              spotify.isInstalled else {
            Logger.shared.routing("Replay-current-track: Spotify not installed")
            return false
        }
        guard spotify.isRunning else {
            Logger.shared.routing("Replay-current-track: Spotify not running")
            return false
        }

        let success: Bool
        if resumePlayback {
            Logger.shared.routing("Replay-current-track: seeking Spotify to 0 and playing")
            success = AppleScriptHelper.restartAndPlaySpotify(for: spotify)
        } else {
            Logger.shared.routing("Replay-current-track: seeking Spotify to 0")
            success = AppleScriptHelper.setPlaybackPosition(0, for: spotify)
        }

        if success {
            preferences.setLastUsedApp(spotify.id)
            activeApp = spotify

            NotificationCenter.default.post(
                name: Constants.Notifications.activeAppChanged,
                object: spotify
            )
        }

        return success
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
        startupPollTimer?.invalidate()
        startupPollTimer = nil
        suppressSpotifyPollingUntil = nil
        isPolling = false
        Logger.shared.info("Stopped playback state polling")
    }

    /// Refresh Spotify playback state and update routing/display accordingly (Spotify-only)
    private func refreshSpotifyPlaybackState(reason: String) {
        if let spotify = appDetector.app(withBundleId: spotifyBundleId),
           spotify.isRunning,
           AppleScriptHelper.checkIfAppIsPlaying(spotify) {
            setSpotifyRunning(true)
            setSpotifyPlaying(true)

            let trackInfo: (track: String?, artist: String?, album: String?)
            if spotify.supportsNowPlaying {
                trackInfo = AppleScriptHelper.getCurrentTrack(from: spotify)
            } else {
                trackInfo = (nil, nil, nil)
            }

            if let currentVol = AppleScriptHelper.getVolume(for: spotify), currentVol > 0 {
                lastSpotifyVolume = currentVol
            }

            // A playing track always clears the dismissed state
            stateManager.dismissedTrackKey = nil

            // Compare against previous state *before* updating currentState.
            let previousKey = stateManager.currentState?.trackKey ?? "||"
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
                        if let artworkData = await AppleScriptHelper.getArtworkData(from: spotify) {
                            await MainActor.run {
                                self.stateManager.currentArtwork = NSImage(data: artworkData)
                            }
                        }
                    }
                }
            }
        } else {
            // Update thread-safe caches: Spotify is not actively playing
            if let spotify = appDetector.app(withBundleId: spotifyBundleId) {
                setSpotifyRunning(spotify.isRunning)
            } else {
                setSpotifyRunning(false)
            }
            setSpotifyPlaying(false)

            // Preserve last known track so user can resume from the menu bar,
            // but skip if the user dismissed this track
            if let current = stateManager.currentState {
                if stateManager.dismissedTrackKey == current.trackKey {
                    return
                }
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

    /// Poll for current playback state and update routing/display accordingly (Spotify-only)
    private func pollPlaybackState() {
        if SpotifyPlaybackStartupGuard.isSuppressingReads {
            Logger.shared.debug("Skipping Spotify playback poll during track startup")
            return
        }
        if let until = suppressSpotifyPollingUntil {
            if Date() < until {
                Logger.shared.debug("Skipping Spotify playback poll during track startup")
                return
            }
            suppressSpotifyPollingUntil = nil
        }
        refreshSpotifyPlaybackState(reason: "timer")
    }

    deinit {
        stopPolling()
    }

    // MARK: - Play/Pause Decision (thread-safe, for CGEvent tap)

    /// Represents the routing decision for a play/pause key press.
    enum PlayPauseDecision {
        /// Send .pause to Spotify (browser is also playing)
        case pauseSpotify
        /// Send .playPause toggle to Spotify (only Spotify is playing)
        case toggleSpotify
        /// Don't handle — let the key pass through to the system
        case passThrough
    }

    /// Determine what to do when play/pause is pressed.
    /// Thread-safe: reads only from atomic caches. Safe to call from CGEvent tap thread.
    func decidePlayPause(browserIsNowPlaying: Bool) -> PlayPauseDecision {
        guard isSpotifyRunning, isSpotifyPlaying else {
            return .passThrough
        }

        if browserIsNowPlaying {
            return .pauseSpotify
        } else {
            return .toggleSpotify
        }
    }

    /// Execute a play/pause decision. Must be called from the main thread.
    @discardableResult
    func executePlayPauseDecision(_ decision: PlayPauseDecision) -> Bool {
        guard let spotify = appDetector.app(withBundleId: spotifyBundleId) else { return false }

        switch decision {
        case .pauseSpotify:
            Logger.shared.routing("Browser also playing — sending explicit pause to Spotify")
            let success = commandSender.sendCommand(.pause, to: spotify)
            if success {
                preferences.setLastUsedApp(spotify.id)
                activeApp = spotify
            }
            return success

        case .toggleSpotify:
            Logger.shared.routing("Only Spotify playing — sending playPause to Spotify")
            let success = commandSender.sendCommand(.playPause, to: spotify)
            if success {
                preferences.setLastUsedApp(spotify.id)
                activeApp = spotify
            }
            return success

        case .passThrough:
            Logger.shared.routing("Spotify not playing — key passed through to system")
            return false
        }
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
