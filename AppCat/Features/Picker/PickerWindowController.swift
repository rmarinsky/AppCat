import AppKit
import SwiftUI

private enum PickerPanelViewID {
    static let surface = NSUserInterfaceItemIdentifier("PickerPanelSurface")
    static let glass = NSUserInterfaceItemIdentifier("PickerPanelGlass")
    static let hosting = NSUserInterfaceItemIdentifier("PickerPanelHosting")
}

/// Borderless NSPanel returns false for canBecomeKey by default,
/// which prevents keyboard and mouse input. Override to allow it.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

enum PickerPanelPositioning {
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
        // A pre-warmed or reused panel may carry stale layer state, so re-apply on every show.
        if let surfaceView = surfaceView(in: panel) {
            applyPanelSurfaceAppearance(to: surfaceView)
        }
        if let visualEffect = materialView(in: panel) {
            applyVisualEffectFallbackAppearance(to: visualEffect)
        }

        positionPanel(panel, on: screen)
        ignoreDismissUntil = Date().addingTimeInterval(dismissGraceInterval)

        // Activate the app so macOS delivers key/mouse events to the panel. Demote to
        // .accessory (no Dock icon) only when the main window isn't on screen — otherwise a
        // link click while Settings is open would strip the app's Dock presence.
        if !MainWindowActivation.isMainWindowVisible {
            NSApp.setActivationPolicy(.accessory)
        }

        if shouldActivateAppForCurrentPresentation {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(hostingView(in: panel))
        } else {
            panel.orderFrontRegardless()
        }

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

    private var shouldActivateAppForCurrentPresentation: Bool {
        !(appState.isManualPickerPresentation && appState.pickerActivationMode == .holdOptionTab)
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
               let item = PickerShortcutPolicy.item(
                   forKeyCode: pressedKeyCode,
                   in: items,
                   activationMode: appState.pickerActivationMode,
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
        guard appState.pickerActivationMode == .toggleShortcut else { return false }
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

    private func panelSize(for screen: NSScreen) -> NSSize {
        panelSurfaceSize(for: screen)
    }

    private func panelSurfaceSize(for screen: NSScreen) -> NSSize {
        let scale = pickerScale
        return NSSize(
            width: PickerMetrics.panelWidth(
                itemCount: itemCountForPanelSizing(),
                availableWidth: screen.visibleFrame.width,
                scale: scale
            ),
            height: PickerMetrics.panelHeight(scale: scale)
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
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

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
                glassView.tintColor = nil
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
        visualEffect.layer?.backgroundColor = NSColor.clear.cgColor
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
            guard !self.isInDismissGracePeriod else {
                self.panel?.makeKeyAndOrderFront(nil)
                return
            }
            self.close()
        }
    }
}
