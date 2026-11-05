import XCTest
@testable import Reflex

final class PlaybackStateTests: XCTestCase {
    private func app(_ player: PlaybackPlayer) -> MediaApp {
        MediaApp(id: player.rawValue, name: player.name, bundleIdentifier: player.rawValue,
                 icon: nil, appleScriptName: player.appleScriptName, supportsNowPlaying: true)
    }

    func testSameMetadataInDifferentPlayersHasDifferentIdentity() {
        let spotify = PlaybackState(app: app(.spotify), isPlaying: false,
                                    trackName: "Song", artistName: "Artist", albumName: "Album", timestamp: Date())
        let music = PlaybackState(app: app(.appleMusic), isPlaying: false,
                                  trackName: "Song", artistName: "Artist", albumName: "Album", timestamp: Date())
        XCTAssertNotEqual(spotify.trackKey, music.trackKey)
    }

    func testMusicIdentityDoesNotBecomeSpotifyURI() {
        let state = PlaybackState(app: app(.appleMusic), isPlaying: false,
                                  trackName: "Song", artistName: "Artist", albumName: nil,
                                  trackIdentifier: "ABC123", position: 42, duration: 210, volume: 60,
                                  timestamp: Date())
        XCTAssertNil(state.spotifyTrackURI)
        XCTAssertTrue(state.trackKey.contains("ABC123"))
        XCTAssertEqual(state.position, 42)
        XCTAssertEqual(state.duration, 210)
        XCTAssertEqual(state.volume, 60)
    }

    func testSpotifyIdentityRemainsAvailableForNavigation() {
        let state = PlaybackState(app: app(.spotify), isPlaying: true,
                                  trackName: "Song", artistName: nil, albumName: nil,
                                  spotifyTrackURI: "spotify:track:123", timestamp: Date())
        XCTAssertEqual(state.trackIdentifier, "spotify:track:123")
        XCTAssertEqual(state.spotifyTrackURI, "spotify:track:123")
    }

    func testSwitchingClearsArtworkDismissalAndActivePlayer() {
        let manager = PlaybackStateManager()
        manager.updateState(PlaybackState(app: app(.spotify), isPlaying: true,
                                          trackName: "Song", artistName: nil, albumName: nil,
                                          timestamp: Date()))
        manager.dismissCurrentTrack()
        manager.clearState()
        XCTAssertNil(manager.currentState)
        XCTAssertNil(manager.currentArtwork)
        XCTAssertNil(manager.activeApp)
        XCTAssertNil(manager.dismissedTrackKey)
    }

    func testPausedSnapshotUpdatesActivePlayer() {
        let manager = PlaybackStateManager()
        manager.updateState(PlaybackState(app: app(.appleMusic), isPlaying: false,
                                          trackName: "Song", artistName: nil, albumName: nil,
                                          timestamp: Date()))
        XCTAssertEqual(manager.activeApp?.id, PlaybackPlayer.appleMusic.rawValue)
    }
}
