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
        pickerCoordinator.historyManager = historyManager
        _ = updaterManager

        Log.app.info("BrowserCat launched")
    }

    // MARK: - URL Handling

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, withReply _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString)
        else {
            Log.app.error("Received invalid URL event")
            return
        }

        Log.app.info("Received URL: \(urlString)")
        appState.pendingURL = url
        appState.pendingURLTitle = nil
        fetchTitle(for: url)

        // Check URL rules before showing picker
        if let match = urlRulesManager.findMatch(
            for: url,
            browsers: appState.browsers,
            apps: appState.apps,
            rules: appState.urlRules
        ) {
            switch match {
            case let .browser(browser, profile):
                pickerCoordinator.openURL(with: browser, profile: profile, state: appState)
                return
            case let .app(app):
                pickerCoordinator.openURL(with: app, state: appState)
                return
            }
        }

        pickerCoordinator.showPicker(state: appState)
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
