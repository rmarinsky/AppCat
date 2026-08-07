@testable import AppCat
import AppKit
import KeyboardShortcuts
import XCTest

final class PickerSessionTests: XCTestCase {
    @MainActor
    func testRefreshingPickerPermissionsPublishesNewValues() {
        let state = AppState()

        state.refreshPickerPermissions(inputMonitoring: false, accessibility: false)
        XCTAssertFalse(state.hasInputMonitoringPermission)
        XCTAssertFalse(state.hasAccessibilityPermission)

        state.refreshPickerPermissions(inputMonitoring: true, accessibility: true)
        XCTAssertTrue(state.hasInputMonitoringPermission)
        XCTAssertTrue(state.hasAccessibilityPermission)
    }

    @MainActor
    func testPrewarmedPickerCoordinatorIsReleased() {
        weak var releasedCoordinator: PickerCoordinator?

        autoreleasepool {
            let coordinator = PickerCoordinator()
            releasedCoordinator = coordinator
            coordinator.prewarmPicker(state: AppState())
        }

        XCTAssertNil(releasedCoordinator)
    }

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
    func testRefreshSnapshotForVisibleToggleSessionPublishesEmptyResult() {
        let state = AppState()
        let coordinator = PickerCoordinator()
        state.pickerInvocationSource = .toggleShortcut
        state.apps = [makeApp(id: "test.closed")]
        state.regularAppBundleIDs = ["test.closed"]
        state.runningAppBundleIDs = ["test.closed"]
        state.appActivityUpdatedAt = Date()
        state.appWindowActivityUpdatedAt = Date()
        state.runningWindowsByAppID = [:]
        state.showWindowlessApps = true

        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        if NSApp.isActive { NSApp.deactivate() }
        coordinator.showPicker(state: state)
        defer { coordinator.dismissPicker(state: state) }

        state.isPickerVisible = true
        state.isPickerPresentationPending = false
        XCTAssertEqual(state.pickerItemsSnapshot.map(\.id), ["app:test.closed"])

        state.runningAppBundleIDs = []
        state.regularAppBundleIDs = []
        coordinator.refreshManualPickerSession()

        XCTAssertTrue(state.pickerItemsSnapshot.isEmpty)
        XCTAssertEqual(state.focusedBrowserIndex, 0)
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

    // MARK: - Initial focus lands on the previous window

    func testManualPickerOpensFocusedOnThePreviousWindow() {
        let items = [item("test.current"), item("test.previous")]

        XCTAssertEqual(
            PickerInitialFocusPolicy.initialIndex(
                items: items,
                frontmostRankKey: WindowActivationKey.app("test.current"),
                invocationSource: .toggleShortcut
            ),
            1
        )
    }

    /// An app with one open window renders as an app tile, but the recorded frontmost key is a
    /// *window* key. Matching only on the exact key would leave focus on the app you are already in
    /// for the most common case there is.
    func testManualPickerSkipsSingleWindowFrontmostAppRenderedAsAnAppTile() {
        let items = [item("test.current"), item("test.previous")]

        XCTAssertEqual(
            PickerInitialFocusPolicy.initialIndex(
                items: items,
                frontmostRankKey: WindowActivationKey.window(bundleID: "test.current", title: "Only Window"),
                invocationSource: .toggleShortcut
            ),
            1
        )
    }

    /// If the window you are in was filtered out of the list (hidden, or windowless with windowless
    /// apps switched off), index 0 *is* the previous window — skipping again would overshoot.
    func testManualPickerStaysOnIndexZeroWhenTheFrontmostTargetIsNotListed() {
        let items = [item("test.previous"), item("test.older")]

        XCTAssertEqual(
            PickerInitialFocusPolicy.initialIndex(
                items: items,
                frontmostRankKey: WindowActivationKey.app("test.hidden"),
                invocationSource: .toggleShortcut
            ),
            0
        )
    }

    func testInitialFocusStaysOnIndexZeroForNonSwitcherAndDegenerateSessions() {
        let items = [item("test.current"), item("test.previous")]
        let frontmost = WindowActivationKey.app("test.current")

        // Link routing lists destinations for a URL, not a history — there is no "previous".
        XCTAssertEqual(
            PickerInitialFocusPolicy.initialIndex(
                items: items,
                frontmostRankKey: frontmost,
                invocationSource: .linkRouting
            ),
            0
        )
        // Hold-⌥Tab presents at 0 and steps +1 itself; opting in here would land on 2.
        XCTAssertEqual(
            PickerInitialFocusPolicy.initialIndex(
                items: items,
                frontmostRankKey: frontmost,
                invocationSource: .holdOptionTab
            ),
            0
        )
        XCTAssertEqual(
            PickerInitialFocusPolicy.initialIndex(
                items: [item("test.current")],
                frontmostRankKey: frontmost,
                invocationSource: .toggleShortcut
            ),
            0
        )
        XCTAssertEqual(
            PickerInitialFocusPolicy.initialIndex(
                items: items,
                frontmostRankKey: nil,
                invocationSource: .toggleShortcut
            ),
            0
        )
    }

    // MARK: - Commit on modifier release

    func testWatchedModifiersFollowTheConfiguredShortcut() {
        XCTAssertEqual(
            PickerCommitModifierPolicy.watchedModifiers(for: .init(.tab, modifiers: [.option])),
            [.option]
        )
        XCTAssertEqual(
            PickerCommitModifierPolicy.watchedModifiers(for: .init(.b, modifiers: [.option, .command])),
            [.option, .command]
        )
        XCTAssertNil(
            PickerCommitModifierPolicy.watchedModifiers(for: .init(.f13)),
            "A modifier-free chord has no release to wait for; the picker stays modal"
        )
        XCTAssertNil(PickerCommitModifierPolicy.watchedModifiers(for: nil))
    }

    func testCommitTriggersOnlyOnceTheWatchedModifierIsReleased() {
        XCTAssertFalse(PickerCommitModifierPolicy.shouldCommit(watched: [.option], current: [.option]))
        XCTAssertFalse(
            PickerCommitModifierPolicy.shouldCommit(watched: [.option], current: [.option, .shift]),
            "⇧⌥Tab still holds ⌥, so stepping backward must not commit"
        )
        XCTAssertTrue(PickerCommitModifierPolicy.shouldCommit(watched: [.option], current: []))
        XCTAssertTrue(
            PickerCommitModifierPolicy.shouldCommit(watched: [.option, .command], current: [.command]),
            "Releasing any watched modifier ends the gesture"
        )
    }

    @MainActor
    func testModifierWatcherCommitsOnceWhenModifiersAreReleased() async {
        var heldModifiers: NSEvent.ModifierFlags = [.option]
        var commitCount = 0
        let watcher = PickerCommitModifierWatcher(
            dependencies: .init(currentModifiers: { heldModifiers }, sleep: { _ in await Task.yield() })
        )
        watcher.isSessionAlive = { true }
        watcher.onCommit = { commitCount += 1 }

        watcher.arm(watching: [.option])
        await Task.yield()
        XCTAssertEqual(commitCount, 0, "Still held")

        heldModifiers = []
        while watcher.isArmed { await Task.yield() }

        XCTAssertEqual(commitCount, 1)
        XCTAssertFalse(watcher.isArmed)
    }

    /// Escape, click-away, and resign-key all end a session without telling the watcher; polling the
    /// session instead of hooking each path is what keeps them from committing a dismissed picker.
    @MainActor
    func testModifierWatcherDisarmsWhenTheSessionEnds() async {
        var commitCount = 0
        let watcher = PickerCommitModifierWatcher(
            dependencies: .init(currentModifiers: { [] }, sleep: { _ in await Task.yield() })
        )
        watcher.isSessionAlive = { false }
        watcher.onCommit = { commitCount += 1 }

        watcher.arm(watching: [.option])
        while watcher.isArmed { await Task.yield() }

        XCTAssertEqual(commitCount, 0)
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
