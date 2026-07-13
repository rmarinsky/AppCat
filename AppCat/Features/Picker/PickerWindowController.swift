import AppKit
import SwiftUI

private enum PickerPanelViewID {
    static let surface = NSUserInterfaceItemIdentifier("PickerPanelSurface")
    static let glass = NSUserInterfaceItemIdentifier("PickerPanelGlass")
    static let hosting = NSUserInterfaceItemIdentifier("PickerPanelHosting")
}

enum PickerSurfaceAppearance {
    static func adaptiveTint(for appearance: NSAppearance) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.08)
            : NSColor.black.withAlphaComponent(0.04)
    }
}

/// Borderless NSPanel returns false for canBecomeKey by default,
/// which prevents keyboard and mouse input. Override to allow it.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

final class PickerHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool {
        true
    }
}

enum PickerPanelKeyResignAction: Equatable {
    case refocus
    case remainVisible
    case dismiss
}

enum PickerPanelInteractionPolicy {
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .fullScreenAuxiliary,
        .stationary,
        .ignoresCycle,
    ]
    static let windowLevel = NSWindow.Level.screenSaver
    static let presentationActivationPolicy = NSApplication.ActivationPolicy.accessory
    static let deactivationSettlingDelay: TimeInterval = 0.15
    static let styleMask: NSWindow.StyleMask = [
        .fullSizeContentView,
        .borderless,
        .nonactivatingPanel,
    ]

    static func dismissalActivationPolicy(
        isMainWindowVisibleOnActiveSpace: Bool
    ) -> NSApplication.ActivationPolicy {
        isMainWindowVisibleOnActiveSpace ? .regular : .accessory
    }

    static func shouldRestoreRegularPolicy(
        isPickerVisible: Bool,
        isMainWindowVisibleOnActiveSpace: Bool
    ) -> Bool {
        !isPickerVisible && isMainWindowVisibleOnActiveSpace
    }

    static func shouldWaitForApplicationDeactivation(
        isApplicationActive: Bool,
        wasWaitingForDeactivation: Bool
    ) -> Bool {
        isApplicationActive || wasWaitingForDeactivation
    }

    static func keyResignAction(
        for source: PickerInvocationSource,
        isInDismissGracePeriod: Bool
    ) -> PickerPanelKeyResignAction {
        guard source.requiresKeyboardFocus else { return .remainVisible }
        return isInDismissGracePeriod ? .refocus : .dismiss
    }

    static func apply(to panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = windowLevel
        panel.collectionBehavior = collectionBehavior
    }

    /// A global mouse-down is only observed when AppKit did not deliver the click to AppCat.
    /// Keeping this fallback for every picker makes the first click reliable across activation
    /// policy changes without double-firing a SwiftUI Button that received its local event.
    static func acceptsGlobalClickFallback(for _: PickerInvocationSource) -> Bool {
        true
    }
}

enum PickerPanelPositioning {
    static func centeredOrigin(panelSize: NSSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2
        )
    }

    static func nearCursorOrigin(
        mouseLocation: NSPoint,
        panelSize: NSSize,
        visibleFrame: NSRect,
        scale: CGFloat
    ) -> NSPoint {
        let scale = PickerMetrics.clampedScale(scale)
        var origin = NSPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y - panelSize.height / 2 + 40 * scale
        )
        let margin = PickerMetrics.screenMargin
        origin.x = max(visibleFrame.minX + margin, min(origin.x, visibleFrame.maxX - panelSize.width - margin))
        origin.y = max(visibleFrame.minY + margin, min(origin.y, visibleFrame.maxY - panelSize.height - margin))
        return origin
    }
}

@MainActor
final class PickerWindowController: NSObject {
    private var panel: NSPanel?
    private let appState: AppState
    private let coordinator: PickerCoordinator
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var ignoreDismissUntil: Date = .distantPast
    private var isClosing = false
    private var presentationDeactivationObserver: NSObjectProtocol?
    private var presentationWorkItem: DispatchWorkItem?
    private let dismissGraceInterval: TimeInterval = 0.12
    private var typeAheadBuffer = ""
    private var typeAheadResetTask: Task<Void, Never>?
    private let typeAheadResetDelay: UInt64 = 900_000_000

    init(appState: AppState, coordinator: PickerCoordinator) {
        self.appState = appState
        self.coordinator = coordinator
    }

    /// Build the panel + SwiftUI hosting view without presenting — the first real show() then
    /// skips window/view-graph construction. Safe to call once at launch; no-op if built.
    func prewarm() {
        guard panel == nil else { return }
        let screen = screenNearCursor()
        buildPanelIfNeeded(size: panelSize(for: screen))
        panel?.layoutIfNeeded()
        Log.picker.debug("Picker panel pre-warmed")
    }

    private func buildPanelIfNeeded(size: NSSize) {
        guard panel == nil else { return }
        let newPanel = makePanel(size: size)
        panel = newPanel

        let hostingView = PickerHostingView(
            rootView: PickerView()
                .environment(appState)
                .environment(\.pickerCoordinator, coordinator)
        )
        hostingView.identifier = PickerPanelViewID.hosting
        hostingView.autoresizingMask = [.width, .height]
        let container = pickerContentContainer(in: newPanel) ?? newPanel.contentView!
        hostingView.frame = container.bounds
        // Keep hosting view background transparent so vibrancy shows through
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        hostingView.layer?.isOpaque = false
        installHostingView(hostingView, in: newPanel, fallbackContainer: container)
    }

    func show() {
        isClosing = false
        let wasWaitingForDeactivation = presentationDeactivationObserver != nil || presentationWorkItem != nil
        cancelPendingPresentation()
        removePresentationDeactivationObserver()
        // Every show() starts a fresh session: a second link can arrive while the picker is
        // already open (no close in between), and reusing the previous session's snapshot would
        // render stale items in a panel sized and positioned for the wrong list.
        appState.pickerItemsSnapshot = []
        seedPickerSnapshotIfPossible()
        // Reset focus here, not only in the view's onAppear — after a pre-warm the hidden view
        // has already "appeared" once and onAppear may not fire again for the real presentation.
        appState.focusedBrowserIndex = 0
        let screen = screenNearCursor()
        let targetSize = panelSize(for: screen)

        buildPanelIfNeeded(size: targetSize)

        guard let panel else { return }
        PickerPanelInteractionPolicy.apply(to: panel)
        resizePanelIfNeeded(panel, to: targetSize)
        // A pre-warmed or reused panel may carry stale layer state, so re-apply on every show.
        if let surfaceView = surfaceView(in: panel) {
            applyPanelSurfaceAppearance(to: surfaceView)
        }
        if let visualEffect = materialView(in: panel) {
            applyVisualEffectFallbackAppearance(to: visualEffect)
        }

        positionPanel(panel, on: screen)

        // A nonactivating accessory panel can join another app's fullscreen Space without
        // switching Spaces. If LaunchServices activated AppCat first, wait until deactivation is
        // complete before making the panel key; otherwise the delayed resign would immediately
        // dismiss the picker or leave it visible without keyboard input.
        let shouldWaitForDeactivation = PickerPanelInteractionPolicy.shouldWaitForApplicationDeactivation(
            isApplicationActive: NSApp.isActive,
            wasWaitingForDeactivation: wasWaitingForDeactivation
        )
        NSApp.setActivationPolicy(PickerPanelInteractionPolicy.presentationActivationPolicy)
        if shouldWaitForDeactivation {
            waitForApplicationDeactivationBeforePresenting()
        } else {
            presentPanelAfterDeactivation()
        }
    }

    private func presentPanelAfterDeactivation() {
        guard !isClosing, appState.isPickerVisible, let panel else { return }
        guard !NSApp.isActive else {
            // LaunchServices can briefly reactivate AppCat during the settling interval. Re-arm
            // the deactivation wait instead of abandoning a visible picker session with no panel.
            waitForApplicationDeactivationBeforePresenting()
            return
        }
        removePresentationDeactivationObserver()

        ignoreDismissUntil = Date().addingTimeInterval(dismissGraceInterval)
        panel.orderFrontRegardless()
        if shouldTakeKeyboardFocusForCurrentPresentation {
            focusPanel(panel)
        } else if panel.isKeyWindow {
            // A reused link/toggle panel may still be key when the invocation changes to hold.
            panel.resignKey()
        }

        installMonitors()

        Log.picker.debug("Picker shown")
    }

    private func waitForApplicationDeactivationBeforePresenting() {
        guard !isClosing, appState.isPickerVisible else { return }
        installPresentationDeactivationObserver()
        NSApp.deactivate()
        if !NSApp.isActive {
            schedulePresentationAfterDeactivation()
        }
    }

    private func installPresentationDeactivationObserver() {
        guard presentationDeactivationObserver == nil else { return }
        presentationDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.schedulePresentationAfterDeactivation()
            }
        }
    }

    private func schedulePresentationAfterDeactivation() {
        guard presentationWorkItem == nil else { return }
        removePresentationDeactivationObserver()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.presentationWorkItem = nil
            self.presentPanelAfterDeactivation()
        }
        presentationWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PickerPanelInteractionPolicy.deactivationSettlingDelay,
            execute: workItem
        )
    }

    private func cancelPendingPresentation() {
        presentationWorkItem?.cancel()
        presentationWorkItem = nil
    }

    private func removePresentationDeactivationObserver() {
        if let presentationDeactivationObserver {
            NotificationCenter.default.removeObserver(presentationDeactivationObserver)
            self.presentationDeactivationObserver = nil
        }
    }

    func close() {
        isClosing = true
        cancelPendingPresentation()
        removePresentationDeactivationObserver()
        ignoreDismissUntil = .distantPast
        clearTypeAheadBuffer()
        appState.isPickerVisible = false
        appState.clearPendingOpen()
        appState.pickerInvocationSource = .linkRouting
        appState.pickerItemsSnapshot = []
        removeMonitors()
        panel?.orderOut(nil)
        NSApp.setActivationPolicy(PickerPanelInteractionPolicy.dismissalActivationPolicy(
            isMainWindowVisibleOnActiveSpace: MainWindowActivation.isMainWindowVisibleOnActiveSpace
        ))
        DispatchQueue.main.async { [weak self] in
            self?.isClosing = false
        }
        Log.picker.debug("Picker dismissed")
    }

    private var shouldTakeKeyboardFocusForCurrentPresentation: Bool {
        appState.pickerInvocationSource.requiresKeyboardFocus
    }

    private func focusPanel(_ panel: NSPanel) {
        panel.makeKey()
        panel.makeFirstResponder(hostingView(in: panel))
    }

    // MARK: - Monitors

    private func installMonitors() {
        removeMonitors()

        // Dismiss on click outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isInDismissGracePeriod else { return }
                if self.openItemForGlobalMouseDown(at: NSEvent.mouseLocation, eventType: event.type) {
                    return
                }
                guard Self.shouldDismissForGlobalMouseDown(
                    at: NSEvent.mouseLocation,
                    panelFrame: self.panel?.frame
                ) else { return }
                self.close()
            }
        }

        // Handle keyboard events via local monitor since SwiftUI's
        // .onKeyPress does not work reliably inside an NSPanel.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeMonitors() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private var isInDismissGracePeriod: Bool {
        Date() < ignoreDismissUntil
    }

    // MARK: - Key Handling

    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !isClosing, appState.isPickerVisible else { return false }

        switch Int(event.keyCode) {
        case 53: // Escape
            clearTypeAheadBuffer()
            coordinator.dismissPicker(state: appState)
            return true
        case 36: // Return
            let items = pickerItemsForCurrentSession()
            switch PickerReturnKeyPolicy.action(
                itemCount: items.count,
                focusedIndex: appState.focusedBrowserIndex,
                url: appState.pendingURL,
                invocationSource: appState.pickerInvocationSource
            ) {
            case let .openItem(index):
                open(items[index])
            case .configureApps:
                coordinator.configureAppsForUnmatchedFile(state: appState)
            case .consume:
                break
            }
            return true
        case 51: // Delete / Backspace
            removeLastTypeAheadCharacter()
            return true
        case 48: // Tab
            clearTypeAheadBuffer()
            let itemCount = itemCountForFocusNavigation()
            if event.modifierFlags.contains(.shift) {
                moveFocusWrapping(-1, itemCount: itemCount)
            } else {
                moveFocusWrapping(1, itemCount: itemCount)
            }
            return true
        case 123: // Left arrow
            clearTypeAheadBuffer()
            moveFocus(-1, itemCount: itemCountForFocusNavigation())
            return true
        case 124: // Right arrow
            clearTypeAheadBuffer()
            moveFocus(1, itemCount: itemCountForFocusNavigation())
            return true
        case 125: // Down arrow
            clearTypeAheadBuffer()
            let itemCount = itemCountForFocusNavigation()
            moveFocus(1, itemCount: itemCount)
            return true
        case 126: // Up arrow
            clearTypeAheadBuffer()
            let itemCount = itemCountForFocusNavigation()
            moveFocus(-1, itemCount: itemCount)
            return true
        default:
            let items = pickerItemsForCurrentSession()
            let pressedKeyCode = event.keyCode
            let mode = PickerShortcutOpenPolicy.mode(
                for: event.modifierFlags,
                invocationSource: appState.pickerInvocationSource
            )

            if canHandlePickerShortcut(event),
               let item = PickerShortcutPolicy.item(
                   forKeyCode: pressedKeyCode,
                   in: items,
                   invocationSource: appState.pickerInvocationSource,
                   selectWithNumberKeys: appState.selectWithNumberKeys
               )
            {
                guard !event.isARepeat else { return true }
                open(item, mode: mode, source: .pickerHotkey)
                return true
            }

            if let typed = typeAheadCharacter(from: event) {
                appendTypeAheadCharacter(typed, items: items)
                return true
            }

            return false
        }
    }

    private func canHandlePickerShortcut(_ event: NSEvent) -> Bool {
        guard appState.pickerInvocationSource.allowsDirectSelection else { return false }
        var blocked: NSEvent.ModifierFlags = [.command, .control]
        if appState.isManualPickerPresentation {
            blocked.insert([.shift, .option])
        }
        return event.modifierFlags.intersection(blocked).isEmpty
    }

    private func open(
        _ item: PickerItem,
        mode: BrowserLauncher.OpenMode = .normal,
        source: OpenSource = .pickerClick
    ) {
        if let app = item.app {
            coordinator.openURL(with: app, windowTarget: item.windowTarget, state: appState, source: source)
        } else if let browser = item.browser {
            coordinator.openURL(
                with: browser,
                mode: mode,
                profile: item.profile,
                windowTarget: item.windowTarget,
                state: appState,
                source: source
            )
        }
    }

    private func typeAheadCharacter(from event: NSEvent) -> String? {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return nil }
        guard let value = event.charactersIgnoringModifiers, value.count == 1 else { return nil }
        guard let scalar = value.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) else {
            return nil
        }
        return value
    }

    private func appendTypeAheadCharacter(_ character: String, items: [PickerItem]) {
        typeAheadBuffer += character
        if focusFirstTypeAheadMatch(in: items) == false, typeAheadBuffer.count > 1 {
            typeAheadBuffer = character
            _ = focusFirstTypeAheadMatch(in: items)
        }
        scheduleTypeAheadReset()
    }

    private func removeLastTypeAheadCharacter() {
        guard !typeAheadBuffer.isEmpty else { return }
        typeAheadBuffer.removeLast()
        if typeAheadBuffer.isEmpty {
            clearTypeAheadBuffer()
            return
        }
        _ = focusFirstTypeAheadMatch(in: pickerItemsForCurrentSession())
        scheduleTypeAheadReset()
    }

    @discardableResult
    private func focusFirstTypeAheadMatch(in items: [PickerItem]) -> Bool {
        guard let index = PickerTypeAheadMatcher.firstMatchIndex(in: items, query: typeAheadBuffer) else {
            return false
        }
        appState.focusedBrowserIndex = index
        return true
    }

    private func scheduleTypeAheadReset() {
        typeAheadResetTask?.cancel()
        typeAheadResetTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.typeAheadResetDelay)
            guard !Task.isCancelled else { return }
            self.typeAheadBuffer = ""
            self.typeAheadResetTask = nil
        }
    }

    private func clearTypeAheadBuffer() {
        typeAheadResetTask?.cancel()
        typeAheadResetTask = nil
        typeAheadBuffer = ""
    }

    private func refreshPickerItemsSnapshot() {
        appState.pickerItemsSnapshot = PickerItem.items(
            for: appState.pendingURL,
            pickerBrowsers: appState.pickerBrowsers,
            allBrowsers: appState.browsers,
            apps: appState.apps,
            appUsage: appState.appUsage,
            runningBundleIDs: appState.cachedRunningBundleIDs,
            windowsByAppID: appState.cachedWindowsByAppID,
            activations: appState.appActivations,
            regularBundleIDs: appState.regularAppBundleIDs,
            runningAppsByBundleID: appState.runningAppsByBundleID,
            showWindowlessApps: appState.showWindowlessApps,
            showBackgroundApps: appState.showBackgroundApps,
            hiddenAppIDs: appState.hiddenPickerAppIDs
        )
    }

    private func pickerItemsForCurrentSession() -> [PickerItem] {
        guard appState.pickerItemsSnapshot.isEmpty else { return appState.pickerItemsSnapshot }
        refreshPickerItemsSnapshot()
        return appState.pickerItemsSnapshot
    }

    private func itemCountForFocusNavigation() -> Int {
        let cachedCount = appState.pickerItemsSnapshot.count
        guard cachedCount == 0 else { return cachedCount }

        return estimatedPickerItemCount()
    }

    private func estimatedPickerItemCount() -> Int {
        let browserIDs = Set(appState.browsers.map(\.id))

        guard let pendingURL = appState.pendingURL else {
            let runningBundleIDs = appState.cachedRunningBundleIDs
                ?? Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let windowsByAppID = appState.cachedWindowsByAppID ?? [:]
            let runningBrowsers = PickerItem.matchingBrowsers(for: nil, in: appState.pickerBrowsers)
                .filter { runningBundleIDs.contains($0.id) }
            let browserCount = runningBrowsers.reduce(0) { count, browser in
                count + max(1, windowsByAppID[browser.id]?.count ?? 0)
            }
            let appCount = appState.apps.reduce(0) { count, app in
                app.isVisible && runningBundleIDs.contains(app.id) && !browserIDs.contains(app.id)
                    ? count + max(1, windowsByAppID[app.id]?.count ?? 0)
                    : count
            }
            return browserCount + appCount
        }

        let browserCount = pickerBrowserItemCount(
            PickerItem.matchingBrowsers(for: pendingURL, in: appState.pickerBrowsers)
        )
        let appCount = PickerItem.matchingApps(
            for: pendingURL,
            in: appState.apps,
            excludingBundleIDs: browserIDs,
            includingLaunchServicesCandidates: false
        ).count
        return browserCount + appCount
    }

    /// Rebuild the switcher snapshot after a live window-cache refresh landed while the picker
    /// is on screen. Skips churn when the visible list is unchanged; otherwise keeps the user's
    /// focused tile by remapping the focus index by item id, then re-fits the panel.
    func refreshSnapshotForVisibleSession() {
        guard appState.isPickerVisible,
              appState.pickerInvocationSource.refreshesLiveSnapshot,
              !isClosing
        else { return }

        let oldItems = appState.pickerItemsSnapshot
        let oldIndex = appState.focusedBrowserIndex
        appState.pickerItemsSnapshot = []
        refreshPickerItemsSnapshot()
        let newItems = appState.pickerItemsSnapshot

        guard !newItems.isEmpty else {
            appState.pickerItemsSnapshot = oldItems
            return
        }
        guard newItems.map(\.id) != oldItems.map(\.id) else { return }

        appState.focusedBrowserIndex = Self.remappedFocusIndex(
            oldItems: oldItems,
            newItems: newItems,
            oldIndex: oldIndex
        )
        if let panel {
            let screen = screenNearCursor()
            resizePanelIfNeeded(panel, to: panelSize(for: screen))
            positionPanel(panel, on: screen)
        }
        Log.picker.debug("Picker snapshot refreshed in place (\(oldItems.count) → \(newItems.count) items)")
    }

    func moveFocusForVisibleSession(delta: Int) {
        guard appState.isPickerVisible else { return }
        clearTypeAheadBuffer()
        moveFocusWrapping(delta, itemCount: itemCountForFocusNavigation())
    }

    func openFocusedItemForVisibleSession() {
        guard appState.isPickerVisible else { return }
        let items = pickerItemsForCurrentSession()
        guard items.indices.contains(appState.focusedBrowserIndex) else { return }
        open(items[appState.focusedBrowserIndex], source: .pickerHotkey)
    }

    private func openItemForGlobalMouseDown(at screenLocation: NSPoint, eventType: NSEvent.EventType) -> Bool {
        guard eventType == .leftMouseDown,
              appState.isPickerVisible,
              PickerPanelInteractionPolicy.acceptsGlobalClickFallback(
                  for: appState.pickerInvocationSource
              ),
              let panel
        else {
            return false
        }

        let items = pickerItemsForCurrentSession()
        guard let index = Self.itemIndexForManualPickerClick(
            at: screenLocation,
            panelFrame: panel.frame,
            itemCount: items.count,
            scrollOffsetX: pickerScrollOffsetX(in: panel),
            scale: pickerScale
        ) else {
            return false
        }

        appState.focusedBrowserIndex = index
        open(items[index], source: .pickerClick)
        return true
    }

    /// Where focus should land after the item list is replaced: follow the focused item's id,
    /// fall back to the same position clamped into bounds.
    static func remappedFocusIndex(oldItems: [PickerItem], newItems: [PickerItem], oldIndex: Int) -> Int {
        guard !newItems.isEmpty else { return 0 }
        guard oldItems.indices.contains(oldIndex) else { return 0 }
        let focusedID = oldItems[oldIndex].id
        return newItems.firstIndex { $0.id == focusedID } ?? min(oldIndex, newItems.count - 1)
    }

    static func shouldDismissForGlobalMouseDown(at screenLocation: NSPoint, panelFrame: NSRect?) -> Bool {
        guard let panelFrame else { return true }
        return !panelFrame.contains(screenLocation)
    }

    static func itemIndexForManualPickerClick(
        at screenLocation: NSPoint,
        panelFrame: NSRect?,
        itemCount: Int,
        scrollOffsetX: CGFloat,
        scale: CGFloat
    ) -> Int? {
        guard itemCount > 0,
              let panelFrame,
              panelFrame.contains(screenLocation)
        else {
            return nil
        }

        let scale = PickerMetrics.clampedScale(scale)
        let localX = screenLocation.x - panelFrame.minX
        let localY = screenLocation.y - panelFrame.minY
        let verticalPadding = PickerMetrics.verticalPadding(scale: scale)
        guard localY >= verticalPadding,
              localY <= verticalPadding + PickerMetrics.itemHeight(scale: scale)
        else {
            return nil
        }

        let itemWidth = PickerMetrics.itemWidth(scale: scale)
        let stride = itemWidth + PickerMetrics.itemSpacing(scale: scale)
        let contentX = localX + scrollOffsetX - PickerMetrics.horizontalPadding(scale: scale)
        guard contentX >= 0 else { return nil }

        let rawIndex = Int(floor(contentX / stride))
        guard rawIndex >= 0, rawIndex < itemCount else { return nil }
        let xWithinSlot = contentX - CGFloat(rawIndex) * stride
        guard xWithinSlot <= itemWidth else { return nil }
        return rawIndex
    }

    private func seedPickerSnapshotIfPossible() {
        guard appState.pickerItemsSnapshot.isEmpty else { return }
        // For the no-URL apps/windows picker we need the running-apps cache to be warm, otherwise
        // refreshPickerItemsSnapshot would trigger a synchronous NSWorkspace + AX window
        // enumeration on the present frame. For the URL case there is no such dependency, so seed
        // eagerly here (before makeKeyAndOrderFront) so the very first body pass renders from a
        // ready snapshot instead of recomputing — and any file-URL LaunchServices lookup happens
        // once, here, rather than repeatedly during body evaluation.
        if appState.pendingURL == nil, appState.cachedRunningBundleIDs == nil { return }
        refreshPickerItemsSnapshot()
    }

    private func pickerBrowserItemCount(_ browsers: [InstalledBrowser]) -> Int {
        browsers.reduce(0) { count, browser in
            let visibleProfiles = browser.profiles.filter(\.isVisible)
            if visibleProfiles.isEmpty, browser.isVisible {
                return count + 1
            }
            return count + visibleProfiles.count
        }
    }

    private func moveFocus(_ delta: Int, itemCount: Int) {
        let newIndex = appState.focusedBrowserIndex + delta
        if newIndex >= 0, newIndex < itemCount {
            appState.focusedBrowserIndex = newIndex
        }
    }

    private func moveFocusWrapping(_ delta: Int, itemCount: Int) {
        guard itemCount > 0 else { return }
        let newIndex = (appState.focusedBrowserIndex + delta + itemCount) % itemCount
        appState.focusedBrowserIndex = newIndex
    }

    // MARK: - Panel

    private func panelSize(for screen: NSScreen) -> NSSize {
        panelSurfaceSize(for: screen)
    }

    private func panelSurfaceSize(for screen: NSScreen) -> NSSize {
        let scale = pickerScale
        let itemCount = itemCountForPanelSizing()
        let showsFileEmptyState = PickerEmptyStatePolicy.action(
            for: appState.pendingURL,
            itemCount: itemCount,
            invocationSource: appState.pickerInvocationSource
        ) == .configureApps
        return NSSize(
            width: PickerMetrics.panelWidth(
                itemCount: itemCount,
                availableWidth: screen.visibleFrame.width,
                showsFileEmptyState: showsFileEmptyState,
                scale: scale
            ),
            height: PickerMetrics.panelHeight(
                showsIncognitoHint: appState.showsPickerIncognitoHint,
                scale: scale
            )
        )
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: PickerPanelInteractionPolicy.styleMask,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        PickerPanelInteractionPolicy.apply(to: panel)

        let surfaceView = makePanelSurfaceView(frame: panelSurfaceFrame(in: NSRect(origin: .zero, size: size)))
        panel.contentView = surfaceView

        panel.delegate = self

        return panel
    }

    private func makePanelSurfaceView(frame: NSRect) -> NSView {
        if #available(macOS 26.0, *) {
            return makeGlassSurfaceView(frame: frame)
        }

        let surfaceView = NSView(frame: frame)
        surfaceView.identifier = PickerPanelViewID.surface
        surfaceView.wantsLayer = true
        applyPanelSurfaceAppearance(to: surfaceView)

        let visualEffect = NSVisualEffectView(frame: surfaceView.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.wantsLayer = true
        applyVisualEffectFallbackAppearance(to: visualEffect)
        surfaceView.addSubview(visualEffect)
        return surfaceView
    }

    @available(macOS 26.0, *)
    private func makeGlassSurfaceView(frame: NSRect) -> NSGlassEffectContainerView {
        let container = NSGlassEffectContainerView(frame: frame)
        container.identifier = PickerPanelViewID.surface
        container.spacing = 0

        let glassView = NSGlassEffectView(frame: container.bounds)
        glassView.identifier = PickerPanelViewID.glass
        glassView.autoresizingMask = [.width, .height]
        container.contentView = glassView

        applyPanelSurfaceAppearance(to: container)
        return container
    }

    private func applyPanelSurfaceAppearance(to surfaceView: NSView) {
        let radius = PickerMetrics.panelCornerRadius(scale: pickerScale)
        if #available(macOS 26.0, *) {
            if let glassContainer = surfaceView as? NSGlassEffectContainerView {
                glassContainer.spacing = 0
            }
            if let glassView = glassEffectView(in: surfaceView) {
                glassView.style = .regular
                glassView.cornerRadius = radius
                glassView.tintColor = PickerSurfaceAppearance.adaptiveTint(for: glassView.effectiveAppearance)
            }
            return
        }

        surfaceView.wantsLayer = true
        surfaceView.layer?.cornerRadius = radius
        surfaceView.layer?.cornerCurve = .continuous
        surfaceView.layer?.masksToBounds = true
        surfaceView.layer?.backgroundColor = NSColor.clear.cgColor
        surfaceView.layer?.isOpaque = false
        surfaceView.layer?.borderWidth = 0
        surfaceView.layer?.borderColor = nil
    }

    private func applyVisualEffectFallbackAppearance(to visualEffect: NSVisualEffectView) {
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.layer?.cornerRadius = PickerMetrics.panelCornerRadius(scale: pickerScale)
        visualEffect.layer?.cornerCurve = .continuous
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 0
        visualEffect.layer?.borderColor = nil
        visualEffect.layer?.backgroundColor = PickerSurfaceAppearance.adaptiveTint(
            for: visualEffect.effectiveAppearance
        ).cgColor
    }

    private func refreshPanelAppearance() {
        guard let panel else { return }
        if let surfaceView = surfaceView(in: panel) {
            applyPanelSurfaceAppearance(to: surfaceView)
        }
        if let visualEffect = materialView(in: panel) {
            applyVisualEffectFallbackAppearance(to: visualEffect)
        }
    }

    private func materialView(in panel: NSPanel) -> NSVisualEffectView? {
        panel.contentView.flatMap { firstDescendant(of: NSVisualEffectView.self, in: $0) }
    }

    private func surfaceView(in panel: NSPanel) -> NSView? {
        panel.contentView.flatMap { firstDescendant(in: $0, matching: { $0.identifier == PickerPanelViewID.surface }) }
    }

    private func hostingView(in panel: NSPanel) -> NSView? {
        panel.contentView.flatMap { firstDescendant(in: $0, matching: { $0.identifier == PickerPanelViewID.hosting }) }
    }

    private func pickerScrollOffsetX(in panel: NSPanel) -> CGFloat {
        guard let contentView = panel.contentView,
              let scrollView = firstDescendant(of: NSScrollView.self, in: contentView)
        else {
            return 0
        }

        return scrollView.contentView.bounds.minX
    }

    private func pickerContentContainer(in panel: NSPanel) -> NSView? {
        if #available(macOS 26.0, *), let glassView = glassEffectView(in: panel) {
            return glassView.contentView ?? glassView
        }
        guard let surfaceView = surfaceView(in: panel) else { return panel.contentView }
        return surfaceView
    }

    private func installHostingView(_ hostingView: NSView, in panel: NSPanel, fallbackContainer: NSView) {
        if #available(macOS 26.0, *), let glassView = glassEffectView(in: panel) {
            hostingView.frame = glassView.bounds
            glassView.contentView = hostingView
            return
        }
        fallbackContainer.addSubview(hostingView)
    }

    @available(macOS 26.0, *)
    private func glassEffectView(in panel: NSPanel) -> NSGlassEffectView? {
        panel.contentView.flatMap { glassEffectView(in: $0) }
    }

    @available(macOS 26.0, *)
    private func glassEffectView(in root: NSView) -> NSGlassEffectView? {
        firstDescendant(of: NSGlassEffectView.self, in: root)
    }

    private var pickerScale: CGFloat {
        PickerMetrics.clampedScale(CGFloat(appState.pickerScale))
    }

    private func panelSurfaceFrame(in bounds: NSRect) -> NSRect {
        bounds
    }

    private func firstDescendant<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        firstDescendant(in: root, matching: { $0 is T }) as? T
    }

    private func firstDescendant(in root: NSView, matching matches: (NSView) -> Bool) -> NSView? {
        if matches(root) { return root }
        for subview in root.subviews {
            if matches(subview) { return subview }
            if let nested = firstDescendant(in: subview, matching: matches) {
                return nested
            }
        }
        return nil
    }

    private func resizePanelIfNeeded(_ panel: NSPanel, to targetSize: NSSize) {
        if panel.frame.size != targetSize {
            panel.setContentSize(targetSize)
        }
        if let contentView = panel.contentView {
            contentView.frame = NSRect(origin: .zero, size: targetSize)
            if let surfaceView = surfaceView(in: panel) {
                applyPanelSurfaceAppearance(to: surfaceView)
                layoutPanelSurfaceContent(surfaceView)
            }
            if let visualEffect = materialView(in: panel) {
                applyVisualEffectFallbackAppearance(to: visualEffect)
            }
        }
    }

    private func layoutPanelSurfaceContent(_ surfaceView: NSView) {
        if #available(macOS 26.0, *), let glassView = glassEffectView(in: surfaceView) {
            glassView.frame = surfaceView.bounds
            glassView.contentView?.frame = glassView.bounds
            return
        }

        for subview in surfaceView.subviews {
            subview.frame = surfaceView.bounds
        }
    }

    private func screenNearCursor() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func positionPanel(_ panel: NSPanel, on screen: NSScreen) {
        if appState.isManualPickerPresentation {
            panel.setFrameOrigin(PickerPanelPositioning.centeredOrigin(
                panelSize: panel.frame.size,
                visibleFrame: screen.visibleFrame
            ))
            return
        }

        positionNearCursor(panel, on: screen)
    }

    private func positionNearCursor(_ panel: NSPanel, on screen: NSScreen) {
        panel.setFrameOrigin(PickerPanelPositioning.nearCursorOrigin(
            mouseLocation: NSEvent.mouseLocation,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame,
            scale: pickerScale
        ))
    }

    private func itemCountForPanelSizing() -> Int {
        let snapshotCount = appState.pickerItemsSnapshot.count
        return snapshotCount == 0 ? estimatedPickerItemCount() : snapshotCount
    }
}

// MARK: - NSWindowDelegate

extension PickerWindowController: NSWindowDelegate {
    nonisolated func windowDidBecomeKey(_: Notification) {
        Task { @MainActor [weak self] in
            self?.refreshPanelAppearance()
        }
    }

    nonisolated func windowDidBecomeMain(_: Notification) {
        Task { @MainActor [weak self] in
            self?.refreshPanelAppearance()
        }
    }

    nonisolated func windowDidResignKey(_: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshPanelAppearance()
            guard !self.isClosing,
                  self.appState.isPickerVisible,
                  self.panel?.isVisible == true
            else { return }

            switch PickerPanelInteractionPolicy.keyResignAction(
                for: self.appState.pickerInvocationSource,
                isInDismissGracePeriod: self.isInDismissGracePeriod
            ) {
            case .refocus:
                if let panel = self.panel {
                    panel.orderFrontRegardless()
                    self.focusPanel(panel)
                }
            case .remainVisible:
                self.panel?.orderFrontRegardless()
            case .dismiss:
                self.close()
            }
        }
    }
}
