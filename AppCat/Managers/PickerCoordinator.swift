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

    private let browserLauncher: BrowserLauncher
    private let urlResolver = URLResolver()
    private var pickerController: PickerWindowController?
    var historyManager: HistoryManager?
    var suggestionsManager: SuggestionsManager?
    var statsManager: StatsManager?

    init() {
        browserLauncher = BrowserLauncher()
    }

    init(browserLauncher: BrowserLauncher) {
        self.browserLauncher = browserLauncher
    }

    func showPicker(state: AppState) {
        if state.isManualPickerPresentation, !state.isPickerSessionActive {
            state.manualPickerTargetCounts = statsManager?.recentManualPickerTargetCounts() ?? [:]
        }
        if pickerController == nil {
            pickerController = PickerWindowController(appState: state, coordinator: self)
        }
        // Mark presentation pending before ordering front. `isPickerVisible` flips true only after
        // a successful orderFront so Dock reopen is not blocked during the deactivation wait.
        // Snapshot/focus seeding happens inside show() and does not depend on isPickerVisible.
        state.isPickerPresentationPending = true
        pickerController?.show()
    }

    /// Build the picker panel + SwiftUI hierarchy ahead of time (ordered out) so the first real
    /// presentation doesn't pay window/view-graph construction on the click-to-picker path.
    func prewarmPicker(state: AppState) {
        guard pickerController == nil, !state.isPickerSessionActive else { return }
        pickerController = PickerWindowController(appState: state, coordinator: self)
        pickerController?.prewarm()
    }

    /// Forward a live window-cache refresh to the visible manual switcher session.
    func refreshManualPickerSession() {
        pickerController?.refreshSnapshotForVisibleSession()
    }

    /// Re-assert fullscreen-safe policy, position, and z-order without rebuilding the session.
    func reassertPickerVisibility(state: AppState) {
        guard state.isPickerSessionActive else { return }
        pickerController?.reassertVisibility()
    }

    func moveFocus(delta: Int, state: AppState) {
        guard state.isPickerSessionActive else { return }
        pickerController?.moveFocusForVisibleSession(delta: delta)
    }

    func openFocusedItem(state: AppState) {
        guard state.isPickerSessionActive else { return }
        guard let pickerController else {
            // No panel backing the session — clear stuck empty/OOB state.
            dismissPicker(state: state)
            return
        }
        pickerController.openFocusedItemForVisibleSession()
    }

    func dismissPicker(state: AppState) {
        pickerController?.close()
        // Clear routing state here too: on the auto-route path the picker controller may not
        // exist yet, and its close() (which also clears) never runs — a stale pendingURL would
        // otherwise block main-window opens and Dock-icon reopen forever. Double-clear is
        // idempotent for the controller-backed path.
        state.isPickerVisible = false
        state.isPickerPresentationPending = false
        state.clearPendingOpen()
        state.pickerInvocationSource = .linkRouting
        state.pickerItemsSnapshot = []
    }

    func configureAppsForUnmatchedFile(state: AppState) {
        guard PickerEmptyStatePolicy.action(
            for: state.pendingURL,
            itemCount: 0,
            invocationSource: state.pickerInvocationSource
        ) == .configureApps else { return }

        dismissPicker(state: state)
        state.mainWindowSection = .settingsApps
        MainWindowActivation.requestOpen()
    }

    @discardableResult
    func select(
        _ item: PickerItem,
        mode: BrowserLauncher.OpenMode = .normal,
        state: AppState,
        source: OpenSource = .pickerClick
    ) -> Bool {
        guard state.isPickerSessionActive else { return false }

        if let app = item.app {
            openURL(
                with: app,
                windowTarget: item.windowTarget,
                state: state,
                source: source
            )
            return true
        }

        guard let browser = item.browser else { return false }
        openURL(
            with: browser,
            mode: mode,
            profile: item.profile,
            windowTarget: item.windowTarget,
            state: state,
            source: source
        )
        return true
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
            let shouldRecordManualSwitch = state.isManualPickerPresentation
            dismissPicker(state: state)
            #if DEBUG
                if UITestRuntime.isEnabled { return }
            #endif
            let didActivate = browserLauncher.activate(browser: browser, profile: profile, windowTarget: windowTarget)
            if shouldRecordManualSwitch, didActivate {
                statsManager?.recordManualPickerSwitch(targetID: browser.id)
            }
            return
        }
        dismissPickerForSelection(pendingOpen, state: state)
        #if DEBUG
            if UITestRuntime.isEnabled { return }
        #endif
        // Launch the original/wrapped URL(s) so Slack click tracking, Teams Safe Links security
        // scanning, OIDC handshakes, etc. still see the click. The normalized URL is only used
        // internally for rule matching, history, and suggestions.
        browserLauncher.open(
            urls: pendingOpen.launchURLs,
            with: browser,
            mode: mode,
            profile: profile
        ) { [weak self] succeeded in
            guard succeeded, let self else { return }
            self.recordBrowserOpen(
                pendingOpen,
                browser: browser,
                profile: profile,
                source: source,
                state: state
            )
            self.deferHandoffOverlay(
                .init(
                    icon: browser.icon,
                    destinationName: profile.map { "\(browser.displayName) · \($0.displayName)" } ?? browser.displayName,
                    reason: HandoffReason(source: source)
                ),
                state: state
            )
        }
    }

    func openURL(
        with app: InstalledApp,
        windowTarget: AppWindowTarget? = nil,
        state: AppState,
        source: OpenSource = .pickerClick
    ) {
        guard let pendingOpen = snapshotPendingOpen(state: state) else {
            let shouldRecordManualSwitch = state.isManualPickerPresentation
            dismissPicker(state: state)
            #if DEBUG
                if UITestRuntime.isEnabled { return }
            #endif
            let didActivate = browserLauncher.activate(app: app, windowTarget: windowTarget)
            if shouldRecordManualSwitch, didActivate {
                statsManager?.recordManualPickerSwitch(targetID: app.id)
            }
            return
        }
        dismissPickerForSelection(pendingOpen, state: state)
        #if DEBUG
            if UITestRuntime.isEnabled { return }
        #endif
        browserLauncher.open(urls: pendingOpen.launchURLs, with: app) { [weak self] results in
            guard let self else { return }
            let successfulIndices = results.indices.filter {
                results[$0]
                    && pendingOpen.displayURLs.indices.contains($0)
                    && pendingOpen.launchURLs.indices.contains($0)
            }
            guard !successfulIndices.isEmpty else { return }
            let successfulOpen = PendingOpenSnapshot(
                url: pendingOpen.url,
                displayURLs: successfulIndices.map { pendingOpen.displayURLs[$0] },
                launchURLs: successfulIndices.map { pendingOpen.launchURLs[$0] },
                title: pendingOpen.title
            )
            self.recordAppOpen(successfulOpen, app: app, source: source, state: state)
            self.deferHandoffOverlay(
                .init(icon: app.icon, destinationName: app.displayName, reason: HandoffReason(source: source)),
                state: state
            )
        }
    }

    func reopenURL(_ urlString: String, state: AppState) {
        guard let url = URL(string: urlString) else { return }
        state.pickerInvocationSource = .linkRouting
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
        let entryIDs = historyManager?.record(
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
        statsManager?.record(source, profileTargeted: profile != nil)
        for (index, entryID) in entryIDs.enumerated() {
            guard pendingOpen.launchURLs.indices.contains(index),
                  pendingOpen.displayURLs.indices.contains(index)
            else { continue }
            resolveFinalURL(
                forEntry: entryID,
                sourceURL: pendingOpen.launchURLs[index],
                displayURL: pendingOpen.displayURLs[index],
                state: state
            )
        }
        deferSuggestionRecompute(state: state)
    }

    private func recordAppOpen(
        _ pendingOpen: PendingOpenSnapshot,
        app: InstalledApp,
        source: OpenSource,
        state: AppState
    ) {
        state.recordAppUsage(app.id)
        let entryIDs = historyManager?.record(
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
        statsManager?.record(source)
        for (index, entryID) in entryIDs.enumerated() {
            guard pendingOpen.launchURLs.indices.contains(index),
                  pendingOpen.displayURLs.indices.contains(index)
            else { continue }
            resolveFinalURL(
                forEntry: entryID,
                sourceURL: pendingOpen.launchURLs[index],
                displayURL: pendingOpen.displayURLs[index],
                state: state
            )
        }
        deferSuggestionRecompute(state: state)
    }

    private func deferSuggestionRecompute(state: AppState) {
        Task { @MainActor in
            await Task.yield()
            self.suggestionsManager?.recompute(state: state)
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
