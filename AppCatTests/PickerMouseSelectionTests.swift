#if canImport(AppCat)
@testable import AppCat
#endif
import Foundation
import XCTest

final class PickerMouseSelectionTests: XCTestCase {
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
