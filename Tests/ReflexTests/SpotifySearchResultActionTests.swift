import XCTest
@testable import Reflex

final class SpotifySearchResultActionTests: XCTestCase {
    func testPlayControlRetainsNormalPlayAction() {
        XCTAssertEqual(SpotifySearchResultActionKind.classify(buttonLabels: ["Play"]), .play)
        XCTAssertEqual(SpotifySearchResultActionKind.classify(buttonLabels: ["Play Gaslight 101"]), .play)
    }

    func testPauseControlOnlyRequestsPlaybackVerification() {
        XCTAssertEqual(
            SpotifySearchResultActionKind.classify(buttonLabels: ["Pause"]),
            .verifyAlreadyPlaying
        )
        XCTAssertEqual(
            SpotifySearchResultActionKind.classify(buttonLabels: ["Pause Nights"]),
            .verifyAlreadyPlaying
        )
    }

    func testUnknownOrMissingControlsAreRejected() {
        XCTAssertNil(SpotifySearchResultActionKind.classify(buttonLabels: []))
        XCTAssertNil(SpotifySearchResultActionKind.classify(buttonLabels: ["More options", "Save"]))
    }

    func testExplicitPlayTakesPrecedenceWhenBothControlsArePresent() {
        XCTAssertEqual(
            SpotifySearchResultActionKind.classify(buttonLabels: ["Pause", "Play"]),
            .play
        )
    }
}
