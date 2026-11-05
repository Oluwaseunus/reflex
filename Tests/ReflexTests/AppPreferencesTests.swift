import Foundation
import XCTest
@testable import Reflex

final class AppPreferencesTests: XCTestCase {
    func testExistingPreferencesKeepSpotifySelected() throws {
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(preferences.selectedPlayer, .spotify)
    }

    func testPlayerSelectionSurvivesSaving() throws {
        for player in PlaybackPlayerSelection.allCases {
            var preferences = AppPreferences()
            preferences.selectedPlayer = player
            let data = try JSONEncoder().encode(preferences)
            XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: data).selectedPlayer, player)
        }
    }

    func testAlbumArtworkBackgroundDefaultsToEnabledForExistingPreferences() throws {
        let legacyPreferences = Data(#"{"showNowPlaying":false,"searchHighlightStyle":"neutral"}"#.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: legacyPreferences)

        XCTAssertTrue(preferences.useAlbumArtworkBackground)
        XCTAssertFalse(preferences.showNowPlaying)
        XCTAssertEqual(preferences.searchHighlightStyle, .neutral)
    }

    func testAlbumArtworkBackgroundChoiceSurvivesSaving() throws {
        for enabled in [false, true] {
            var preferences = AppPreferences()
            preferences.useAlbumArtworkBackground = enabled

            let saved = try JSONEncoder().encode(preferences)
            let restored = try JSONDecoder().decode(AppPreferences.self, from: saved)

            XCTAssertEqual(restored.useAlbumArtworkBackground, enabled)
        }
    }
}
