import ApplicationServices
import XCTest
@testable import Reflex

final class SpotifyQuickSearchOverlayTests: XCTestCase {
    private let quickSearchRoles: Set<String> = [kAXGroupRole, kAXComboBoxRole, kAXListRole, kAXStaticTextRole]
    private let quickSearchLabels: Set<String> = ["Navigate", "Enter", "Open", "Shift", "Play", "Search"]

    func testCapturedQuickSearchStructureIsRecognizedWithoutQueryOrResultText() {
        XCTAssertTrue(SpotifyQuickSearchOverlay.matches(
            groupLabel: "Search", descendantRoles: quickSearchRoles, descendantLabels: quickSearchLabels
        ))
    }

    func testNormalSearchFieldDoesNotTriggerEscape() {
        XCTAssertFalse(SpotifyQuickSearchOverlay.matches(
            groupLabel: "Search", descendantRoles: [kAXComboBoxRole, kAXButtonRole],
            descendantLabels: ["Search", "What do you want to play?", "Browse"]
        ))
    }

    func testCapturedEmptyQuickSearchIsRecognized() {
        XCTAssertTrue(SpotifyQuickSearchOverlay.matches(
            groupLabel: "Search", descendantRoles: [kAXGroupRole, kAXComboBoxRole],
            descendantLabels: ["Search", "What do you want to play?"]
        ))
    }

    func testExposedMainPlayerPreventsEscapeEvenWithMatchingSearchGroup() {
        XCTAssertFalse(SpotifyQuickSearchOverlay.matches(
            groupLabel: "Search", descendantRoles: [kAXGroupRole, kAXComboBoxRole],
            descendantLabels: ["Search", "What do you want to play?"], mainPlayerExposed: true
        ))
    }

    func testSearchSuggestionsWithoutModalKeyboardHintsDoNotTriggerEscape() {
        XCTAssertFalse(SpotifyQuickSearchOverlay.matches(
            groupLabel: "Search", descendantRoles: quickSearchRoles,
            descendantLabels: ["Search", "Play", "What do you want to play?"]
        ))
    }

    func testOtherDialogsDoNotTriggerEscape() {
        XCTAssertFalse(SpotifyQuickSearchOverlay.matches(
            groupLabel: "Connect to a device", descendantRoles: quickSearchRoles,
            descendantLabels: quickSearchLabels
        ))
    }
}
