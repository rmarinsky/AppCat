import Foundation
import os

@MainActor
final class PickerCoordinator {
    private let browserLauncher = BrowserLauncher()
    private let urlResolver = URLResolver()
    private var pickerController: PickerWindowController?
    var historyManager: HistoryManager?
    var suggestionsManager: SuggestionsManager?
    var statsManager: StatsManager?

    func showPicker(state: AppState) {
        guard state.pendingURL != nil else { return }

        if pickerController == nil {
            pickerController = PickerWindowController(appState: state, coordinator: self)
        }
        pickerController?.show()
        state.isPickerVisible = true
    }

    func dismissPicker(state: AppState) {
        pickerController?.close()
        state.isPickerVisible = false
    }

    func openURL(
        with browser: InstalledBrowser,
        mode: BrowserLauncher.OpenMode = .normal,
        profile: BrowserProfile? = nil,
        state: AppState,
        source: OpenSource = .pickerClick
    ) {
        guard let url = state.pendingURL else { return }
        let displayURLs = state.pendingDisplayURLs
        // Launch the original/wrapped URL(s) so Slack click tracking, Teams Safe Links security
        // scanning, OIDC handshakes, etc. still see the click. The normalized URL is only used
        // internally for rule matching, history, and suggestions.
        let launchURLs = state.launchURLsForPendingOpen
        browserLauncher.open(urls: launchURLs, with: browser, mode: mode, profile: profile)
        let entryIDs = displayURLs.enumerated().map { index, displayURL in
            historyManager?.record(
                url: displayURL,
                title: index == 0 ? state.pendingURLTitle : nil,
                appName: browser.displayName,
                profileName: profile?.displayName,
                browserID: browser.id,
                profileDirectoryName: profile?.directoryName,
                targetType: .browser,
                state: state
            )
        }
        statsManager?.record(source)
        for (index, entryID) in entryIDs.enumerated() {
            guard launchURLs.indices.contains(index), displayURLs.indices.contains(index) else { continue }
            resolveFinalURL(forEntry: entryID, sourceURL: launchURLs[index], displayURL: displayURLs[index], state: state)
        }
        completeURLOpen(url, state: state)
    }

    func openURL(with app: InstalledApp, state: AppState, source: OpenSource = .pickerClick) {
        guard let url = state.pendingURL else { return }
        state.recordAppUsage(app.id)
        let displayURLs = state.pendingDisplayURLs
        let launchURLs = state.launchURLsForPendingOpen
        for launchURL in launchURLs {
            browserLauncher.open(url: launchURL, with: app)
        }
        let entryIDs = displayURLs.enumerated().map { index, displayURL in
            historyManager?.record(
                url: displayURL,
                title: index == 0 ? state.pendingURLTitle : nil,
                appName: app.displayName,
                profileName: nil,
                browserID: app.id,
                profileDirectoryName: nil,
                targetType: .app,
                state: state
            )
        }
        statsManager?.record(source)
        for (index, entryID) in entryIDs.enumerated() {
            guard launchURLs.indices.contains(index), displayURLs.indices.contains(index) else { continue }
            resolveFinalURL(forEntry: entryID, sourceURL: launchURLs[index], displayURL: displayURLs[index], state: state)
        }
        completeURLOpen(url, state: state)
    }

    func reopenURL(_ urlString: String, state: AppState) {
        guard let url = URL(string: urlString) else { return }
        state.setPendingOpen(displayURLs: [url], launchURLs: [url])
        showPicker(state: state)
    }

    private func completeURLOpen(_ url: URL, state: AppState) {
        state.lastOpenedURL = url.absoluteString
        SettingsStorage.shared.lastURL = url.absoluteString
        state.clearPendingOpen()
        dismissPicker(state: state)
        suggestionsManager?.recompute(state: state)
    }

    /// Follows server redirects in the background and updates the recorded history
    /// entry to reflect where the user actually lands (e.g. office.com → microsoft.com).
    /// No-ops when the resolved URL is the same as what we already recorded.
    private func resolveFinalURL(forEntry entryID: UUID?, sourceURL: URL, displayURL: URL, state: AppState) {
        guard let entryID else { return }
        let resolver = urlResolver
        Task { @MainActor [weak self] in
            guard let final = await resolver.resolveFinalURL(for: sourceURL) else { return }
            // Skip if the chain landed back at the URL we already recorded — avoids
            // a redundant write and a redundant suggestion recompute.
            if final.absoluteString == displayURL.absoluteString { return }
            guard let self else { return }
            self.historyManager?.updateURL(id: entryID, finalURL: final, state: state)
            self.suggestionsManager?.recompute(state: state)
        }
    }
}
