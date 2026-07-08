@testable import AppCat
import AppKit
import XCTest

final class PickerSessionTests: XCTestCase {
    // MARK: - Coordinator dismiss clears pending state

    /// Auto-routed opens can dismiss before any picker window was ever created; the coordinator
    /// itself must clear the routing state or a stale pendingURL blocks main-window opens.
    @MainActor
    func testDismissPickerWithoutControllerClearsPendingState() throws {
        let state = AppState()
        let coordinator = PickerCoordinator()
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))

        state.setPendingOpen(displayURLs: [url], launchURLs: [url])
        state.isPickerVisible = true
        state.isManualPickerPresentation = true
        state.pickerItemsSnapshot = [PickerItem(app: makeApp(id: "test.app"))]

        coordinator.dismissPicker(state: state)

        XCTAssertNil(state.pendingURL)
        XCTAssertTrue(state.pendingAdditionalURLs.isEmpty)
        XCTAssertTrue(state.pendingLaunchURLs.isEmpty)
        XCTAssertFalse(state.isPickerVisible)
        XCTAssertFalse(state.isManualPickerPresentation)
        XCTAssertTrue(state.pickerItemsSnapshot.isEmpty)
    }

    // MARK: - Focus remap on in-place snapshot refresh

    @MainActor
    func testRemappedFocusFollowsFocusedItemID() {
        let old = [item("a"), item("b"), item("c")]
        let new = [item("b"), item("c"), item("a")]
        XCTAssertEqual(PickerWindowController.remappedFocusIndex(oldItems: old, newItems: new, oldIndex: 0), 2)
    }

    @MainActor
    func testRemappedFocusFallsBackToClampedPositionWhenItemRemoved() {
        let old = [item("a"), item("b"), item("c")]
        let new = [item("a"), item("b")]
        XCTAssertEqual(PickerWindowController.remappedFocusIndex(oldItems: old, newItems: new, oldIndex: 2), 1)
    }

    @MainActor
    func testRemappedFocusHandlesEmptyAndOutOfBoundsInput() {
        let items = [item("a")]
        XCTAssertEqual(PickerWindowController.remappedFocusIndex(oldItems: items, newItems: [], oldIndex: 0), 0)
        XCTAssertEqual(PickerWindowController.remappedFocusIndex(oldItems: [], newItems: items, oldIndex: 5), 0)
        XCTAssertEqual(PickerWindowController.remappedFocusIndex(oldItems: items, newItems: items, oldIndex: 9), 0)
    }

    // MARK: - Icon downsampling

    func testDownsampledIconHasSingleTileSizedRep() {
        let source = NSImage(size: NSSize(width: 1024, height: 1024))
        source.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
        source.unlockFocus()

        let icon = AppIconLoader.downsampled(source)

        XCTAssertEqual(icon.representations.count, 1)
        XCTAssertEqual(icon.size, NSSize(width: 64, height: 64))
        let rep = try? XCTUnwrap(icon.representations.first as? NSBitmapImageRep)
        XCTAssertEqual(rep?.pixelsWide, 128)
        XCTAssertEqual(rep?.pixelsHigh, 128)
    }

    // MARK: - Helpers

    private func item(_ id: String) -> PickerItem {
        PickerItem(app: makeApp(id: id))
    }

    private func makeApp(id: String) -> InstalledApp {
        InstalledApp(
            id: id,
            displayName: id,
            appURL: URL(fileURLWithPath: "/Applications/\(id).app"),
            urlSchemes: [],
            hostPatterns: [],
            isVisible: true,
            sortOrder: 0
        )
    }
}
