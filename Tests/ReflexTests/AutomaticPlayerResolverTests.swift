import XCTest
@testable import Reflex

final class AutomaticPlayerResolverTests: XCTestCase {
    func testLastPlaybackStartWinsAndPausingRetainsThatPlayer() {
        var resolver = AutomaticPlayerResolver()
        let available = Set(PlaybackPlayer.allCases)
        XCTAssertEqual(resolver.resolve(available: available, playing: [.spotify], remembered: nil, foreground: nil), .spotify)
        XCTAssertEqual(resolver.resolve(available: available, playing: available, remembered: .spotify, foreground: .spotify), .appleMusic)
        // The older Spotify session must not take over when Music pauses.
        XCTAssertEqual(resolver.resolve(available: available, playing: [.spotify], remembered: .appleMusic, foreground: .spotify), .appleMusic)
        XCTAssertEqual(resolver.resolve(available: available, playing: [], remembered: .appleMusic, foreground: nil), .appleMusic)
        XCTAssertEqual(resolver.resolve(available: available, playing: [.spotify], remembered: .appleMusic, foreground: nil), .spotify)
    }

    func testStartupAndAppTerminationUseRunningPlayersOnly() {
        var resolver = AutomaticPlayerResolver()
        let available = Set(PlaybackPlayer.allCases)
        XCTAssertEqual(resolver.resolve(available: available, playing: available, remembered: .appleMusic, foreground: nil), .appleMusic)
        XCTAssertEqual(resolver.resolve(available: [.spotify], playing: [], remembered: .appleMusic, foreground: nil), .spotify)
        XCTAssertNil(resolver.resolve(available: [], playing: [], remembered: .spotify, foreground: nil))

        var paused = AutomaticPlayerResolver()
        XCTAssertEqual(paused.resolve(available: available, playing: [], remembered: .appleMusic, foreground: nil), .appleMusic)
    }
}
