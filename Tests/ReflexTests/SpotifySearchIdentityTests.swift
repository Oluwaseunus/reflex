import XCTest
@testable import Reflex

final class SpotifySearchIdentityTests: XCTestCase {
    private let trackURI = "spotify:track:2sVV8LROIH1Z7mJWBBYpkU"

    func testLiveSpotifyLinkPreservesTrackIdentity() {
        XCTAssertEqual(
            SpotifySearchIdentity.uri(from: "https://xpui.app.spotify.com/track/2sVV8LROIH1Z7mJWBBYpkU", type: "track"),
            trackURI
        )
    }

    func testAlbumAndForeignLinksCannotBecomeTrackCommands() {
        XCTAssertNil(SpotifySearchIdentity.uri(from: "https://xpui.app.spotify.com/album/2sVV8LROIH1Z7mJWBBYpkU", type: "track"))
        XCTAssertNil(SpotifySearchIdentity.uri(from: "https://example.com/track/2sVV8LROIH1Z7mJWBBYpkU", type: "track"))
        XCTAssertNil(SpotifySearchIdentity.uri(from: "spotify:track:abc\" & do shell script", type: "track"))
    }

    func testQueryMatchesTitleAndArtistLinksWithPunctuation() {
        let result = SpotifySearchIdentity(trackURI: trackURI, title: "Can’t Stay", artists: ["Odeal"])
        XCTAssertNotNil(result.score(for: "can't stay by odeal"))
        XCTAssertNotNil(result.score(for: "CAN'T STAY ODEAL"))
    }

    func testArtistAloneCannotMakeAnUnrelatedSongMatch() {
        let result = SpotifySearchIdentity(trackURI: trackURI, title: "My Heart", artists: ["Odeal"])
        XCTAssertNil(result.score(for: "can't stay by odeal"))
    }

    func testSameTitleByAnotherArtistDoesNotMatch() {
        let result = SpotifySearchIdentity(trackURI: trackURI, title: "Can't Stay", artists: ["Someone Else"])
        XCTAssertNil(result.score(for: "can't stay by odeal"))
    }

    func testOriginalRanksAboveAlternateUnlessRequested() {
        let original = SpotifySearchIdentity(trackURI: trackURI, title: "Can't Stay", artists: ["Odeal"])
        let alternate = SpotifySearchIdentity(trackURI: trackURI, title: "Can't Stay (No Drums)", artists: ["Odeal"])
        XCTAssertGreaterThan(original.score(for: "can't stay by odeal")!, alternate.score(for: "can't stay by odeal")!)
        XCTAssertNil(original.score(for: "can't stay no drums odeal"))
        XCTAssertNotNil(alternate.score(for: "can't stay no drums odeal"))
    }

    func testEmptyQueryNeverMatches() {
        let result = SpotifySearchIdentity(trackURI: trackURI, title: "Can't Stay", artists: ["Odeal"])
        XCTAssertNil(result.score(for: "   "))
    }
}
