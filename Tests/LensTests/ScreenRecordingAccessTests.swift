import XCTest
@testable import Lens

final class ScreenRecordingAccessTests: XCTestCase {
    @MainActor func testAutomaticChecksNeverRequestPermission() {
        var requests = 0
        let access = ScreenRecordingAccess(preflight: { false }, request: { requests += 1; return false })
        for _ in 0..<100 { XCTAssertFalse(access.isGranted) }
        XCTAssertEqual(requests, 0)
    }

    @MainActor func testDeniedRequestIsNotRepeatedAndExternalGrantIsObserved() {
        var granted = false
        var requests = 0
        let access = ScreenRecordingAccess(preflight: { granted }, request: { requests += 1; return false })
        XCTAssertFalse(access.requestFromUserAction())
        XCTAssertFalse(access.requestFromUserAction())
        XCTAssertEqual(requests, 1)
        granted = true
        XCTAssertTrue(access.requestFromUserAction())
        XCTAssertEqual(requests, 1)
    }

    @MainActor func testGrantedBuildDoesNotRequestAgain() {
        var requests = 0
        let access = ScreenRecordingAccess(preflight: { true }, request: { requests += 1; return true })
        XCTAssertTrue(access.requestFromUserAction())
        XCTAssertFalse(access.requestedThisLaunch)
        XCTAssertEqual(requests, 0)
    }
}
