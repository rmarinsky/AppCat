import Foundation
import Observation
import os

@Observable
@MainActor
final class AppState {
    /// Normalized URL — used for rule matching, history, picker display, and suggestion analysis.
    var pendingURL: URL?
    /// Extra URLs from one system open request, usually multi-file opens from Finder.
    /// The first item still lives in `pendingURL` to preserve the existing picker flow.
    var pendingAdditionalURLs: [URL] = []
    /// URLs that should be launched. For wrapped links and shortcut files, this can differ
    /// from the display/rule-matching URLs stored in `pendingURL` and `pendingAdditionalURLs`.
    var pendingLaunchURLs: [URL] = []
    var pendingURLTitle: String?
    var browsers: [InstalledBrowser] = []
    var apps: [InstalledApp] = []
    var lastOpenedURL: String?
    var isPickerVisible: Bool = false
    var isDefaultBrowser: Bool = false
    var isDefaultWebFileHandler: Bool = false
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

    var pendingDisplayURLs: [URL] {
        guard let pendingURL else { return [] }
        return [pendingURL] + pendingAdditionalURLs
    }

    var launchURLsForPendingOpen: [URL] {
        let displayURLs = pendingDisplayURLs
        guard !pendingLaunchURLs.isEmpty, pendingLaunchURLs.count == displayURLs.count else {
            return displayURLs
        }
        return pendingLaunchURLs
    }

    func setPendingOpen(displayURLs: [URL], launchURLs: [URL]) {
        guard let firstDisplayURL = displayURLs.first else {
            clearPendingOpen()
            return
        }

        let normalizedLaunchURLs = launchURLs.count == displayURLs.count ? launchURLs : displayURLs
        pendingURL = firstDisplayURL
        pendingAdditionalURLs = Array(displayURLs.dropFirst())
        pendingLaunchURLs = normalizedLaunchURLs
        pendingURLTitle = nil
    }

    func clearPendingOpen() {
        pendingURL = nil
        pendingAdditionalURLs = []
        pendingLaunchURLs = []
        pendingURLTitle = nil
    }
}
