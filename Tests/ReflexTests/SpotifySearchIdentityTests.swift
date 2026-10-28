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

    func testSearchRouteExposesCompletedQuery() {
        XCTAssertEqual(
            SpotifySearchIdentity.searchQuery(
                from: "https://xpui.app.spotify.com/search/geekin%20nemzz/tracks"
            ),
            "geekin nemzz"
        )
        XCTAssertEqual(
            SpotifySearchIdentity.searchQuery(
                from: "xpui.app.spotify.com/search/geekin%20nemzz"
            ),
            "geekin nemzz"
        )
    }

    func testTrackAndForeignURLsAreNotSearchRoutes() {
        XCTAssertNil(
            SpotifySearchIdentity.searchQuery(
                from: "https://xpui.app.spotify.com/track/2sVV8LROIH1Z7mJWBBYpkU"
            )
        )
        XCTAssertNil(
            SpotifySearchIdentity.searchQuery(
                from: "https://example.com/search/geekin%20nemzz"
            )
        )
    }

    func testQueryMatcherAcceptsCompactAndSeparatedTitles() {
        XCTAssertTrue(SpotifySearchIdentity.matchesSearchQuery("gaslight101 odeal", title: "Gaslight 101", artists: ["Odeal"]))
        XCTAssertTrue(SpotifySearchIdentity.matchesSearchQuery("BlameU Odeal", title: "Blame U", artists: ["Odeal"]))
    }

    func testQueryMatcherDistinguishesONOMEFromOnMe() {
        XCTAssertTrue(SpotifySearchIdentity.matchesSearchQuery("onome odeal", title: "ONOME", artists: ["Odeal"]))
        XCTAssertFalse(SpotifySearchIdentity.matchesSearchQuery("onome odeal", title: "On Me (with Odeal)", artists: ["6LACK", "Odeal"]))
        XCTAssertTrue(SpotifySearchIdentity.matchesSearchQuery("on me with odeal", title: "On Me (with Odeal)", artists: ["6LACK", "Odeal"]))
        XCTAssertFalse(SpotifySearchIdentity.matchesSearchQuery("on me with odeal", title: "ONOME", artists: ["Odeal"]))
        XCTAssertFalse(SpotifySearchIdentity.matchesSearchQuery("on me odeal", title: "On Me (with Odeal)", artists: ["6LACK", "Odeal"]))
    }

    func testQueryMatcherSupportsExactTitleArtistAndOrderingForms() {
        XCTAssertTrue(SpotifySearchIdentity.matchesSearchQuery("Gaslight 101", title: "Gaslight 101", artists: ["Odeal"]))
        XCTAssertTrue(SpotifySearchIdentity.matchesSearchQuery("Odeal", title: "Gaslight 101", artists: ["Odeal"]))
        XCTAssertTrue(SpotifySearchIdentity.matchesSearchQuery("Odeal Gaslight 101", title: "Gaslight 101", artists: ["Odeal"]))
        XCTAssertTrue(SpotifySearchIdentity.matchesSearchQuery("Gaslight 101 by Odeal", title: "Gaslight 101", artists: ["Odeal"]))
    }

    func testQueryMatcherRejectsWrongArtistEmptyIdentityAndSubstrings() {
        XCTAssertFalse(SpotifySearchIdentity.matchesSearchQuery("gaslight101 wrongartist", title: "Gaslight 101", artists: ["Odeal"]))
        XCTAssertFalse(SpotifySearchIdentity.matchesSearchQuery("", title: "Gaslight 101", artists: ["Odeal"]))
        XCTAssertFalse(SpotifySearchIdentity.matchesSearchQuery("gaslight101", title: "", artists: ["Odeal"]))
        XCTAssertFalse(SpotifySearchIdentity.matchesSearchQuery("odeal", title: "", artists: ["Odeal"]))
        XCTAssertFalse(SpotifySearchIdentity.matchesSearchQuery("gaslight", title: "Gaslight 101", artists: ["Odeal"]))
        XCTAssertFalse(SpotifySearchIdentity.matchesSearchQuery("gaslight101 odeal live", title: "Gaslight 101", artists: ["Odeal"]))
    }

    func testQueryMatcherSupportsCombinedArtistLists() {
        XCTAssertTrue(SpotifySearchIdentity.matchesSearchQuery(
            "blame u odeal wizkid", title: "Blame U", artists: ["Odeal", "Wizkid"]
        ))
    }

    func testDistinctCombinedIdentitiesAreAmbiguous() {
        let first = SpotifySearchIdentity.normalizedIdentity(title: "Gaslight 101", artists: ["Odeal"])!
        let second = SpotifySearchIdentity.normalizedIdentity(title: "Gaslight 101", artists: ["Another Artist"])!
        XCTAssertTrue(SpotifySearchIdentity.hasAmbiguousCombinedMatches([first, second]))
        XCTAssertFalse(SpotifySearchIdentity.hasAmbiguousCombinedMatches([first, first]))
        XCTAssertNil(SpotifySearchIdentity.selectedMatchIndex(
            matchKinds: [.titleAndArtist, .titleAndArtist], normalizedIdentities: [first, second]
        ))
        XCTAssertEqual(SpotifySearchIdentity.selectedMatchIndex(
            matchKinds: [.titleAndArtist, .titleAndArtist], normalizedIdentities: [first, first]
        ), 0)
    }

    func testCombinedMatchRejectsCollisionWithExactTitleOnlyIdentity() {
        let combined = SpotifySearchIdentity.normalizedIdentity(title: "One More", artists: ["Artist X"])!
        let titleOnly = SpotifySearchIdentity.normalizedIdentity(title: "One More Artist X", artists: ["Artist Y"])!
        XCTAssertNil(SpotifySearchIdentity.selectedMatchIndex(
            matchKinds: [.titleAndArtist, .title], normalizedIdentities: [combined, titleOnly]
        ))
    }

    func testArtistOnlyMatchKeepsFirstRankedResult() {
        let first = SpotifySearchIdentity.normalizedIdentity(title: "Song One", artists: ["Odeal"])!
        let second = SpotifySearchIdentity.normalizedIdentity(title: "Song Two", artists: ["Odeal"])!
        XCTAssertEqual(SpotifySearchIdentity.selectedMatchIndex(
            matchKinds: [.artist, .artist], normalizedIdentities: [first, second]
        ), 0)
    }

    func testDuplicateCatalogReleasesWithSameIdentityBothRemainEligible() {
        let uris = [
            "spotify:track:2AsdsBTAtp5EckmvsbUKtH",
            "spotify:track:0zyTXbKeSEfgOUT6iZD3Ws"
        ]
        let eligibleURIs = uris.filter { _ in
            SpotifySearchIdentity.searchQueryMatchKind("onome odeal", title: "ONOME", artists: ["Odeal"]) == .titleAndArtist
        }
        XCTAssertEqual(eligibleURIs, uris)
        XCTAssertEqual(
            SpotifySearchIdentity.normalizedIdentity(title: "ONOME", artists: ["Odeal"]),
            SpotifySearchIdentity.normalizedIdentity(title: "ONOME", artists: ["Odeal"])
        )
    }

}
