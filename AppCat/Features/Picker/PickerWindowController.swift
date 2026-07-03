import AppKit
import SwiftUI

/// Borderless NSPanel returns false for canBecomeKey by default,
/// which prevents keyboard and mouse input. Override to allow it.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool {
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

        let hostingView = NSHostingView(
            rootView: PickerView()
                .environment(appState)
                .environment(\.pickerCoordinator, coordinator)
        )
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = newPanel.contentView!.bounds
        // Keep hosting view background transparent so vibrancy shows through
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        newPanel.contentView?.addSubview(hostingView)
    }

    func show() {
        isClosing = false
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
        resizePanelIfNeeded(panel, to: targetSize)
        // Material/corner radius differ between routing and app-switcher styles; a pre-warmed or
        // reused panel may carry the other style's look, so re-apply on every show.
        if let visualEffect = panel.contentView as? NSVisualEffectView {
            applyLiquidGlassAppearance(to: visualEffect)
        }

        positionPanel(panel, on: screen)
        ignoreDismissUntil = Date().addingTimeInterval(dismissGraceInterval)

        // Activate the app so macOS delivers key/mouse events to the panel. Demote to
        // .accessory (no Dock icon) only when the main window isn't on screen — otherwise a
        // link click while Settings is open would strip the app's Dock presence.
        if !MainWindowActivation.isMainWindowVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        NSApp.activate(ignoringOtherApps: true)

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView?.subviews.first)

        installMonitors()

        Log.picker.debug("Picker shown")
    }

    func close() {
        isClosing = true
        ignoreDismissUntil = .distantPast
        clearTypeAheadBuffer()
        appState.isPickerVisible = false
        appState.clearPendingOpen()
        appState.isManualPickerPresentation = false
        appState.pickerItemsSnapshot = []
        removeMonitors()
        panel?.orderOut(nil)
        if !MainWindowActivation.isMainWindowVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        DispatchQueue.main.async { [weak self] in
            self?.isClosing = false
        }
        Log.picker.debug("Picker dismissed")
    }

    // MARK: - Monitors

    private func installMonitors() {
        removeMonitors()

        // Dismiss on click outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.isInDismissGracePeriod else { return }
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

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard !isClosing, appState.isPickerVisible else { return false }

        switch Int(event.keyCode) {
        case 53: // Escape
            clearTypeAheadBuffer()
            coordinator.dismissPicker(state: appState)
            return true
        case 36: // Return
            let items = pickerItemsForCurrentSession()
            if items.indices.contains(appState.focusedBrowserIndex) {
                open(items[appState.focusedBrowserIndex])
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
            let isPrivate = event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift)
            let mode: BrowserLauncher.OpenMode = isPrivate ? .privateMode : .normal

            if canHandlePickerShortcut(event),
               let item = PickerShortcutAssigner.item(
                   forKeyCode: pressedKeyCode,
                   in: items,
                   positionalEnabled: appState.selectWithNumberKeys
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
            showWindowlessApps: appState.showWindowlessApps,
            showBackgroundApps: appState.showBackgroundApps
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
        guard appState.isPickerVisible, appState.isManualPickerPresentation, !isClosing else { return }

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

    /// Where focus should land after the item list is replaced: follow the focused item's id,
    /// fall back to the same position clamped into bounds.
    static func remappedFocusIndex(oldItems: [PickerItem], newItems: [PickerItem], oldIndex: Int) -> Int {
        guard !newItems.isEmpty else { return 0 }
        guard oldItems.indices.contains(oldIndex) else { return 0 }
        let focusedID = oldItems[oldIndex].id
        return newItems.firstIndex { $0.id == focusedID } ?? min(oldIndex, newItems.count - 1)
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

    private var presentationStyle: PickerPresentationStyle {
        appState.isManualPickerPresentation ? .appSwitcher : .routing
    }

    private func panelSize(for screen: NSScreen) -> NSSize {
        let style = presentationStyle
        let showsHint = appState.pendingURL != nil && appState.pendingURL?.isFileURL != true
        return NSSize(
            width: PickerMetrics.panelWidth(
                itemCount: itemCountForPanelSizing(),
                availableWidth: screen.visibleFrame.width,
                style: style
            ),
            height: PickerMetrics.panelHeight(showsHint: showsHint, style: style)
        )
    }

    private func makePanel(size: NSSize) -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        visualEffect.wantsLayer = true
        applyLiquidGlassAppearance(to: visualEffect)
        panel.contentView = visualEffect

        panel.delegate = self

        return panel
    }

    private func applyLiquidGlassAppearance(to visualEffect: NSVisualEffectView) {
        let style = presentationStyle
        visualEffect.material = style == .appSwitcher ? .hudWindow : .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.layer?.cornerRadius = PickerMetrics.panelCornerRadius(for: style)
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = style == .appSwitcher ? 0.75 : 0.5
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(style == .appSwitcher ? 0.22 : 0.14).cgColor
        visualEffect.layer?.backgroundColor = NSColor.black.withAlphaComponent(style == .appSwitcher ? 0.10 : 0.06).cgColor
    }

    private func resizePanelIfNeeded(_ panel: NSPanel, to targetSize: NSSize) {
        guard panel.frame.size != targetSize else { return }

        panel.setContentSize(targetSize)
        if let contentView = panel.contentView {
            contentView.frame = NSRect(origin: .zero, size: targetSize)
            if let visualEffect = contentView as? NSVisualEffectView {
                applyLiquidGlassAppearance(to: visualEffect)
            }
            for subview in contentView.subviews {
                subview.frame = contentView.bounds
            }
        }
    }

    private func screenNearCursor() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func positionPanel(_ panel: NSPanel, on screen: NSScreen) {
        if presentationStyle == .appSwitcher {
            panel.setFrameOrigin(PickerPanelPositioning.centeredOrigin(
                panelSize: panel.frame.size,
                visibleFrame: screen.visibleFrame
            ))
            return
        }

        positionNearCursor(panel, on: screen)
    }

    private func positionNearCursor(_ panel: NSPanel, on screen: NSScreen) {
        let mouseLocation = NSEvent.mouseLocation
        let panelSize = panel.frame.size
        let visibleFrame = screen.visibleFrame

        // Position centered on cursor, shifted up slightly
        var origin = NSPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y - panelSize.height / 2 + 40
        )

        // Clamp to screen edges
        origin.x = max(visibleFrame.minX + 8, min(origin.x, visibleFrame.maxX - panelSize.width - 8))
        origin.y = max(visibleFrame.minY + 8, min(origin.y, visibleFrame.maxY - panelSize.height - 8))

        panel.setFrameOrigin(origin)
    }

    private func itemCountForPanelSizing() -> Int {
        let snapshotCount = appState.pickerItemsSnapshot.count
        return snapshotCount == 0 ? estimatedPickerItemCount() : snapshotCount
    }
}

// MARK: - NSWindowDelegate

extension PickerWindowController: NSWindowDelegate {
    nonisolated func windowDidResignKey(_: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !self.isClosing,
                  self.appState.isPickerVisible,
                  self.panel?.isVisible == true
            else { return }
            guard !self.isInDismissGracePeriod else {
                self.panel?.makeKeyAndOrderFront(nil)
                return
            }
            self.close()
        }
    }
}
