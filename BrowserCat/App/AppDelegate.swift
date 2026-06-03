import AppKit
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

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        browserManager.refreshBrowsers(into: appState)
        appManager.refreshApps(into: appState)
        urlRulesManager.load(into: appState)
        defaultBrowserManager.checkIsDefault(state: appState)
        historyManager.load(into: appState)
        statsManager.load()
        statsManager.backfillIfNeeded(history: appState.history, rules: appState.urlRules)
        pickerCoordinator.historyManager = historyManager
        pickerCoordinator.suggestionsManager = suggestionsManager
        pickerCoordinator.statsManager = statsManager
        suggestionsManager.loadCached(into: appState)
        suggestionsManager.analyseIfNeeded(state: appState)
        _ = updaterManager

        Log.app.info("BrowserCat launched")
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
