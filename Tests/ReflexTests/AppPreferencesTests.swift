import Foundation
import XCTest
@testable import Reflex

final class AppPreferencesTests: XCTestCase {
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
