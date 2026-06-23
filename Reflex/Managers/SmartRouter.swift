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
            spotifyTrackURI: item.type == .track ? item.playbackURI : nil,
            spotifyAlbumURI: item.type == .track ? item.contextURI : (item.type == .album ? item.playbackURI : nil),
            spotifyArtistURI: item.artistURI,
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
                Logger.shared.routing("Spotify not running; no target app for command")
                return nil
            }
            guard AppleScriptHelper.checkIfAppIsPlaying(spotify) else {
                Logger.shared.routing("Spotify not playing; no target app for command")
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
            let previousState = stateManager.currentState
            let rawTrackInfo: (track: String?, artist: String?, album: String?)
            if spotify.supportsNowPlaying {
                rawTrackInfo = AppleScriptHelper.getCurrentTrack(from: spotify)
            } else {
                rawTrackInfo = (nil, nil, nil)
            }

            let trackInfo: (track: String?, artist: String?, album: String?)
            if rawTrackInfo.track != nil && rawTrackInfo.artist != nil {
                trackInfo = rawTrackInfo
            } else if let previousState,
                      previousState.app?.bundleIdentifier == spotifyBundleId,
                      previousState.hasDisplayableTrackInfo {
                trackInfo = (
                    track: previousState.trackName,
                    artist: previousState.artistName,
                    album: previousState.albumName
                )
            } else {
                Logger.shared.debug("Spotify is playing but track metadata is unavailable; leaving display state unchanged")
                return
            }

            if let currentVol = AppleScriptHelper.getVolume(for: spotify), currentVol > 0 {
                lastSpotifyVolume = currentVol
            }

            // A playing track always clears the dismissed state
            stateManager.dismissedTrackKey = nil

            // Compare against previous state *before* updating currentState.
            let previousKey = previousState?.trackKey ?? "||"
            let currentKey = "\(trackInfo.track ?? "")||\(trackInfo.artist ?? "")"
            let trackChanged = previousKey != currentKey
            let trackURI = spotify.supportsNowPlaying ? AppleScriptHelper.currentSpotifyTrackURI() : nil
            let albumURI: String?
            let artistURI: String?
            if previousState?.spotifyTrackURI == trackURI {
                albumURI = previousState?.spotifyAlbumURI
                artistURI = previousState?.spotifyArtistURI
            } else {
                albumURI = nil
                artistURI = nil
            }

            let state = PlaybackState(
                app: spotify,
                isPlaying: true,
                trackName: trackInfo.track,
                artistName: trackInfo.artist,
                albumName: trackInfo.album,
                spotifyTrackURI: trackURI,
                spotifyAlbumURI: albumURI,
                spotifyArtistURI: artistURI,
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
                    spotifyTrackURI: current.spotifyTrackURI,
                    spotifyAlbumURI: current.spotifyAlbumURI,
                    spotifyArtistURI: current.spotifyArtistURI,
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
