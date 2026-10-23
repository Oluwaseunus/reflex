import XCTest
@testable import Reflex

@MainActor
final class SpotifyDeviceWorkWaitTests: XCTestCase {
    func testWaitReturnsWhenDeviceWorkFinishes() async throws {
        var isUpdating = true
        var observedBusyState = 0
        let finishDeviceWork = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(20))
            isUpdating = false
        }

        try await SpotifyBackgroundController.waitForDeviceWork(
            isUpdating: {
                observedBusyState += 1
                return isUpdating
            },
            timeout: .seconds(1),
            pollingInterval: .milliseconds(2)
        )
        XCTAssertGreaterThan(observedBusyState, 0)
        XCTAssertFalse(isUpdating)
        try await finishDeviceWork.value
    }

    func testWaitTimesOutWhileDeviceWorkRemainsBusy() async {
        do {
            try await SpotifyBackgroundController.waitForDeviceWork(
                isUpdating: { true },
                timeout: .milliseconds(20),
                pollingInterval: .milliseconds(2)
            )
            XCTFail("Expected the device-work wait to time out")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("device work did not finish"))
        }
    }

    func testWaitPropagatesCancellation() async {
        var observedBusyState = 0
        let waitForDeviceWork = Task { @MainActor in
            try await SpotifyBackgroundController.waitForDeviceWork(
                isUpdating: {
                    observedBusyState += 1
                    return true
                },
                timeout: .seconds(1),
                pollingInterval: .milliseconds(2)
            )
        }
        for _ in 0..<10 where observedBusyState == 0 {
            await Task.yield()
        }
        guard observedBusyState > 0 else {
            waitForDeviceWork.cancel()
            _ = await waitForDeviceWork.result
            XCTFail("The helper did not observe device work before cancellation")
            return
        }
        waitForDeviceWork.cancel()

        do {
            try await waitForDeviceWork.value
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
