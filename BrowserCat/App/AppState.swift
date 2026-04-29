import Foundation
import Observation
import os

@Observable
@MainActor
final class AppState {
    /// Unwrapped URL — used for rule matching, history, picker display, and suggestion analysis.
    var pendingURL: URL?
    /// Original URL as received from the system — sent to the browser when launching, so wrappers
    /// (Slack click tracking, Teams Safe Links security scan, OIDC handshake) still see the click.
    /// `nil` when the URL didn't need unwrapping.
    var pendingOriginalURL: URL?
    var pendingURLTitle: String?
    var browsers: [InstalledBrowser] = []
    var apps: [InstalledApp] = []
    var lastOpenedURL: String?
    var isPickerVisible: Bool = false
    var isDefaultBrowser: Bool = false
    var focusedBrowserIndex: Int = 0

    var urlRules: [URLRule] = []
    var history: [HistoryEntry] = []
    var suggestions: [RuleSuggestion] = []
    var recentLinksCount: Int = 3
    var compactPickerView: Bool = false
    var appLanguage: AppLanguage = .default

    var visibleBrowsers: [InstalledBrowser] {
        browsers.filter { $0.isVisible && !$0.isIgnored }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var pickerBrowsers: [InstalledBrowser] {
        browsers
            .filter { browser in
                !browser.isIgnored && (browser.isVisible || browser.profiles.contains(where: { $0.isVisible }))
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var ignoredBrowsers: [InstalledBrowser] {
        browsers.filter(\.isIgnored).sorted { $0.sortOrder < $1.sortOrder }
    }

    var visibleApps: [InstalledApp] {
        apps.filter(\.isVisible).sorted { $0.sortOrder < $1.sortOrder }
    }

    init() {
        SettingsStorage.shared.applyLanguagePreference()
        lastOpenedURL = SettingsStorage.shared.lastURL
        recentLinksCount = SettingsStorage.shared.recentLinksCount
        compactPickerView = SettingsStorage.shared.compactPickerView
        appLanguage = SettingsStorage.shared.appLanguage
        Log.app.debug("AppState initialized")
    }
}
