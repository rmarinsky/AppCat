import Foundation
import os

@MainActor
final class PickerCoordinator {
    private struct PendingOpenSnapshot {
        let url: URL
        let displayURLs: [URL]
        let launchURLs: [URL]
        let title: String?
    }

    private let browserLauncher = BrowserLauncher()
    private let urlResolver = URLResolver()
    private var pickerController: PickerWindowController?
    var historyManager: HistoryManager?
    var suggestionsManager: SuggestionsManager?
    var statsManager: StatsManager?

    func showPicker(state: AppState) {
        if pickerController == nil {
            pickerController = PickerWindowController(appState: state, coordinator: self)
        }
        // Mark visible before ordering front: the SwiftUI content's onAppear gates its focus/
        // snapshot seeding on this flag (to stay inert during pre-warm) and can fire mid-show().
        state.isPickerVisible = true
        pickerController?.show()
    }

    /// Build the picker panel + SwiftUI hierarchy ahead of time (ordered out) so the first real
    /// presentation doesn't pay window/view-graph construction on the click-to-picker path.
    func prewarmPicker(state: AppState) {
        guard pickerController == nil, !state.isPickerVisible else { return }
        pickerController = PickerWindowController(appState: state, coordinator: self)
        pickerController?.prewarm()
    }

    /// Forward a live window-cache refresh to the visible manual switcher session.
    func refreshManualPickerSession() {
        pickerController?.refreshSnapshotForVisibleSession()
    }

    func moveFocus(delta: Int, state: AppState) {
        guard state.isPickerVisible else { return }
        pickerController?.moveFocusForVisibleSession(delta: delta)
    }

    func openFocusedItem(state: AppState) {
        guard state.isPickerVisible else { return }
        pickerController?.openFocusedItemForVisibleSession()
    }

    func dismissPicker(state: AppState) {
        pickerController?.close()
        // Clear routing state here too: on the auto-route path the picker controller may not
        // exist yet, and its close() (which also clears) never runs — a stale pendingURL would
        // otherwise block main-window opens and Dock-icon reopen forever. Double-clear is
        // idempotent for the controller-backed path.
        state.isPickerVisible = false
        state.clearPendingOpen()
        state.isManualPickerPresentation = false
        state.pickerItemsSnapshot = []
    }

    func openURL(
        with browser: InstalledBrowser,
        mode: BrowserLauncher.OpenMode = .normal,
        profile: BrowserProfile? = nil,
        windowTarget: AppWindowTarget? = nil,
        state: AppState,
        source: OpenSource = .pickerClick
    ) {
        guard let pendingOpen = snapshotPendingOpen(state: state) else {
            dismissPicker(state: state)
            browserLauncher.activate(browser: browser, profile: profile, windowTarget: windowTarget)
            return
        }
        dismissPickerForSelection(pendingOpen, state: state)
        // Launch the original/wrapped URL(s) so Slack click tracking, Teams Safe Links security
        // scanning, OIDC handshakes, etc. still see the click. The normalized URL is only used
        // internally for rule matching, history, and suggestions.
        browserLauncher.open(urls: pendingOpen.launchURLs, with: browser, mode: mode, profile: profile)
        deferHandoffOverlay(
            .init(
                icon: browser.icon,
                destinationName: profile.map { "\(browser.displayName) · \($0.displayName)" } ?? browser.displayName,
                reason: HandoffReason(source: source)
            ),
            state: state
        )
        recordBrowserOpen(
            pendingOpen,
            browser: browser,
            profile: profile,
            source: source,
            state: state
        )
    }

    func openURL(
        with app: InstalledApp,
        windowTarget: AppWindowTarget? = nil,
        state: AppState,
        source: OpenSource = .pickerClick
    ) {
        guard let pendingOpen = snapshotPendingOpen(state: state) else {
            dismissPicker(state: state)
            browserLauncher.activate(app: app, windowTarget: windowTarget)
            deferPostSelectionWork {
                state.recordAppUsage(app.id)
            }
            return
        }
        dismissPickerForSelection(pendingOpen, state: state)
        for launchURL in pendingOpen.launchURLs {
            browserLauncher.open(url: launchURL, with: app)
        }
        deferHandoffOverlay(
            .init(icon: app.icon, destinationName: app.displayName, reason: HandoffReason(source: source)),
            state: state
        )
        recordAppOpen(pendingOpen, app: app, source: source, state: state)
    }

    func reopenURL(_ urlString: String, state: AppState) {
        guard let url = URL(string: urlString) else { return }
        state.isManualPickerPresentation = false
        state.setPendingOpen(displayURLs: [url], launchURLs: [url])
        showPicker(state: state)
    }

    private func snapshotPendingOpen(state: AppState) -> PendingOpenSnapshot? {
        guard let url = state.pendingURL else { return nil }
        return PendingOpenSnapshot(
            url: url,
            displayURLs: state.pendingDisplayURLs,
            launchURLs: state.launchURLsForPendingOpen,
            title: state.pendingURLTitle
        )
    }

    private func dismissPickerForSelection(_ pendingOpen: PendingOpenSnapshot, state: AppState) {
        state.lastOpenedURL = pendingOpen.url.absoluteString
        SettingsStorage.shared.lastURL = pendingOpen.url.absoluteString
        dismissPicker(state: state)
    }

    private func recordBrowserOpen(
        _ pendingOpen: PendingOpenSnapshot,
        browser: InstalledBrowser,
        profile: BrowserProfile?,
        source: OpenSource,
        state: AppState
    ) {
        deferPostSelectionWork {
            let entryIDs = self.historyManager?.record(
                urls: pendingOpen.displayURLs,
                title: pendingOpen.title,
                appName: browser.displayName,
                profileName: profile?.displayName,
                browserID: browser.id,
                profileDirectoryName: profile?.directoryName,
                targetType: .browser,
                sourceRuleID: source.ruleID,
                state: state
            ) ?? []
            self.statsManager?.record(source)
            for (index, entryID) in entryIDs.enumerated() {
                guard pendingOpen.launchURLs.indices.contains(index),
                      pendingOpen.displayURLs.indices.contains(index)
                else { continue }
                self.resolveFinalURL(
                    forEntry: entryID,
                    sourceURL: pendingOpen.launchURLs[index],
                    displayURL: pendingOpen.displayURLs[index],
                    state: state
                )
            }
            self.suggestionsManager?.recompute(state: state)
        }
    }

    private func recordAppOpen(
        _ pendingOpen: PendingOpenSnapshot,
        app: InstalledApp,
        source: OpenSource,
        state: AppState
    ) {
        deferPostSelectionWork {
            state.recordAppUsage(app.id)
            let entryIDs = self.historyManager?.record(
                urls: pendingOpen.displayURLs,
                title: pendingOpen.title,
                appName: app.displayName,
                profileName: nil,
                browserID: app.id,
                profileDirectoryName: nil,
                targetType: .app,
                sourceRuleID: source.ruleID,
                state: state
            ) ?? []
            self.statsManager?.record(source)
            for (index, entryID) in entryIDs.enumerated() {
                guard pendingOpen.launchURLs.indices.contains(index),
                      pendingOpen.displayURLs.indices.contains(index)
                else { continue }
                self.resolveFinalURL(
                    forEntry: entryID,
                    sourceURL: pendingOpen.launchURLs[index],
                    displayURL: pendingOpen.displayURLs[index],
                    state: state
                )
            }
            self.suggestionsManager?.recompute(state: state)
        }
    }

    private func deferPostSelectionWork(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 750_000_000)
            work()
        }
    }

    private func deferHandoffOverlay(_ presentation: HandoffPresentation, state: AppState) {
        let locale = state.appLanguage.locale
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            HandoffOverlayController.shared.present(presentation, locale: locale)
        }
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
