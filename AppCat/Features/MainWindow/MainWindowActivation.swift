import AppKit

@MainActor
enum MainWindowActivation {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("ua.com.rmarinsky.appcat.main-window")

    static func requestOpen() {
        prepareForMainWindow()
        NotificationCenter.default.post(name: .openMainWindow, object: nil)
        focusAfterWindowOpen()
    }

    static func prepareForMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Restoring `.regular` while Settings belongs to another Space makes macOS jump back to
    /// that Space. Only restore it immediately when Settings is actually visible where the user
    /// is; `applicationDidBecomeActive` restores it after the user returns to Settings later.
    static var isMainWindowVisibleOnActiveSpace: Bool {
        guard let window = mainWindow, window.isVisible else { return false }
        return window.occlusionState.contains(.visible)
    }

    static func configure(_ window: NSWindow) {
        window.identifier = windowIdentifier
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.toolbar = nil
        hideSidebarToggleButton(in: window)
        DispatchQueue.main.async { [weak window] in
            window?.toolbar = nil
            if let window {
                hideSidebarToggleButton(in: window)
            }
        }
    }

    private static func hideSidebarToggleButton(in window: NSWindow) {
        guard let button = window.standardWindowButton(.toolbarButton) else { return }
        button.isHidden = true
        button.isEnabled = false
    }

    static func focusAfterWindowOpen() {
        focusMainWindowIfAvailable()
        scheduleFocus()
        scheduleFocus(after: 0.12)
    }

    static func focusMainWindowIfAvailable() {
        prepareForMainWindow()

        guard let window = mainWindow else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier == windowIdentifier }
            ?? NSApp.windows.first { $0.title == "AppCat" }
    }

    private static func scheduleFocus(after delay: TimeInterval = 0) {
        Task { @MainActor in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            focusMainWindowIfAvailable()
        }
    }
}

extension Notification.Name {
    /// Posted by app lifecycle/menu commands to ask SwiftUI to open the main window.
    static let openMainWindow = Notification.Name("ua.com.rmarinsky.appcat.openMainWindow")
}
