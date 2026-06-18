import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    init(
        appState: AppState,
        browserManager: BrowserManager,
        appManager: AppManager,
        urlRulesManager: URLRulesManager,
        defaultBrowserManager: DefaultBrowserManager,
        pickerCoordinator: PickerCoordinator,
        historyManager: HistoryManager,
        suggestionsManager: SuggestionsManager,
        statsManager: StatsManager
    ) {
        let rootView = MainWindowView()
            .environment(appState)
            .environment(\.browserManager, browserManager)
            .environment(\.appManager, appManager)
            .environment(\.urlRulesManager, urlRulesManager)
            .environment(\.defaultBrowserManager, defaultBrowserManager)
            .environment(\.pickerCoordinator, pickerCoordinator)
            .environment(\.historyManager, historyManager)
            .environment(\.suggestionsManager, suggestionsManager)
            .environment(\.statsManager, statsManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AppCat"
        window.contentView = NSHostingView(rootView: rootView)
        window.minSize = NSSize(width: 900, height: 620)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AppCatMainWindow")

        if !window.setFrameUsingName("AppCatMainWindow") {
            window.center()
        }

        if let surface = NSColor(named: "SurfaceWindow") {
            window.backgroundColor = surface
        }

        var behavior = window.collectionBehavior
        behavior.insert(.moveToActiveSpace)
        behavior.insert(.fullScreenPrimary)
        window.collectionBehavior = behavior

        MainWindowActivation.configure(window)

        super.init(window: window)
        window.delegate = self
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        Log.app.info("Main window show requested: visibleBefore=\(window.isVisible, privacy: .public)")
        MainWindowActivation.prepareForMainWindow()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        MainWindowActivation.focusAfterWindowOpen()
        Log.app.info("Main window show completed: visibleAfter=\(window.isVisible, privacy: .public)")
    }

    func windowWillClose(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
