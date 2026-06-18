import AppKit
import KeyboardShortcuts
import os
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let browserManager = BrowserManager()
    let appManager = AppManager()
    let urlRulesManager = URLRulesManager()
    let defaultBrowserManager = DefaultBrowserManager()
    let pickerCoordinator = PickerCoordinator()
    let historyManager = HistoryManager()
    let suggestionsManager = SuggestionsManager()
    let statsManager = StatsManager()
    lazy var updaterManager = UpdaterManager()
    lazy var appActivityMonitor = AppActivityMonitor(appState: appState)
    private var mainWindowController: MainWindowController?
    private var openMainWindowObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        openMainWindowObserver = NotificationCenter.default.addObserver(
            forName: .openMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openMainWindow()
            }
        }

        browserManager.refreshBrowsers(into: appState)
        appManager.refreshApps(into: appState)
        urlRulesManager.load(into: appState)
        defaultBrowserManager.checkIsDefault(state: appState)
        historyManager.load(into: appState)
        statsManager.load()
        statsManager.backfillIfNeeded(history: appState.history, rules: appState.urlRules)
        appActivityMonitor.start()
        pickerCoordinator.historyManager = historyManager
        pickerCoordinator.suggestionsManager = suggestionsManager
        pickerCoordinator.statsManager = statsManager
        suggestionsManager.loadCached(into: appState)
        suggestionsManager.analyseIfNeeded(state: appState)
        _ = updaterManager

        KeyboardShortcuts.onKeyUp(for: .openPickerManually) { [weak self] in
            self?.openPickerManually()
        }
        KeyboardShortcuts.onKeyUp(for: .reopenLastPicker) { [weak self] in
            guard let self, let last = self.appState.lastOpenedURL else { return }
            self.pickerCoordinator.reopenURL(last, state: self.appState)
        }

        Log.app.info("AppCat launched")

        // Delay slightly so URL/file launch events can populate pending state first.
        scheduleMainWindowOpen(section: .overview, delay: 0.35)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard appState.pendingURL == nil, !appState.isPickerVisible else {
            MainWindowActivation.prepareForMainWindow()
            return true
        }

        openMainWindow()
        return true
    }

    func applicationDidBecomeActive(_: Notification) {
        scheduleMainWindowOpen(delay: 0.12)
    }

    func applicationWillTerminate(_: Notification) {
        if let openMainWindowObserver {
            NotificationCenter.default.removeObserver(openMainWindowObserver)
        }
        appActivityMonitor.stop()
    }

    func openMainWindow() {
        if mainWindowController == nil {
            Log.app.info("Creating main window controller")
            mainWindowController = MainWindowController(
                appState: appState,
                browserManager: browserManager,
                appManager: appManager,
                urlRulesManager: urlRulesManager,
                defaultBrowserManager: defaultBrowserManager,
                pickerCoordinator: pickerCoordinator,
                historyManager: historyManager,
                suggestionsManager: suggestionsManager,
                statsManager: statsManager
            )
        }

        Log.app.info("Opening main window")
        mainWindowController?.show()
    }

    private func scheduleMainWindowOpen(section: MainWindowSection? = nil, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard self.appState.pendingURL == nil, !self.appState.isPickerVisible else {
                Log.app.info(
                    "Skipping scheduled main window open: pendingURL=\(self.appState.pendingURL?.absoluteString ?? "nil", privacy: .public), pickerVisible=\(self.appState.isPickerVisible, privacy: .public)"
                )
                return
            }
            guard self.mainWindowController?.window?.isVisible != true else {
                Log.app.info("Scheduled main window open focused existing window")
                MainWindowActivation.focusMainWindowIfAvailable()
                return
            }
            if let section {
                self.appState.mainWindowSection = section
            }
            Log.app.info("Scheduled main window open will create/show window")
            self.openMainWindow()
        }
    }

    // MARK: - Global Shortcuts

    /// ⌥⌘B: show the manual app/window switcher.
    private func openPickerManually() {
        if appState.isPickerVisible {
            pickerCoordinator.dismissPicker(state: appState)
            return
        }

        appActivityMonitor.refreshRunningApplications()
        appActivityMonitor.refreshWindowSnapshotForPicker()
        appManager.refreshApps(into: appState)
        appState.clearPendingOpen()
        appState.isManualPickerPresentation = true
        pickerCoordinator.showPicker(state: appState)
    }

    // MARK: - URL Handling

    func application(_: NSApplication, open urls: [URL]) {
        handleIncomingURLs(urls)
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let rawURL = URL(string: urlString)
        else {
            Log.app.error("Received invalid URL event")
            return
        }

        handleIncomingURLs([rawURL])
    }

    private func handleIncomingURLs(_ rawURLs: [URL]) {
        let incomingURLs = rawURLs.map(normalizeIncomingURL)
        let displayURLs = incomingURLs.map(\.displayURL)
        let launchURLs = incomingURLs.map(\.launchURL)
        guard let url = displayURLs.first else { return }

        appState.isManualPickerPresentation = false
        appState.setPendingOpen(displayURLs: displayURLs, launchURLs: launchURLs)
        fetchTitle(for: url)

        if rawURLs.count > 1 {
            Log.app.info("Received \(rawURLs.count) URL(s); primary: \(url.absoluteString)")
        } else {
            Log.app.info("Received URL: \(url.absoluteString)")
        }

        // Check URL rules before showing picker. Multi-file opens use the first file/URL
        // as the routing signal, then launch the full batch in the chosen browser.
        if let match = urlRulesManager.findMatch(
            for: url,
            browsers: appState.browsers,
            apps: appState.apps,
            rules: appState.urlRules
        ) {
            let source = OpenSource.autoRoute(ruleID: match.ruleID)
            switch match {
            case let .browser(browser, profile, _):
                pickerCoordinator.openURL(with: browser, profile: profile, state: appState, source: source)
                return
            case let .app(app, _):
                pickerCoordinator.openURL(with: app, state: appState, source: source)
                return
            }
        }

        pickerCoordinator.showPicker(state: appState)
    }

    private func normalizeIncomingURL(_ rawURL: URL) -> (displayURL: URL, launchURL: URL) {
        let shortcutURL = FileShortcutResolver.resolve(rawURL)
        let displayURL = URLUnwrapper.unwrap(shortcutURL)
        let launchURL = shortcutURL == rawURL ? rawURL : shortcutURL

        if shortcutURL != rawURL {
            Log.app.info("Resolved shortcut: \(rawURL.absoluteString) → \(shortcutURL.absoluteString)")
        }

        if displayURL != shortcutURL {
            Log.app.info("Unwrapped URL: \(shortcutURL.absoluteString) → \(displayURL.absoluteString)")
        }

        return (displayURL, launchURL)
    }

    // MARK: - Title Fetching

    private func fetchTitle(for url: URL) {
        Task {
            let metadata = await LinkMetadataManager.shared.metadata(for: url)
            guard let title = metadata.title else { return }
            if self.appState.pendingURL == url {
                self.appState.pendingURLTitle = title
            }
        }
    }
}
