import Foundation
import Combine
import AppKit
import MusicKit

/// Routes commands and publishes playback from the user's selected player.
final class SmartRouter: ObservableObject {
    @Published private(set) var activeApp: MediaApp?
    @Published private(set) var isPolling = false

    private let appDetector: MediaAppDetector
    private let commandSender: MediaCommandSender
    private let preferences: PreferencesManager
    private let stateManager: PlaybackStateManager
    private let appLookup: (String) -> MediaApp?
    private let playbackReader: (MediaApp) -> PlaybackState?
    private let commandHandler: (MediaCommand, MediaApp) -> Bool
    private let artworkReader: (MediaApp) async -> Data?
    private var lastVolumes: [String: Int] = [:]
    private var pollingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var artworkRequestID = UUID()
    private var catalogRequestID = UUID()
    private var catalogTask: Task<Void, Never>?
    private var catalogAttemptedKey: String?
    private var automaticResolver = AutomaticPlayerResolver()
    private var playbackObservers: [NSObjectProtocol] = []
    private var isRefreshingPlayback = false
    private var refreshPending = false

    init(appDetector: MediaAppDetector,
         commandSender: MediaCommandSender,
         preferences: PreferencesManager,
         stateManager: PlaybackStateManager,
         appLookup: ((String) -> MediaApp?)? = nil,
         playbackReader: @escaping (MediaApp) -> PlaybackState? = AppleScriptHelper.playbackState,
         commandHandler: ((MediaCommand, MediaApp) -> Bool)? = nil,
         artworkReader: @escaping (MediaApp) async -> Data? = AppleScriptHelper.getArtworkData) {
        self.appDetector = appDetector
        self.commandSender = commandSender
        self.preferences = preferences
        self.stateManager = stateManager
        self.appLookup = appLookup ?? { appDetector.app(withBundleId: $0) }
        self.playbackReader = playbackReader
        self.commandHandler = commandHandler ?? { commandSender.sendCommand($0, to: $1) }
        self.artworkReader = artworkReader
        setupObservers()
    }

    private func setupObservers() {
        preferences.committedPreferences
            .prepend(preferences.prefs)
            .map { $0.selectedPlayer }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                self.artworkRequestID = UUID()
                self.cancelCatalogResolution()
                self.stateManager.clearState()
                self.activeApp = nil
                self.pollPlaybackState()
            }
            .store(in: &cancellables)

        preferences.committedPreferences
            .prepend(preferences.prefs)
            .map { $0.pollingInterval }
            .removeDuplicates()
            .sink { [weak self] interval in
                self?.startPolling(interval: interval)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .musicAuthorizationChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.cancelCatalogResolution()
                self?.pollPlaybackState()
            }
            .store(in: &cancellables)

        appDetector.$runningApps
            .dropFirst()
            .sink { [weak self] _ in
                // App detector publishes before its app definitions finish updating.
                DispatchQueue.main.async { self?.pollPlaybackState() }
            }
            .store(in: &cancellables)

        // Playback notifications reduce the polling delay, while the timer
        // remains the fallback if a player doesn't send a notification.
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            playbackObservers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                guard self?.preferences.prefs.selectedPlayer == .automatic else { return }
                self?.pollPlaybackState()
            })
        }
    }

    private func determineTargetApp(requirePlaying: Bool = false) -> MediaApp? {
        if preferences.prefs.selectedPlayer == .automatic {
            guard !isRefreshingPlayback else { return nil }
            pollPlaybackState()
        }
        guard let app = appLookup(preferences.playbackPlayer.rawValue),
              app.isInstalled, app.isRunning else { return nil }
        guard !requirePlaying || AppleScriptHelper.checkIfAppIsPlaying(app) else { return nil }
        return app
    }

    @discardableResult
    func routeCommand(_ command: MediaCommand, requirePlaying: Bool = false) -> Bool {
        guard let app = determineTargetApp(requirePlaying: requirePlaying) else { return false }
        let success = commandHandler(command, app)
        if success { recordTarget(app) }
        return success
    }

    private func recordTarget(_ app: MediaApp) {
        preferences.setLastUsedApp(app.id)
        activeApp = app
        NotificationCenter.default.post(name: Constants.Notifications.activeAppChanged, object: app)
    }

    @discardableResult
    func skipToPreviousTrackAndPlay() -> Bool {
        guard let app = determineTargetApp() else { return false }
        let success = AppleScriptHelper.previousTrackAndPlay(for: app)
        if success { recordTarget(app) }
        return success
    }

    @discardableResult
    func replayCurrentTrack(resumePlayback: Bool) -> Bool {
        guard let app = determineTargetApp() else { return false }
        let success = resumePlayback
            ? AppleScriptHelper.restartAndPlay(for: app)
            : AppleScriptHelper.setPlaybackPosition(0, for: app)
        if success { recordTarget(app) }
        return success
    }

    func startPolling() {
        startPolling(interval: preferences.prefs.pollingInterval)
    }

    private func startPolling(interval: TimeInterval) {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollPlaybackState()
        }
        isPolling = true
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isPolling = false
    }

    func pollPlaybackState() {
        guard !isRefreshingPlayback else {
            refreshPending = true
            return
        }
        isRefreshingPlayback = true
        refreshPlaybackState(for: preferences.prefs.selectedPlayer)
        isRefreshingPlayback = false
        if refreshPending {
            refreshPending = false
            DispatchQueue.main.async { [weak self] in self?.pollPlaybackState() }
        }
    }

    private func refreshPlaybackState(for selection: PlaybackPlayerSelection) {
        let player: PlaybackPlayer
        let app: MediaApp?
        let snapshot: PlaybackState?
        if let explicitPlayer = selection.player {
            player = explicitPlayer
            app = appLookup(player.rawValue)
            snapshot = app.flatMap { $0.isRunning ? playbackReader($0) : nil }
        } else {
            var apps: [PlaybackPlayer: MediaApp] = [:]
            var states: [PlaybackPlayer: PlaybackState] = [:]
            for candidate in PlaybackPlayer.allCases {
                guard let candidateApp = appLookup(candidate.rawValue),
                      candidateApp.isInstalled, candidateApp.isRunning else { continue }
                apps[candidate] = candidateApp
                states[candidate] = playbackReader(candidateApp)
            }
            guard preferences.prefs.selectedPlayer == selection else { return }
            let playing = Set(states.filter { $0.value.isPlaying }.map(\.key))
            let remembered = preferences.prefs.lastUsedApp.flatMap(PlaybackPlayer.init(rawValue:))
            let foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier.flatMap(PlaybackPlayer.init(rawValue:))
            guard let resolved = automaticResolver.resolve(available: Set(apps.keys), playing: playing,
                                                           remembered: remembered, foreground: foreground) else {
                preferences.resolveAutomaticPlayer(nil)
                artworkRequestID = UUID()
                cancelCatalogResolution()
                stateManager.clearState()
                activeApp = nil
                return
            }
            if preferences.playbackPlayer != resolved {
                Logger.shared.info("Automatic player switched to \(resolved.name)")
            }
            preferences.resolveAutomaticPlayer(resolved)
            player = resolved
            app = apps[resolved]
            snapshot = states[resolved]
        }
        // Apple Events may process preference changes while awaiting a reply.
        guard preferences.prefs.selectedPlayer == selection else { return }
        guard let app, let state = snapshot else {
            artworkRequestID = UUID()
            cancelCatalogResolution()
            stateManager.clearState()
            activeApp = nil
            return
        }
        if let volume = state.volume, volume > 0 { lastVolumes[app.id] = volume }
        if state.isPlaying { stateManager.dismissedTrackKey = nil }
        guard stateManager.dismissedTrackKey != state.trackKey else { return }

        let trackChanged = stateManager.currentState?.trackKey != state.trackKey
        stateManager.updateState(state)
        activeApp = app
        if trackChanged {
            cancelCatalogResolution()
            stateManager.currentArtwork = nil
            artworkRequestID = UUID()
        }
        if player == .appleMusic, MusicAuthorization.currentStatus == .authorized,
           stateManager.currentCatalogDetails == nil, catalogAttemptedKey != state.trackKey {
            let expectedKey = state.trackKey
            catalogAttemptedKey = expectedKey
            catalogRequestID = UUID()
            let requestID = catalogRequestID
            catalogTask = Task { @MainActor in
                defer {
                    if self.catalogRequestID == requestID { self.catalogTask = nil }
                }
                do {
                    let details = try await AppleMusicCatalogResolver.shared.details(for: state)
                    guard self.catalogRequestID == requestID,
                          self.stateManager.currentState?.trackKey == expectedKey,
                          self.preferences.playbackPlayer == .appleMusic else { return }
                    self.stateManager.currentCatalogDetails = details
                    Logger.shared.info("MusicKit resolved track=\(details.track.id) albums=\(details.albums.map(\.id).joined(separator: ",")) artists=\(details.artists.map(\.id).joined(separator: ","))")
                } catch {
                    Logger.shared.info("MusicKit metadata unavailable: \(error.localizedDescription)")
                }
            }
        }
        guard trackChanged || stateManager.currentArtwork == nil else { return }
        let requestID = artworkRequestID
        Task { @MainActor in
            let data = await artworkReader(app)
            await MainActor.run {
                // A slow artwork download must never paint a different track/player.
                guard self.artworkRequestID == requestID,
                      self.stateManager.currentState?.trackKey == state.trackKey else { return }
                self.stateManager.currentArtwork = data.flatMap(NSImage.init(data:))
            }
        }
    }

    private func cancelCatalogResolution() {
        catalogRequestID = UUID()
        catalogTask?.cancel()
        catalogTask = nil
        catalogAttemptedKey = nil
    }

    /// Mute by setting volume to zero; restore each player's own last volume.
    func toggleMute() -> Bool? {
        guard let app = determineTargetApp() else { return nil }
        let remembered = lastVolumes[app.id] ?? 50
        guard let volume = AppleScriptHelper.getVolume(for: app) else { return nil }
        if volume > 0 { lastVolumes[app.id] = volume }
        let target = volume > 0 ? 0 : max(remembered, 10)
        guard AppleScriptHelper.setVolume(target, for: app) else { return nil }
        return target == 0
    }

    deinit {
        pollingTimer?.invalidate()
        catalogTask?.cancel()
        for observer in playbackObservers { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
