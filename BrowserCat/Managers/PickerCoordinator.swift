import Foundation
import os

@MainActor
final class PickerCoordinator {
    private let browserLauncher = BrowserLauncher()
    private var pickerController: PickerWindowController?
    var historyManager: HistoryManager?
    var suggestionsManager: SuggestionsManager?

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

    func openURL(with browser: InstalledBrowser, mode: BrowserLauncher.OpenMode = .normal, profile: BrowserProfile? = nil, state: AppState) {
        guard let url = state.pendingURL else { return }
        browserLauncher.open(url: url, with: browser, mode: mode, profile: profile)
        historyManager?.record(
            url: url,
            title: state.pendingURLTitle,
            appName: browser.displayName,
            profileName: profile?.displayName,
            browserID: browser.id,
            profileDirectoryName: profile?.directoryName,
            targetType: .browser,
            state: state
        )
        completeURLOpen(url, state: state)
    }

    func openURL(with app: InstalledApp, state: AppState) {
        guard let url = state.pendingURL else { return }
        browserLauncher.open(url: url, with: app)
        historyManager?.record(
            url: url,
            title: state.pendingURLTitle,
            appName: app.displayName,
            profileName: nil,
            browserID: app.id,
            profileDirectoryName: nil,
            targetType: .app,
            state: state
        )
        completeURLOpen(url, state: state)
    }

    func reopenURL(_ urlString: String, state: AppState) {
        guard let url = URL(string: urlString) else { return }
        state.pendingURL = url
        showPicker(state: state)
    }

    private func completeURLOpen(_ url: URL, state: AppState) {
        state.lastOpenedURL = url.absoluteString
        SettingsStorage.shared.lastURL = url.absoluteString
        state.pendingURL = nil
        state.pendingURLTitle = nil
        dismissPicker(state: state)
        suggestionsManager?.recompute(state: state)
    }
}
