import XCTest
@testable import Reflex

final class SpotifyForegroundPolicyTests: XCTestCase {
    private let chatGPT: pid_t = 101
    private let reflex: pid_t = 202
    private let spotify: pid_t = 303

    func testDeviceRefreshAllowsOriginalAppAndReflexPopupAcrossRepeatedChecks() {
        for current in [chatGPT, reflex, chatGPT, reflex] {
            XCTAssertTrue(SpotifyForegroundPolicy.accepts(expected: chatGPT, current: current, reflex: reflex))
        }
    }

    func testDeviceRefreshStillRejectsSpotifyAndUnrelatedApps() {
        for current in [spotify, pid_t(404)] {
            XCTAssertFalse(SpotifyForegroundPolicy.accepts(expected: chatGPT, current: current, reflex: reflex))
        }
    }

    func testRefreshStartingInReflexStillRejectsSpotify() {
        XCTAssertTrue(SpotifyForegroundPolicy.accepts(expected: reflex, current: reflex, reflex: reflex))
        XCTAssertFalse(SpotifyForegroundPolicy.accepts(expected: reflex, current: spotify, reflex: reflex))
    }

    func testSearchRemainsStrictWithoutTheReflexAllowance() {
        XCTAssertTrue(SpotifyForegroundPolicy.accepts(expected: chatGPT, current: chatGPT))
        XCTAssertFalse(SpotifyForegroundPolicy.accepts(expected: chatGPT, current: reflex))
    }

    func testMissingCurrentAppDoesNotBypassTheGuard() {
        XCTAssertFalse(SpotifyForegroundPolicy.accepts(expected: chatGPT, current: nil, reflex: reflex))
    }
}
