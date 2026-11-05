import XCTest
@testable import Reflex

final class PlayerRoutingTests: XCTestCase {
    func testAutomaticSelectionUpdatesDisplayedPlayerAndCommandTargetTogether() throws {
        let suite = "Reflex.AutomaticRoutingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesManager(defaults: defaults)
        preferences.prefs.selectedPlayer = .automatic
        let manager = PlaybackStateManager()
        var playing: Set<PlaybackPlayer> = [.spotify]
        var commands: [String] = []
        let router = SmartRouter(
            appDetector: MediaAppDetector(), commandSender: MediaCommandSender(),
            preferences: preferences, stateManager: manager,
            appLookup: { id in
                guard let player = PlaybackPlayer(rawValue: id) else { return nil }
                return MediaApp(id: id, name: player.name, bundleIdentifier: id, icon: nil,
                                appleScriptName: player.appleScriptName, supportsNowPlaying: true,
                                isInstalled: true, isRunning: true)
            },
            playbackReader: { app in
                PlaybackState(app: app, isPlaying: playing.contains(PlaybackPlayer(rawValue: app.id)!),
                              trackName: "Song", artistName: "Artist", albumName: nil, timestamp: Date())
            },
            commandHandler: { _, app in commands.append(app.id); return true },
            artworkReader: { _ in nil }
        )
        defer { router.stopPolling() }
        XCTAssertEqual(preferences.playbackPlayer, .spotify)
        playing.insert(.appleMusic)
        router.pollPlaybackState()
        XCTAssertEqual(preferences.prefs.selectedPlayer, .automatic)
        XCTAssertEqual(preferences.playbackPlayer, .appleMusic)
        XCTAssertEqual(manager.currentState?.app?.id, PlaybackPlayer.appleMusic.rawValue)
        XCTAssertTrue(router.routeCommand(.nextTrack))
        XCTAssertEqual(commands, [PlaybackPlayer.appleMusic.rawValue])

        playing.remove(.appleMusic)
        router.pollPlaybackState()
        XCTAssertEqual(preferences.playbackPlayer, .appleMusic)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(PreferencesManager(defaults: defaults).playbackPlayer, .appleMusic)

        preferences.prefs.selectedPlayer = .spotify
        playing.insert(.appleMusic)
        router.pollPlaybackState()
        XCTAssertEqual(preferences.playbackPlayer, .spotify)
        XCTAssertEqual(manager.currentState?.app?.id, PlaybackPlayer.spotify.rawValue)
    }

    func testSelectionImmediatelyChangesDisplayAndCommandTarget() throws {
        let suite = "Reflex.PlayerRoutingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesManager(defaults: defaults)
        let stateManager = PlaybackStateManager()
        var commands: [String] = []
        var unavailable: Set<String> = []
        let router = SmartRouter(
            appDetector: MediaAppDetector(), commandSender: MediaCommandSender(),
            preferences: preferences, stateManager: stateManager,
            appLookup: { id in
                guard !unavailable.contains(id), let player = PlaybackPlayer(rawValue: id) else { return nil }
                return MediaApp(id: id, name: player.name, bundleIdentifier: id, icon: nil,
                                appleScriptName: player.appleScriptName, supportsNowPlaying: true,
                                isInstalled: true, isRunning: true)
            },
            playbackReader: { app in
                XCTAssertEqual(preferences.prefs.selectedPlayer.rawValue, app.id,
                               "The picker choice must be committed before playback is read")
                return PlaybackState(app: app, isPlaying: false, trackName: "Same Song",
                              artistName: "Same Artist", albumName: nil, timestamp: Date())
            },
            commandHandler: { _, app in commands.append(app.id); return true },
            artworkReader: { _ in nil }
        )
        defer { router.stopPolling() }
        XCTAssertEqual(stateManager.currentState?.app?.id, PlaybackPlayer.spotify.rawValue)
        XCTAssertTrue(router.routeCommand(.playPause))
        stateManager.dismissCurrentTrack()

        preferences.prefs.selectedPlayer = .appleMusic
        XCTAssertEqual(stateManager.currentState?.app?.id, PlaybackPlayer.appleMusic.rawValue)
        XCTAssertFalse(stateManager.isPlaying)
        XCTAssertNil(stateManager.dismissedTrackKey)
        XCTAssertTrue(router.routeCommand(.nextTrack))
        XCTAssertEqual(commands, [PlaybackPlayer.spotify.rawValue, PlaybackPlayer.appleMusic.rawValue])

        unavailable.insert(PlaybackPlayer.spotify.rawValue)
        preferences.prefs.selectedPlayer = .spotify
        XCTAssertNil(stateManager.currentState)
        XCTAssertNil(router.activeApp)
        XCTAssertFalse(router.routeCommand(.playPause))
        XCTAssertEqual(commands.count, 2, "Never fall back to the other running player")
    }
}
