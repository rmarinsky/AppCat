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
    var isSettingDefaultBrowser: Bool = false
    var isSettingDefaultWebFileHandler: Bool = false
    var focusedBrowserIndex: Int = 0

    var urlRules: [URLRule] = []
    var history: [HistoryEntry] = []
    var suggestions: [RuleSuggestion] = []
    var appUsage: [String: AppUsage] = [:]
    /// Per-app system activation tally (count + recency) — the app switcher's sort signal.
    var appActivations: [String: AppUsage] = [:]
    var recentLinksCount: Int = 3
    /// Show running apps without open windows in the switcher (dimmed group).
    var showWindowlessApps: Bool = true
    /// Include menu-bar / background apps (`.accessory` / `.prohibited`) in the switcher.
    var showBackgroundApps: Bool = false
    var pickerLayout: PickerLayout = .horizontal
    var selectWithNumberKeys: Bool = true
    var pickerItemsSnapshot: [PickerItem] = []
    var isManualPickerPresentation: Bool = false
    var runningAppBundleIDs: Set<String> = []
    /// Bundle IDs of running apps with `.regular` activation policy (Dock apps). Menu-bar
    /// (`.accessory`) and background (`.prohibited`) apps are excluded — the switcher filters by this.
    var regularAppBundleIDs: Set<String> = []
    var runningWindowsByAppID: [String: [AppWindowTarget]] = [:]
    var frontmostAppBundleID: String?
    var appActivityUpdatedAt: Date?
    var appWindowActivityUpdatedAt: Date?
    var appLanguage: AppLanguage = .default
    var mainWindowSection: MainWindowSection = .overview

    var cachedRunningBundleIDs: Set<String>? {
        appActivityUpdatedAt == nil ? nil : runningAppBundleIDs
    }

    var cachedWindowsByAppID: [String: [AppWindowTarget]]? {
        appWindowActivityUpdatedAt == nil ? nil : runningWindowsByAppID
    }

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

    /// All apps sorted by usage frequency (most-used first), then alphabetically.
    var appsByFrequency: [InstalledApp] {
        apps.sorted { lhs, rhs in
            let lc = appUsage[lhs.id]?.count ?? 0
            let rc = appUsage[rhs.id]?.count ?? 0
            if lc != rc { return lc > rc }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// User-installed apps, most-used first — the top section of the Apps screen. Apps that
    /// declare no file support sink to the bottom (still ranked by use among themselves).
    var installedApps: [InstalledApp] {
        let installed = appsByFrequency.filter { !$0.isSystemApp }
        return installed.filter(\.declaresFileSupport) + installed.filter { !$0.declaresFileSupport }
    }

    /// Apple / system apps, alphabetical — the bottom section of the Apps screen. These stay
    /// out of the frequency race so they don't crowd out the apps you actually route to; and,
    /// like the installed list, file-less apps sink below the ones that open files.
    var systemApps: [InstalledApp] {
        let system = apps.filter(\.isSystemApp)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return system.filter(\.declaresFileSupport) + system.filter { !$0.declaresFileSupport }
    }

    /// Persist the format overrides + unknown-type routing chosen in the format editor.
    func updateAppFormats(appID: String, customFormats: [String]?, opensUnknownTypes: Bool) {
        guard let idx = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[idx].customFormats = customFormats
        apps[idx].opensUnknownTypes = opensUnknownTypes
        AppConfigStorage.shared.save(apps)
    }

    /// Record one use of an app as an open target and persist the running tally.
    func recordAppUsage(_ bundleID: String) {
        var entry = appUsage[bundleID] ?? AppUsage(count: 0, lastUsed: Date())
        entry.count += 1
        entry.lastUsed = Date()
        appUsage[bundleID] = entry
        AppUsageStorage.shared.save(appUsage)
    }

    /// Record one system activation of an app (it became frontmost) and persist the tally. This is
    /// the switcher's frequency + recency signal; AppCat itself is ignored by the caller.
    func recordAppActivation(_ bundleID: String) {
        var entry = appActivations[bundleID] ?? AppUsage(count: 0, lastUsed: Date())
        entry.count += 1
        entry.lastUsed = Date()
        appActivations[bundleID] = entry
        AppActivationStore.shared.save(appActivations)
    }

    init() {
        SettingsStorage.shared.applyLanguagePreference()
        lastOpenedURL = SettingsStorage.shared.lastURL
        recentLinksCount = SettingsStorage.shared.recentLinksCount
        pickerLayout = .horizontal
        selectWithNumberKeys = SettingsStorage.shared.selectWithNumberKeys
        appLanguage = SettingsStorage.shared.appLanguage
        appUsage = AppUsageStorage.shared.load()
        appActivations = AppActivationStore.shared.load()
        showWindowlessApps = SettingsStorage.shared.showWindowlessApps
        showBackgroundApps = SettingsStorage.shared.showBackgroundApps
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
