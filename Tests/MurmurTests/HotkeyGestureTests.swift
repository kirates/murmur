import XCTest
@testable import Murmur

final class HotkeyGestureTests: XCTestCase {
    func testHoldStartsAndStopsRecording() {
        var gesture = HotkeyGesture()
        XCTAssertEqual(gesture.handle(.press(at: 0)), .startRecording)
        XCTAssertEqual(gesture.handle(.release(at: 2.0)), .stopRecording)
        XCTAssertFalse(gesture.isLatched)
    }

    func testShortTapStopsOnlyAfterTheDoubleTapWindow() {
        var gesture = HotkeyGesture()
        XCTAssertEqual(gesture.handle(.press(at: 0)), .startRecording)
        XCTAssertEqual(gesture.handle(.release(at: 0.1)), .none)
        XCTAssertEqual(gesture.pendingWindowDeadline, 0.1 + HotkeyGesture.doubleTapWindow)
        XCTAssertEqual(gesture.handle(.windowExpired(at: 0.6)), .stopRecording)
    }

    func testDoubleTapLatches() {
        var gesture = HotkeyGesture()
        XCTAssertEqual(gesture.handle(.press(at: 0)), .startRecording)
        XCTAssertEqual(gesture.handle(.release(at: 0.1)), .none)
        XCTAssertEqual(gesture.handle(.press(at: 0.25)), .none)
        XCTAssertEqual(gesture.handle(.release(at: 0.32)), .none)
        XCTAssertTrue(gesture.isLatched)
    }

    func testLatchKeepsRecordingThroughAStaleWindowExpiry() {
        var gesture = HotkeyGesture()
        _ = gesture.handle(.press(at: 0))
        _ = gesture.handle(.release(at: 0.1))
        _ = gesture.handle(.press(at: 0.25))
        _ = gesture.handle(.release(at: 0.32))
        XCTAssertEqual(gesture.handle(.windowExpired(at: 0.5)), .none)
        XCTAssertTrue(gesture.isLatched)
    }

    func testSingleTapStopsALatchedSession() {
        var gesture = HotkeyGesture()
        _ = gesture.handle(.press(at: 0))
        _ = gesture.handle(.release(at: 0.1))
        _ = gesture.handle(.press(at: 0.25))
        _ = gesture.handle(.release(at: 0.32))

        XCTAssertEqual(gesture.handle(.press(at: 60.0)), .none)
        XCTAssertEqual(gesture.handle(.release(at: 60.1)), .stopRecording)
        XCTAssertFalse(gesture.isLatched)
    }

    func testLatchSurvivesAnArbitrarilyLongSession() {
        var gesture = HotkeyGesture()
        _ = gesture.handle(.press(at: 0))
        _ = gesture.handle(.release(at: 0.1))
        _ = gesture.handle(.press(at: 0.25))
        _ = gesture.handle(.release(at: 0.32))

        XCTAssertEqual(gesture.handle(.windowExpired(at: 3600)), .none)
        XCTAssertTrue(gesture.isLatched)
        XCTAssertEqual(gesture.handle(.press(at: 7200)), .none)
        XCTAssertEqual(gesture.handle(.release(at: 7200.1)), .stopRecording)
    }

    func testHoldJustOverTheThresholdIsNotATap() {
        var gesture = HotkeyGesture()
        _ = gesture.handle(.press(at: 0))
        XCTAssertEqual(gesture.handle(.release(at: HotkeyGesture.tapThreshold + 0.01)), .stopRecording)
        XCTAssertNil(gesture.pendingWindowDeadline)
    }

    func testResetClearsLatch() {
        var gesture = HotkeyGesture()
        _ = gesture.handle(.press(at: 0))
        _ = gesture.handle(.release(at: 0.1))
        _ = gesture.handle(.press(at: 0.25))
        _ = gesture.handle(.release(at: 0.32))
        XCTAssertTrue(gesture.isLatched)

        gesture.reset()
        XCTAssertFalse(gesture.isLatched)
        XCTAssertEqual(gesture.handle(.press(at: 1.0)), .startRecording)
    }
}
