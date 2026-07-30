@testable import AppCat
import XCTest

final class TapSequenceCounterTests: XCTestCase {
    func testSingleTapCompletesImmediately() {
        var counter = TapSequenceCounter()

        XCTAssertTrue(counter.registerTap(at: 10, requiredCount: 1, interval: 0.45))
        XCTAssertEqual(counter.count, 0)
    }

    func testDoubleTapCompletesWithinInterval() {
        var counter = TapSequenceCounter()

        XCTAssertFalse(counter.registerTap(at: 10, requiredCount: 2, interval: 0.45))
        XCTAssertTrue(counter.registerTap(at: 10.3, requiredCount: 2, interval: 0.45))
        XCTAssertEqual(counter.count, 0)
    }

    func testTapSequenceResetsAfterInterval() {
        var counter = TapSequenceCounter()

        XCTAssertFalse(counter.registerTap(at: 10, requiredCount: 2, interval: 0.45))
        XCTAssertFalse(counter.registerTap(at: 10.8, requiredCount: 2, interval: 0.45))
        XCTAssertEqual(counter.count, 1)
    }

    func testTapSequenceReportsInProgressWithinInterval() {
        var counter = TapSequenceCounter()

        XCTAssertFalse(counter.isSequenceInProgress(at: 10, interval: 0.45))
        XCTAssertFalse(counter.registerTap(at: 10, requiredCount: 2, interval: 0.45))
        XCTAssertTrue(counter.isSequenceInProgress(at: 10.2, interval: 0.45))
        XCTAssertFalse(counter.isSequenceInProgress(at: 10.8, interval: 0.45))
    }
}

