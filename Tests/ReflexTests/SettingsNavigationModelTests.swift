import Foundation
import XCTest
@testable import Reflex

final class SettingsNavigationModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsNavigationModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRestoresLastSelectedPane() {
        let navigation = SettingsNavigationModel(defaults: defaults)
        XCTAssertEqual(navigation.selectedPane, .general)

        navigation.selectedPane = .shortcuts

        let restoredNavigation = SettingsNavigationModel(defaults: defaults)
        XCTAssertEqual(restoredNavigation.selectedPane, .shortcuts)
    }

    func testInvalidStoredPaneFallsBackToGeneral() {
        defaults.set("Missing", forKey: Constants.UserDefaultsKeys.lastSettingsPane)

        let navigation = SettingsNavigationModel(defaults: defaults)

        XCTAssertEqual(navigation.selectedPane, .general)
    }
}
