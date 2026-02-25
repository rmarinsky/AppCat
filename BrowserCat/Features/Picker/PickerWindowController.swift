import AppKit
import SwiftUI

// Borderless NSPanel returns false for canBecomeKey by default,
// which prevents keyboard and mouse input. Override to allow it.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PickerWindowController: NSObject {
    private var panel: NSPanel?
    private let appState: AppState
    private let coordinator: PickerCoordinator
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    init(appState: AppState, coordinator: PickerCoordinator) {
        self.appState = appState
        self.coordinator = coordinator
    }

    func show() {
        if panel == nil {
            let newPanel = makePanel(size: panelSize(isCompact: appState.compactPickerView))
            self.panel = newPanel

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

        guard let panel else { return }
        resizePanelIfNeeded(panel)

        positionNearCursor(panel)

        // Activate the app so macOS delivers key/mouse events to the panel.
        // Use .accessory policy to avoid showing a dock icon.
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView?.subviews.first)

        installMonitors()

        Log.picker.debug("Picker shown")
    }

    func close() {
        removeMonitors()
        panel?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        appState.isPickerVisible = false
        appState.pendingURL = nil
        Log.picker.debug("Picker dismissed")
    }

    // MARK: - Monitors

    private func installMonitors() {
        removeMonitors()

        // Dismiss on click outside
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
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

    // MARK: - Key Handling

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let browsers = appState.pickerBrowsers
        let matchingApps = PickerItem.matchingApps(for: appState.pendingURL, in: appState.visibleApps)
        let prioritizedAppIDs = Set(matchingApps.map(\.id))
        let items = PickerItem.buildItems(
            browsers: browsers,
            apps: matchingApps,
            prioritizedAppIDs: prioritizedAppIDs
        )

        switch Int(event.keyCode) {
        case 53: // Escape
            coordinator.dismissPicker(state: appState)
            return true
        case 36: // Return
            if items.indices.contains(appState.focusedBrowserIndex) {
                let item = items[appState.focusedBrowserIndex]
                if let app = item.app {
                    coordinator.openURL(with: app, state: appState)
                } else if let browser = item.browser {
                    coordinator.openURL(with: browser, mode: .normal, profile: item.profile, state: appState)
                }
            }
            return true
        case 48: // Tab
            if event.modifierFlags.contains(.shift) {
                moveFocusWrapping(-1, itemCount: items.count)
            } else {
                moveFocusWrapping(1, itemCount: items.count)
            }
            return true
        case 123: // Left arrow
            moveFocus(-1, itemCount: items.count)
            return true
        case 124: // Right arrow
            moveFocus(1, itemCount: items.count)
            return true
        case 125: // Down arrow
            if appState.compactPickerView {
                moveFocus(1, itemCount: items.count)
            } else {
                moveFocus(columnsCount, itemCount: items.count)
            }
            return true
        case 126: // Up arrow
            if appState.compactPickerView {
                moveFocus(-1, itemCount: items.count)
            } else {
                moveFocus(-columnsCount, itemCount: items.count)
            }
            return true
        default:
            let pressedKeyCode = event.keyCode
            let keyChar = event.charactersIgnoringModifiers?.lowercased().first
            let isPrivate = event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift)
            let mode: BrowserLauncher.OpenMode = isPrivate ? .privateMode : .normal

            // Check app hotkeys first
            for app in matchingApps {
                if let code = app.hotkeyKeyCode, code == pressedKeyCode {
                    coordinator.openURL(with: app, state: appState)
                    return true
                }
                // Fallback: character match for configs saved before keyCode support
                if app.hotkeyKeyCode == nil, let hotkey = app.hotkey, let keyChar,
                   Character(String(hotkey).lowercased()) == keyChar
                {
                    coordinator.openURL(with: app, state: appState)
                    return true
                }
            }

            // Check profile hotkeys (more specific)
            for browser in browsers {
                if let profile = browser.profiles.first(where: { p in
                    guard p.isVisible else { return false }
                    if let code = p.hotkeyKeyCode { return code == pressedKeyCode }
                    guard let hotkey = p.hotkey, let keyChar else { return false }
                    return Character(String(hotkey).lowercased()) == keyChar
                }) {
                    coordinator.openURL(with: browser, mode: mode, profile: profile, state: appState)
                    return true
                }
            }

            // Then check browser hotkeys
            if let index = browsers.firstIndex(where: { browser in
                guard browser.isVisible else { return false }
                if let code = browser.hotkeyKeyCode { return code == pressedKeyCode }
                guard let hotkey = browser.hotkey, let keyChar else { return false }
                return Character(String(hotkey).lowercased()) == keyChar
            }) {
                coordinator.openURL(with: browsers[index], mode: mode, state: appState)
                return true
            }
            return false
        }
    }

    private var columnsCount: Int {
        max(1, Int(380 - 24) / 80)
    }

    private func moveFocus(_ delta: Int, itemCount: Int) {
        let newIndex = appState.focusedBrowserIndex + delta
        if newIndex >= 0 && newIndex < itemCount {
            appState.focusedBrowserIndex = newIndex
        }
    }

    private func moveFocusWrapping(_ delta: Int, itemCount: Int) {
        guard itemCount > 0 else { return }
        let newIndex = (appState.focusedBrowserIndex + delta + itemCount) % itemCount
        appState.focusedBrowserIndex = newIndex
    }

    // MARK: - Panel

    private func panelSize(isCompact: Bool) -> NSSize {
        let panelWidth: CGFloat = isCompact ? 600 : 380
        let panelHeight: CGFloat = isCompact ? 176 : 300
        return NSSize(width: panelWidth, height: panelHeight)
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
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        // Use NSVisualEffectView as the content view for proper vibrancy
        let visualEffect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        panel.contentView = visualEffect

        panel.delegate = self

        return panel
    }

    private func resizePanelIfNeeded(_ panel: NSPanel) {
        let targetSize = panelSize(isCompact: appState.compactPickerView)
        guard panel.frame.size != targetSize else { return }

        panel.setContentSize(targetSize)
        if let contentView = panel.contentView {
            contentView.frame = NSRect(origin: .zero, size: targetSize)
            for subview in contentView.subviews {
                subview.frame = contentView.bounds
            }
        }
    }

    private func positionNearCursor(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let panelSize = panel.frame.size

        // Find the screen that contains the mouse
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]

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
}

// MARK: - NSWindowDelegate

extension PickerWindowController: NSWindowDelegate {
    nonisolated func windowDidResignKey(_: Notification) {
        Task { @MainActor in
            close()
        }
    }
}
