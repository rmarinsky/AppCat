#if canImport(AppCat)
    @testable import AppCat
#endif
import Foundation
import XCTest

final class PickerMouseSelectionTests: XCTestCase {
    @objc func testReleaseFromReplacedSessionCannotCancelCurrentPress() {
        var mouse = PickerMouseSelection()
        let currentSession = UUID()
        _ = mouse.mouseDown(session: currentSession, item: "current", eventNumber: 20)

        XCTAssertEqual(mouse.mouseUp(session: UUID(), item: "old", eventNumber: 21), .passThrough)
        XCTAssertTrue(mouse.isTracking)
        XCTAssertFalse(mouse.allowsModifierCommit)
        XCTAssertEqual(mouse.mouseUp(session: currentSession, item: "current", eventNumber: 22), .select("current"))
    }

    @objc func testModifierReleaseCannotCommitWhileMouseOwnsTheGesture() {
        var mouse = PickerMouseSelection()
        let session = UUID()
        XCTAssertTrue(mouse.allowsModifierCommit)
        _ = mouse.mouseDown(session: session, item: "first", eventNumber: 10)
        XCTAssertFalse(mouse.allowsModifierCommit)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: 11), .select("first"))
        XCTAssertTrue(mouse.allowsModifierCommit)
    }

    @objc func testReleaseOutsideOriginalTileCancelsWithoutOpeningAnotherTile() {
        let session = UUID()
        for releasedItem: String? in [nil, "second"] {
            var mouse = PickerMouseSelection()
            _ = mouse.mouseDown(session: session, item: "first", eventNumber: 10)
            XCTAssertEqual(mouse.mouseUp(session: session, item: releasedItem, eventNumber: 11), .cancel)
            XCTAssertFalse(mouse.isTracking)
        }
    }

    @objc func testOldSessionAndUnrelatedMouseUpCannotCommitOrStealNewPress() {
        var mouse = PickerMouseSelection()
        let session = UUID()
        _ = mouse.mouseDown(session: session, item: "first", eventNumber: 10)
        XCTAssertEqual(mouse.mouseUp(session: UUID(), item: "first", eventNumber: 11), .passThrough)
        XCTAssertTrue(mouse.isTracking)
        _ = mouse.mouseDown(session: session, item: "second", eventNumber: 20)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: 11), .passThrough)
        XCTAssertTrue(mouse.isTracking)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "second", eventNumber: 21), .select("second"))
    }

    @objc func testEscapeOrSessionCloseCancelsPendingPress() {
        var mouse = PickerMouseSelection()
        let session = UUID()
        _ = mouse.mouseDown(session: session, item: "first", eventNumber: 10)
        mouse.cancel()
        XCTAssertFalse(mouse.isTracking)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: 11), .passThrough)
        XCTAssertEqual(mouse.mouseDown(session: nil, item: "first", eventNumber: 11), .passThrough)
        XCTAssertEqual(mouse.mouseDown(session: session, item: nil, eventNumber: 11), .passThrough)
    }

    @objc func testPressConsumesWithoutSelectingAndReleaseSelectsOnce() {
        // Physical macOS 27 clicks in the diagnostic trace paired down/up as 8410/8410.
        // Retain coverage for later-numbered releases as well.
        for releaseNumber in [8410, 8411] {
            var mouse = PickerMouseSelection()
            let session = UUID()
            XCTAssertEqual(mouse.mouseDown(session: session, item: "first", eventNumber: 8410), .consume)
            XCTAssertTrue(mouse.isTracking)
            XCTAssertFalse(mouse.allowsModifierCommit)
            XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: releaseNumber), .select("first"))
            XCTAssertFalse(mouse.isTracking)
            XCTAssertTrue(mouse.allowsModifierCommit)
            XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: releaseNumber), .passThrough)
        }
    }
}
