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
    let pickerActivationListener = PickerActivationListener()
    private var mainWindowController: MainWindowController?
    private var openMainWindowObserver: NSObjectProtocol?
    private var pickerActivationSettingsObserver: NSObjectProtocol?
    /// Scheduled "open the main window" work. Stored so an incoming URL or a manual picker can
    /// cancel it outright instead of racing the fire-time guard.
    private var pendingMainWindowOpen: DispatchWorkItem?
    /// URLs can arrive before `applicationDidFinishLaunching` loads browsers/rules/apps (the
    /// launch kAEGetURL event is delivered right after `applicationWillFinishLaunching`). Buffer
    /// them until launch configuration is ready, then flush.
    private var isLaunchConfigured = false
    private var bufferedLaunchURLs: [URL] = []

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_: Notification) {
        // Register before launch completes so the URL that launched the app is delivered as an
        // event (ahead of didFinishLaunching) instead of racing the post-launch timers.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_: Notification) {
        openMainWindowObserver = NotificationCenter.default.addObserver(
            forName: .openMainWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.openMainWindow()
            }
        }
        pickerActivationSettingsObserver = NotificationCenter.default.addObserver(
            forName: .pickerActivationSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pickerActivationListener.refresh(settings: self.appState.pickerActivationSettings)
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
        // Rescan installed apps when running apps launch/terminate (debounced) — the switcher
        // hotkey no longer rescans, so this keeps the app list current in the background.
        appActivityMonitor.onAppListChanged = { [weak self] in
            guard let self else { return }
            self.appManager.refreshAppsInBackground(into: self.appState)
        }
        pickerCoordinator.historyManager = historyManager
        pickerCoordinator.suggestionsManager = suggestionsManager
        pickerCoordinator.statsManager = statsManager
        suggestionsManager.loadCached(into: appState)
        suggestionsManager.analyseIfNeeded(state: appState)
        _ = updaterManager

        GlobalShortcuts.migrateLegacyDefaultsIfNeeded()
        configurePickerActivationListener()

        KeyboardShortcuts.onKeyUp(for: .openPickerManually) { [weak self] in
            guard let self, self.appState.pickerActivationMode == .toggleShortcut else { return }
            self.openPickerManually()
        }
        KeyboardShortcuts.onKeyUp(for: .reopenLastPicker) { [weak self] in
            guard let self, let last = self.appState.lastOpenedURL else { return }
            self.pickerCoordinator.reopenURL(last, state: self.appState)
        }

        Log.app.info("AppCat launched")

        // Register the plain-launch fallback BEFORE flushing buffered URLs — order matters.
        // If the app was cold-launched to service a link/file, flushing routes it synchronously
        // and `handleIncomingURLs` cancels this scheduled open at its top. The auto-route path
        // clears `pendingURL` synchronously, so if we flushed first this fallback's fire-time
        // guard would later see clean state (pendingURL == nil, no picker) and still pop the
        // main window over the routed link.
        scheduleMainWindowOpen(section: .overview, delay: 0.35)

        // Launch configuration is ready — release any URLs that arrived during launch.
        isLaunchConfigured = true
        flushBufferedLaunchURLs()

        // Pre-build the picker panel + SwiftUI hierarchy so the first link click doesn't pay
        // view-graph construction. Deferred so it never competes with launch URL handling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.pickerCoordinator.prewarmPicker(state: self.appState)
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard appState.pendingURL == nil, !appState.isPickerVisible else {
            // A picker/routing session is active — don't promote to .regular or steal focus.
            return true
        }

        openMainWindow()
        return true
    }

    func applicationDidBecomeActive(_: Notification) {
        pickerActivationListener.refresh(settings: appState.pickerActivationSettings)
    }

    func applicationWillTerminate(_: Notification) {
        if let openMainWindowObserver {
            NotificationCenter.default.removeObserver(openMainWindowObserver)
        }
        if let pickerActivationSettingsObserver {
            NotificationCenter.default.removeObserver(pickerActivationSettingsObserver)
        }
        pickerActivationListener.stop()
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
                statsManager: statsManager,
                updaterManager: updaterManager
            )
        }

        Log.app.info("Opening main window")
        mainWindowController?.show()
    }

    private func scheduleMainWindowOpen(section: MainWindowSection? = nil, delay: TimeInterval) {
        cancelScheduledMainWindowOpen()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMainWindowOpen = nil
            // Second line of defense — the primary one is explicit cancellation on incoming URLs.
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
        pendingMainWindowOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelScheduledMainWindowOpen() {
        pendingMainWindowOpen?.cancel()
        pendingMainWindowOpen = nil
    }

    // MARK: - Global Shortcuts

    private func configurePickerActivationListener() {
        pickerActivationListener.onHoldStep = { [weak self] delta in
            self?.cycleManualPicker(delta: delta)
        }
        pickerActivationListener.onHoldRelease = { [weak self] in
            self?.openFocusedManualPickerItem()
        }
        pickerActivationListener.onServiceKeyTrigger = { [weak self] in
            self?.openPickerManually()
        }
        pickerActivationListener.refresh(settings: appState.pickerActivationSettings)
    }

    /// Show the manual app/window switcher.
    private func openPickerManually() {
        if appState.isPickerVisible {
            pickerCoordinator.dismissPicker(state: appState)
            return
        }

        presentManualPicker()
    }

    private func cycleManualPicker(delta: Int) {
        guard appState.pendingURL == nil else { return }
        if !appState.isPickerVisible {
            presentManualPicker()
        }
        guard appState.isManualPickerPresentation else { return }
        pickerCoordinator.moveFocus(delta: delta, state: appState)
    }

    private func openFocusedManualPickerItem() {
        guard appState.isPickerVisible, appState.isManualPickerPresentation else { return }
        pickerCoordinator.openFocusedItem(state: appState)
    }

    private func presentManualPicker() {
        cancelScheduledMainWindowOpen()
        appActivityMonitor.refreshRunningApplications()
        if appState.cachedWindowsByAppID == nil {
            // Cold cache (no background pass has landed yet) — enumerate once synchronously so
            // the very first switcher isn't empty.
            appActivityMonitor.refreshWindowSnapshotForPicker()
        }
        appState.clearPendingOpen()
        appState.isManualPickerPresentation = true
        pickerCoordinator.showPicker(state: appState)
        guard appState.pickerActivationMode != .holdOptionTab else {
            // Match the native app switcher: keep the visible list stable until Option is released.
            return
        }
        // Open instantly from the cached snapshot, then correct the list in place once a live
        // enumeration pass (off the main thread) lands.
        appActivityMonitor.refreshWindowsForVisiblePicker { [weak self] in
            self?.pickerCoordinator.refreshManualPickerSession()
        }
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
        // A routing request supersedes any scheduled main-window open — cancel it outright so a
        // late-firing timer can never pop the main window over the picker.
        cancelScheduledMainWindowOpen()

        guard isLaunchConfigured else {
            // Launch config (browsers/rules/apps) isn't loaded yet — routing now would misfire.
            bufferedLaunchURLs.append(contentsOf: rawURLs)
            Log.app.info("Buffered \(rawURLs.count) URL(s) until launch configuration completes")
            return
        }

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

    private func flushBufferedLaunchURLs() {
        guard !bufferedLaunchURLs.isEmpty else { return }
        let urls = bufferedLaunchURLs
        bufferedLaunchURLs = []
        handleIncomingURLs(urls)
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
