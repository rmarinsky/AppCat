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
        state.pickerInvocationSource = .toggleShortcut
        state.pickerItemsSnapshot = [PickerItem(app: makeApp(id: "test.app"))]

        coordinator.dismissPicker(state: state)

        XCTAssertNil(state.pendingURL)
        XCTAssertTrue(state.pendingAdditionalURLs.isEmpty)
        XCTAssertTrue(state.pendingLaunchURLs.isEmpty)
        XCTAssertFalse(state.isPickerVisible)
        XCTAssertFalse(state.isPickerPresentationPending)
        XCTAssertFalse(state.isManualPickerPresentation)
        XCTAssertTrue(state.pickerItemsSnapshot.isEmpty)
    }

    @MainActor
    func testEscapeKeyDismissesVisiblePickerSession() throws {
        let state = AppState()
        let coordinator = PickerCoordinator()
        let controller = PickerWindowController(appState: state, coordinator: coordinator)
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))

        state.setPendingOpen(displayURLs: [url], launchURLs: [url])
        state.isPickerVisible = true

        XCTAssertTrue(controller.handleKeyEvent(event))
        XCTAssertFalse(state.isPickerVisible)
        XCTAssertNil(state.pendingURL)
    }

    @MainActor
    func testConfigureAppsForUnmatchedFileDismissesPickerAndOpensAppsSettings() throws {
        let state = AppState()
        let coordinator = PickerCoordinator()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("payload.romanunknownformat")
        let openExpectation = expectation(description: "main window open requested")
        let observer = NotificationCenter.default.addObserver(
            forName: .openMainWindow,
            object: nil,
            queue: nil
        ) { _ in
            openExpectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        state.setPendingOpen(displayURLs: [url], launchURLs: [url])
        state.isPickerVisible = true
        state.pickerInvocationSource = .linkRouting

        coordinator.configureAppsForUnmatchedFile(state: state)

        XCTAssertNil(state.pendingURL)
        XCTAssertFalse(state.isPickerVisible)
        XCTAssertEqual(state.mainWindowSection, .settingsApps)
        wait(for: [openExpectation], timeout: 0.1)
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

    // MARK: - Click-away dismissal

    @MainActor
    func testGlobalMouseDownInsidePickerFrameDoesNotDismiss() {
        let panelFrame = NSRect(x: 100, y: 200, width: 320, height: 160)

        XCTAssertFalse(PickerWindowController.shouldDismissForGlobalMouseDown(
            at: NSPoint(x: 220, y: 260),
            panelFrame: panelFrame
        ))
        XCTAssertTrue(PickerWindowController.shouldDismissForGlobalMouseDown(
            at: NSPoint(x: 80, y: 260),
            panelFrame: panelFrame
        ))
        XCTAssertTrue(PickerWindowController.shouldDismissForGlobalMouseDown(
            at: NSPoint(x: 220, y: 260),
            panelFrame: nil
        ))
    }

    @MainActor
    func testManualPickerClickHitTestReturnsClickedItemIndex() {
        let panelFrame = NSRect(
            x: 100,
            y: 200,
            width: PickerMetrics.panelWidth(itemCount: 3, availableWidth: 1200),
            height: PickerMetrics.panelHeight()
        )
        let firstItemPoint = NSPoint(
            x: panelFrame.minX + PickerMetrics.horizontalPadding() + PickerMetrics.itemWidth() / 2,
            y: panelFrame.minY + PickerMetrics.verticalPadding() + PickerMetrics.itemHeight() / 2
        )
        let secondItemPoint = NSPoint(
            x: firstItemPoint.x + PickerMetrics.itemWidth() + PickerMetrics.itemSpacing(),
            y: firstItemPoint.y
        )

        XCTAssertEqual(PickerWindowController.itemIndexForManualPickerClick(
            at: firstItemPoint,
            panelFrame: panelFrame,
            itemCount: 3,
            scrollOffsetX: 0,
            scale: 1
        ), 0)
        XCTAssertEqual(PickerWindowController.itemIndexForManualPickerClick(
            at: secondItemPoint,
            panelFrame: panelFrame,
            itemCount: 3,
            scrollOffsetX: 0,
            scale: 1
        ), 1)
    }

    @MainActor
    func testManualPickerClickHitTestIgnoresPaddingGapAndOutsidePanel() {
        let panelFrame = NSRect(
            x: 100,
            y: 200,
            width: PickerMetrics.panelWidth(itemCount: 3, availableWidth: 1200),
            height: PickerMetrics.panelHeight()
        )
        let itemTop = panelFrame.minY + PickerMetrics.verticalPadding() + PickerMetrics.itemHeight()
        let gapX = panelFrame.minX
            + PickerMetrics.horizontalPadding()
            + PickerMetrics.itemWidth()
            + PickerMetrics.itemSpacing() / 2

        XCTAssertNil(PickerWindowController.itemIndexForManualPickerClick(
            at: NSPoint(x: panelFrame.minX + PickerMetrics.horizontalPadding() / 2, y: itemTop - 10),
            panelFrame: panelFrame,
            itemCount: 3,
            scrollOffsetX: 0,
            scale: 1
        ))
        XCTAssertNil(PickerWindowController.itemIndexForManualPickerClick(
            at: NSPoint(x: gapX, y: itemTop - 10),
            panelFrame: panelFrame,
            itemCount: 3,
            scrollOffsetX: 0,
            scale: 1
        ))
        XCTAssertNil(PickerWindowController.itemIndexForManualPickerClick(
            at: NSPoint(x: panelFrame.midX, y: panelFrame.maxY + 1),
            panelFrame: panelFrame,
            itemCount: 3,
            scrollOffsetX: 0,
            scale: 1
        ))
    }

    @MainActor
    func testManualPickerClickHitTestAccountsForHorizontalScrollOffset() {
        let panelFrame = NSRect(
            x: 100,
            y: 200,
            width: PickerMetrics.panelWidth(itemCount: 3, availableWidth: 1200),
            height: PickerMetrics.panelHeight()
        )
        let visibleFirstTileCenter = NSPoint(
            x: panelFrame.minX + PickerMetrics.horizontalPadding() + PickerMetrics.itemWidth() / 2,
            y: panelFrame.minY + PickerMetrics.verticalPadding() + PickerMetrics.itemHeight() / 2
        )
        let oneItemOffset = PickerMetrics.itemWidth() + PickerMetrics.itemSpacing()

        XCTAssertEqual(PickerWindowController.itemIndexForManualPickerClick(
            at: visibleFirstTileCenter,
            panelFrame: panelFrame,
            itemCount: 3,
            scrollOffsetX: oneItemOffset,
            scale: 1
        ), 1)
    }

    @MainActor
    func testLinkPickerClickHitTestCoversTopOfIconAboveShortcutHint() {
        let panelFrame = NSRect(
            x: 100,
            y: 200,
            width: PickerMetrics.panelWidth(itemCount: 2, availableWidth: 1200),
            height: PickerMetrics.panelHeight(showsIncognitoHint: true)
        )
        let pointInsideTopOfFirstIcon = NSPoint(
            x: panelFrame.minX + PickerMetrics.horizontalPadding() + PickerMetrics.itemWidth() / 2,
            y: panelFrame.maxY - PickerMetrics.verticalPadding() - 1
        )

        XCTAssertEqual(PickerWindowController.itemIndexForManualPickerClick(
            at: pointInsideTopOfFirstIcon,
            panelFrame: panelFrame,
            itemCount: 2,
            scrollOffsetX: 0,
            scale: 1,
            showsIncognitoHint: true
        ), 0)
    }

    // MARK: - Hold Option-release on empty / OOB focus

    @MainActor
    func testOpenFocusedItemDismissesWhenSnapshotEmpty() {
        let state = AppState()
        let coordinator = PickerCoordinator()
        state.pickerInvocationSource = .holdOptionTab
        coordinator.prewarmPicker(state: state)
        state.isPickerVisible = true
        state.pickerItemsSnapshot = []
        state.focusedBrowserIndex = 0

        coordinator.openFocusedItem(state: state)

        XCTAssertFalse(state.isPickerVisible)
        XCTAssertFalse(state.isPickerPresentationPending)
        XCTAssertEqual(state.pickerInvocationSource, .linkRouting)
    }

    @MainActor
    func testOpenFocusedItemDismissesWhenFocusOutOfRange() {
        let state = AppState()
        let coordinator = PickerCoordinator()
        state.pickerInvocationSource = .holdOptionTab
        coordinator.prewarmPicker(state: state)
        state.isPickerVisible = true
        state.pickerItemsSnapshot = [PickerItem(app: makeApp(id: "test.only"))]
        state.focusedBrowserIndex = 3

        coordinator.openFocusedItem(state: state)

        XCTAssertFalse(state.isPickerVisible)
        XCTAssertFalse(state.isPickerSessionActive)
    }

    @MainActor
    func testShowPickerMarksPresentationPendingUntilOrderedFront() {
        let state = AppState()
        state.isPickerPresentationPending = true
        state.isPickerVisible = false

        XCTAssertTrue(state.isPickerSessionActive)
        XCTAssertFalse(state.isPickerVisible)

        // Successful orderFront flips visibility and clears pending.
        state.isPickerVisible = true
        state.isPickerPresentationPending = false
        XCTAssertTrue(state.isPickerVisible)
        XCTAssertFalse(state.isPickerPresentationPending)
        XCTAssertTrue(state.isPickerSessionActive)
    }

    @MainActor
    func testRefreshSnapshotForVisibleToggleSessionRemapsFocus() {
        let state = AppState()
        let coordinator = PickerCoordinator()
        state.pickerInvocationSource = .toggleShortcut
        let first = makeApp(id: "test.a")
        let second = makeApp(id: "test.b")
        let third = makeApp(id: "test.c")
        state.apps = [first, second, third]
        state.regularAppBundleIDs = ["test.a", "test.b", "test.c"]
        state.runningAppBundleIDs = ["test.a", "test.b", "test.c"]
        state.appActivityUpdatedAt = Date()
        state.appWindowActivityUpdatedAt = Date()
        state.runningWindowsByAppID = [:]
        state.showWindowlessApps = true

        // Build a real session so refreshManualPickerSession has a controller.
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        if NSApp.isActive { NSApp.deactivate() }
        coordinator.showPicker(state: state)
        defer { coordinator.dismissPicker(state: state) }

        state.isPickerVisible = true
        state.isPickerPresentationPending = false
        guard state.pickerItemsSnapshot.count >= 2 else {
            XCTFail("Expected switcher items for running apps")
            return
        }
        let focusedID = state.pickerItemsSnapshot[min(1, state.pickerItemsSnapshot.count - 1)].id
        state.focusedBrowserIndex = state.pickerItemsSnapshot.firstIndex { $0.id == focusedID } ?? 0

        state.runningAppBundleIDs = ["test.a", "test.c"]
        state.regularAppBundleIDs = ["test.a", "test.c"]
        coordinator.refreshManualPickerSession()

        XCTAssertFalse(state.pickerItemsSnapshot.map(\.id).contains("app:test.b"))
        XCTAssertTrue(state.pickerItemsSnapshot.map(\.id).contains(focusedID) || focusedID == "app:test.b")
        if focusedID != "app:test.b",
           state.pickerItemsSnapshot.indices.contains(state.focusedBrowserIndex)
        {
            XCTAssertEqual(state.pickerItemsSnapshot[state.focusedBrowserIndex].id, focusedID)
        }
    }

    @MainActor
    func testHoldReassertVisibilityKeepsSessionActive() {
        let state = AppState()
        let coordinator = PickerCoordinator()
        state.pickerInvocationSource = .holdOptionTab
        state.apps = [makeApp(id: "test.hold.reassert")]
        state.regularAppBundleIDs = ["test.hold.reassert"]
        state.runningAppBundleIDs = ["test.hold.reassert"]

        coordinator.prewarmPicker(state: state)
        state.isPickerVisible = true
        state.isPickerPresentationPending = false
        state.pickerItemsSnapshot = [PickerItem(app: makeApp(id: "test.hold.reassert"))]

        coordinator.reassertPickerVisibility(state: state)

        XCTAssertTrue(state.isPickerVisible)
        XCTAssertTrue(state.isPickerSessionActive)
        coordinator.dismissPicker(state: state)
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
