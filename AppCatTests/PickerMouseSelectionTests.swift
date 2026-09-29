#if canImport(AppCat)
    @testable import AppCat
#endif
import Foundation
import XCTest

final class PickerMouseSelectionTests: XCTestCase {
    @objc func testModifierReleaseCannotCommitWhileMouseOwnsTheGesture() {
        var mouse = PickerMouseSelection()
        let session = UUID()
        XCTAssertTrue(mouse.allowsModifierCommit)
        _ = mouse.mouseDown(session: session, item: "first", eventNumber: 10)
        XCTAssertFalse(mouse.allowsModifierCommit)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: 10), .select("first"))
        XCTAssertTrue(mouse.allowsModifierCommit)
    }

    @objc func testReleaseOutsideOriginalTileCancelsWithoutOpeningAnotherTile() {
        let session = UUID()
        for releasedItem: String? in [nil, "second"] {
            var mouse = PickerMouseSelection()
            _ = mouse.mouseDown(session: session, item: "first", eventNumber: 10)
            XCTAssertEqual(mouse.mouseUp(session: session, item: releasedItem, eventNumber: 10), .cancel)
            XCTAssertFalse(mouse.isTracking)
        }
    }

    @objc func testOldSessionAndUnrelatedMouseUpCannotCommitOrStealNewPress() {
        var mouse = PickerMouseSelection()
        let session = UUID()
        _ = mouse.mouseDown(session: session, item: "first", eventNumber: 10)
        XCTAssertEqual(mouse.mouseUp(session: UUID(), item: "first", eventNumber: 10), .consume)
        XCTAssertFalse(mouse.isTracking)
        _ = mouse.mouseDown(session: session, item: "second", eventNumber: 11)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: 10), .passThrough)
        XCTAssertTrue(mouse.isTracking)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "second", eventNumber: 11), .select("second"))
    }

    @objc func testEscapeOrSessionCloseCancelsPendingPress() {
        var mouse = PickerMouseSelection()
        let session = UUID()
        _ = mouse.mouseDown(session: session, item: "first", eventNumber: 10)
        mouse.cancel()
        XCTAssertFalse(mouse.isTracking)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: 10), .passThrough)
        XCTAssertEqual(mouse.mouseDown(session: nil, item: "first", eventNumber: 11), .passThrough)
        XCTAssertEqual(mouse.mouseDown(session: session, item: nil, eventNumber: 11), .passThrough)
    }

    @objc func testPressConsumesWithoutSelectingAndReleaseSelectsOnce() {
        var mouse = PickerMouseSelection()
        let session = UUID()
        XCTAssertEqual(mouse.mouseDown(session: session, item: "first", eventNumber: 10), .consume)
        XCTAssertTrue(mouse.isTracking)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: 10), .select("first"))
        XCTAssertFalse(mouse.isTracking)
        XCTAssertEqual(mouse.mouseUp(session: session, item: "first", eventNumber: 10), .passThrough)
    }
}
