import AppKit
import SwiftUI

/// A picker grid item: a browser, browser+profile, or native app.
struct PickerItem: Identifiable {
    let id: String
    let browser: InstalledBrowser?
    let profile: BrowserProfile? // nil = plain browser entry
    let app: InstalledApp?
    let windowTarget: AppWindowTarget?

    /// App-switcher marking (set by `switcherItems`). `hasOpenWindows` draws the running dot and
    /// places the item in the leading group; `isBackgroundRunning` dims it in the trailing group.
    var hasOpenWindows: Bool = false
    var isBackgroundRunning: Bool = false
    /// Current icon reported by the running process. It overrides the installed-app scan icon so
    /// apps that change their icon at runtime are represented accurately in the switcher.
    var runtimeIcon: NSImage? = nil

    var isBrowser: Bool {
        browser != nil
    }

    var isApp: Bool {
        app != nil
    }

    var isWindow: Bool {
        windowTarget != nil
    }

    var displayName: String {
        if let windowTarget { return windowTarget.title }
        if let profile, let browser { return "\(browser.displayName) - \(profile.displayName)" }
        if let browser { return browser.displayName }
        if let app { return app.displayName }
        return ""
    }

    var secondaryDisplayName: String? {
        if windowTarget != nil { return app?.displayName ?? browser?.displayName }
        if profile != nil { return browser?.displayName }
        return nil
    }

    var searchableStrings: [String] {
        [
            displayName,
            secondaryDisplayName,
            app?.displayName,
            browser?.displayName,
            profile?.displayName,
            profile?.email,
            windowTarget?.title,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    /// Identity for the switcher's "no two tiles read identically" net. Window tiles collapse by
    /// app + case/diacritic-folded title (two same-titled windows of one app are indistinguishable
    /// in the row anyway); every other tile keeps its already-unique `id`.
    var switcherDedupeKey: String {
        guard let windowTarget else { return id }
        let title = windowTarget.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "window-title|\(windowTarget.bundleID)|\(title)"
    }

    var icon: NSImage? {
        runtimeIcon ?? browser?.icon ?? app?.icon
    }

    var hotkey: Character? {
        guard windowTarget == nil else { return nil }
        return profile?.hotkey ?? browser?.hotkey ?? app?.hotkey
    }

    var hotkeyKeyCode: UInt16? {
        guard windowTarget == nil else { return nil }
        return profile?.hotkeyKeyCode ?? browser?.hotkeyKeyCode ?? app?.hotkeyKeyCode
    }

    init(browser: InstalledBrowser) {
        id = browser.id
        self.browser = browser
        profile = nil
        app = nil
        windowTarget = nil
    }

    init(browser: InstalledBrowser, profile: BrowserProfile) {
        id = "\(browser.id):\(profile.directoryName)"
        self.browser = browser
        self.profile = profile
        app = nil
        windowTarget = nil
    }

    init(browser: InstalledBrowser, windowTarget: AppWindowTarget) {
        id = "window:\(windowTarget.id)"
        self.browser = browser
        profile = nil
        app = nil
        self.windowTarget = windowTarget
    }

    init(app: InstalledApp, windowTarget: AppWindowTarget? = nil) {
        id = windowTarget.map { "window:\($0.id)" } ?? "app:\(app.id)"
        browser = nil
        profile = nil
        self.app = app
        self.windowTarget = windowTarget
    }

    /// Build the ordered picker item list.
    /// Priority:
    /// 1) if provided, matching apps for the current URL
    /// 2) profile-with-hotkey
    /// 3) app/browser with hotkey
    /// 4) the rest
    static func buildItems(
        browsers: [InstalledBrowser],
        apps: [InstalledApp],
        prioritizedAppIDs: Set<String> = [],
        browsersFirst: Bool = false
    ) -> [PickerItem] {
        let appItems = apps.map { PickerItem(app: $0) }
        var browserItems: [PickerItem] = []

        for browser in browsers {
            let visibleProfiles = browser.profiles.filter(\.isVisible)

            // If browser has enabled profiles, show only profiles in picker.
            if visibleProfiles.isEmpty, browser.isVisible {
                browserItems.append(PickerItem(browser: browser))
            }

            for profile in visibleProfiles {
                browserItems.append(PickerItem(browser: browser, profile: profile))
            }
        }

        if browsersFirst {
            return orderedByHotkeys(browserItems) + orderedByHotkeys(appItems)
        }

        let ordered = orderedByHotkeys(appItems + browserItems)

        guard !prioritizedAppIDs.isEmpty else {
            return ordered
        }

        let prioritized = ordered.filter { item in
            guard let appID = item.app?.id else { return false }
            return prioritizedAppIDs.contains(appID)
        }
        let rest = ordered.filter { item in
            guard let appID = item.app?.id else { return true }
            return !prioritizedAppIDs.contains(appID)
        }
        return prioritized + rest
    }

    static func shouldShowBrowsersFirst(for url: URL?) -> Bool {
        guard let url, url.isFileURL else { return false }
        return BrowserFileType.isBrowserReadableFile(url)
    }

    private static func orderedByHotkeys(_ items: [PickerItem]) -> [PickerItem] {
        let profileWithHotkey = items.filter { $0.profile != nil && $0.hotkey != nil }
        let otherWithHotkey = items.filter { $0.profile == nil && $0.hotkey != nil }
        let withoutHotkey = items.filter { $0.hotkey == nil }
        return profileWithHotkey + otherWithHotkey + withoutHotkey
    }

    static func matchingApps(
        for url: URL?,
        in apps: [InstalledApp],
        excludingBundleIDs excludedBundleIDs: Set<String> = [],
        includingLaunchServicesCandidates: Bool = false
    ) -> [InstalledApp] {
        guard let url else { return [] }
        if url.isFileURL {
            return InstalledApp.matchingFileApps(
                for: url,
                in: apps,
                excludingBundleIDs: excludedBundleIDs,
                includingLaunchServicesCandidates: includingLaunchServicesCandidates
            )
        }
        return apps.filter { $0.isVisible && !excludedBundleIDs.contains($0.id) && $0.matchesHost(of: url) }
    }

    static func matchingBrowsers(for url: URL?, in browsers: [InstalledBrowser]) -> [InstalledBrowser] {
        guard let url else { return browsers }
        guard url.isFileURL else { return browsers }
        return BrowserFileType.isBrowserReadableFile(url) ? browsers : []
    }

    @MainActor
    static func items(
        for url: URL?,
        pickerBrowsers: [InstalledBrowser],
        allBrowsers: [InstalledBrowser],
        apps: [InstalledApp],
        appUsage: [String: AppUsage],
        runningBundleIDs providedRunningBundleIDs: Set<String>? = nil,
        windowsByAppID providedWindowsByAppID: [String: [AppWindowTarget]]? = nil,
        activations: [String: AppUsage] = [:],
        regularBundleIDs: Set<String>? = nil,
        runningAppsByBundleID: [String: InstalledApp] = [:],
        showWindowlessApps: Bool = true,
        showBackgroundApps: Bool = false,
        hiddenAppIDs: Set<String> = []
    ) -> [PickerItem] {
        let browsers = matchingBrowsers(for: url, in: pickerBrowsers)
            .filter { !hiddenAppIDs.contains($0.id) }
        let allBrowsersForDisplay = allBrowsers.filter { !hiddenAppIDs.contains($0.id) }
        let pickerApps = apps.filter { !hiddenAppIDs.contains($0.id) }
        let browserIDs = Set(allBrowsers.map(\.id))
        if url == nil {
            let runningBundleIDs = providedRunningBundleIDs ?? Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let windowsByAppID = providedWindowsByAppID ?? WindowEnumerator.runningWindows()
            return switcherItems(
                apps: pickerApps,
                browsers: browsers,
                allBrowsers: allBrowsersForDisplay,
                browserIDs: browserIDs,
                runningBundleIDs: runningBundleIDs,
                regularBundleIDs: regularBundleIDs,
                windowsByAppID: windowsByAppID,
                activations: activations,
                runningAppsByBundleID: runningAppsByBundleID.filter { !hiddenAppIDs.contains($0.key) },
                showWindowlessApps: showWindowlessApps,
                showBackgroundApps: showBackgroundApps
            )
        }

        let matchingApps = matchingApps(
            for: url,
            in: pickerApps,
            excludingBundleIDs: browserIDs.union(hiddenAppIDs),
            includingLaunchServicesCandidates: true
        )
        let orderedApps: [InstalledApp]
        if url?.isFileURL == true {
            orderedApps = matchingApps
        } else {
            orderedApps = matchingApps.sorted { lhs, rhs in
                let lhsDate = appUsage[lhs.id]?.lastUsed ?? .distantPast
                let rhsDate = appUsage[rhs.id]?.lastUsed ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                let lhsCount = appUsage[lhs.id]?.count ?? 0
                let rhsCount = appUsage[rhs.id]?.count ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }

        return buildItems(
            browsers: browsers,
            apps: orderedApps,
            prioritizedAppIDs: Set(orderedApps.map(\.id)),
            browsersFirst: shouldShowBrowsersFirst(for: url)
        ).map { withRuntimeIcon($0, from: runningAppsByBundleID) }
    }

    /// The app-switcher (no pending URL) list: running browsers + apps, filtered by activation
    /// policy, sorted by real usage, split into a leading "has open windows" group and a trailing
    /// dimmed "running, no windows" group.
    private static func switcherItems(
        apps: [InstalledApp],
        browsers: [InstalledBrowser],
        allBrowsers: [InstalledBrowser],
        browserIDs: Set<String>,
        runningBundleIDs: Set<String>,
        regularBundleIDs: Set<String>?,
        windowsByAppID: [String: [AppWindowTarget]],
        activations: [String: AppUsage],
        runningAppsByBundleID: [String: InstalledApp],
        showWindowlessApps: Bool,
        showBackgroundApps: Bool
    ) -> [PickerItem] {
        struct Entry { let id: String; let name: String; let hasWindows: Bool; let items: [PickerItem] }

        // Menu-bar (`.accessory`) and background (`.prohibited`) apps are hidden unless opted in.
        // An empty/nil policy set means it hasn't been captured yet (first launch), so don't
        // over-filter — better to show everything briefly than an empty switcher.
        func passesPolicy(_ id: String) -> Bool {
            if showBackgroundApps { return true }
            guard let regularBundleIDs, !regularBundleIDs.isEmpty else { return true }
            return regularBundleIDs.contains(id)
        }

        var entries: [Entry] = []

        // Browsers are Dock apps; keep their existing per-window / profile expansion.
        for browser in browsers where runningBundleIDs.contains(browser.id) {
            let windows = windowsByAppID[browser.id] ?? []
            entries.append(Entry(
                id: browser.id,
                name: browser.displayName,
                hasWindows: !windows.isEmpty,
                items: browserSwitcherItems(for: browser, windows: windows).map {
                    withRuntimeIcon($0, from: runningAppsByBundleID)
                }
            ))
        }

        for app in apps where app.isVisible && !browserIDs.contains(app.id)
            && runningBundleIDs.contains(app.id) && passesPolicy(app.id)
        {
            let windows = windowsByAppID[app.id] ?? []
            entries.append(Entry(
                id: app.id,
                name: app.displayName,
                hasWindows: !windows.isEmpty,
                items: appSwitcherItems(for: app, windows: windows).map {
                    withRuntimeIcon($0, from: runningAppsByBundleID)
                }
            ))
        }

        // Apps that register an http handler (cmux, many Electron/WebKit apps) get detected as
        // "browsers" and, when hidden from the routing picker, fall out of `apps` (their id is a
        // browser id) *and* out of `browsers` (not visible) — vanishing from the switcher entirely.
        // In an app switcher they're just regular running apps, so surface any running, non-ignored
        // browser that isn't already a visible picker entry as a plain app tile.
        let shownBrowserIDs = Set(browsers.map(\.id))
        for browser in allBrowsers where !shownBrowserIDs.contains(browser.id)
            && !browser.isIgnored && runningBundleIDs.contains(browser.id) && passesPolicy(browser.id)
        {
            let windows = windowsByAppID[browser.id] ?? []
            let items = windows.count >= 2
                ? windows.map { PickerItem(browser: browser, windowTarget: $0) }
                : [PickerItem(browser: browser)]
            entries.append(Entry(
                id: browser.id,
                name: browser.displayName,
                hasWindows: !windows.isEmpty,
                items: items.map { withRuntimeIcon($0, from: runningAppsByBundleID) }
            ))
        }

        // A just-launched or newly installed app can precede the slower full /Applications scan.
        // Surface its live NSRunningApplication snapshot immediately instead of waiting for that
        // rescan. Configured apps (including ones the user hid) remain authoritative.
        let configuredAppIDs = Set(apps.map(\.id))
        let representedIDs = configuredAppIDs.union(browserIDs)
        for runtimeApp in runningAppsByBundleID.values
            where runningBundleIDs.contains(runtimeApp.id)
                && !representedIDs.contains(runtimeApp.id)
                && passesPolicy(runtimeApp.id)
        {
            let windows = windowsByAppID[runtimeApp.id] ?? []
            entries.append(Entry(
                id: runtimeApp.id,
                name: runtimeApp.displayName,
                hasWindows: !windows.isEmpty,
                items: appSwitcherItems(for: runtimeApp, windows: windows)
            ))
        }

        // Most-recent first, usage count as tiebreak, then name for a stable order among never-used apps.
        func before(_ x: Entry, _ y: Entry) -> Bool {
            let rx = activations[x.id], ry = activations[y.id]
            let dx = rx?.lastUsed ?? .distantPast, dy = ry?.lastUsed ?? .distantPast
            if dx != dy { return dx > dy }
            let cx = rx?.count ?? 0, cy = ry?.count ?? 0
            if cx != cy { return cx > cy }
            return x.name.localizedCaseInsensitiveCompare(y.name) == .orderedAscending
        }

        let windowed = entries.filter(\.hasWindows).sorted(by: before)
        let windowless = showWindowlessApps ? entries.filter { !$0.hasWindows }.sorted(by: before) : []

        let windowedItems = windowed.flatMap(\.items).map { tagged($0, hasOpenWindows: true, isBackground: false) }
        let windowlessItems = windowless.flatMap(\.items).map { tagged($0, hasOpenWindows: false, isBackground: true) }
        return dedupedForDisplay(windowedItems + windowlessItems)
    }

    /// Safety net: never render two switcher tiles that read identically (see `switcherDedupeKey`).
    /// Upstream window enumeration already dedupes per app+title, but this guarantees the invariant at
    /// the UI boundary regardless of which enumeration path produced the targets.
    private static func dedupedForDisplay(_ items: [PickerItem]) -> [PickerItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.switcherDedupeKey).inserted }
    }

    private static func tagged(_ item: PickerItem, hasOpenWindows: Bool, isBackground: Bool) -> PickerItem {
        var copy = item
        copy.hasOpenWindows = hasOpenWindows
        copy.isBackgroundRunning = isBackground
        return copy
    }

    private static func withRuntimeIcon(
        _ item: PickerItem,
        from runningAppsByBundleID: [String: InstalledApp]
    ) -> PickerItem {
        guard let bundleID = item.app?.id ?? item.browser?.id,
              let icon = runningAppsByBundleID[bundleID]?.icon
        else { return item }
        var copy = item
        copy.runtimeIcon = icon
        return copy
    }

    private static func appSwitcherItems(for app: InstalledApp, windows: [AppWindowTarget]) -> [PickerItem] {
        guard windows.count >= 2 else { return [PickerItem(app: app)] }
        return windows.map { PickerItem(app: app, windowTarget: $0) }
    }

    private static func browserSwitcherItems(for browser: InstalledBrowser, windows: [AppWindowTarget]) -> [PickerItem] {
        guard windows.count >= 2 else {
            return [PickerItem(browser: browser)]
        }
        return windows.map { PickerItem(browser: browser, windowTarget: $0) }
    }
}

enum PickerPresentationStyle {
    case routing
    case appSwitcher
}

enum PickerCellFocusPolicy {
    // The panel owns keyboard selection. Native Button focus would draw a second rectangular ring.
    static let allowsNativeFocus = false
}

enum PickerEmptyStateAction: Equatable {
    case none
    case configureApps
}

enum PickerEmptyStatePolicy {
    static func action(
        for url: URL?,
        itemCount: Int,
        invocationSource: PickerInvocationSource
    ) -> PickerEmptyStateAction {
        guard itemCount == 0,
              invocationSource == .linkRouting,
              url?.isFileURL == true
        else { return .none }

        return .configureApps
    }
}

enum PickerReturnKeyAction: Equatable {
    case openItem(Int)
    case configureApps
    case consume
}

enum PickerReturnKeyPolicy {
    static func action(
        itemCount: Int,
        focusedIndex: Int,
        url: URL?,
        invocationSource: PickerInvocationSource
    ) -> PickerReturnKeyAction {
        if focusedIndex >= 0, focusedIndex < itemCount {
            return .openItem(focusedIndex)
        }
        if PickerEmptyStatePolicy.action(
            for: url,
            itemCount: itemCount,
            invocationSource: invocationSource
        ) == .configureApps {
            return .configureApps
        }
        return .consume
    }
}

enum PickerMetrics {
    static let screenMargin: CGFloat = 8

    private static let tileIconSize: CGFloat = 88
    private static let tileIconChromeSize: CGFloat = 92
    private static let tileFallbackIconSize: CGFloat = 64
    private static let tileWidth: CGFloat = 94
    private static let shortcutVerticalGapBase: CGFloat = 4
    private static let tileSpacing: CGFloat = 2
    private static let tileHorizontalPadding: CGFloat = 28
    private static let tileVerticalPadding: CGFloat = 13
    private static let tileTitleFontSize: CGFloat = 14
    private static let tileTitleHeight: CGFloat = 22
    private static let tileSubtitleFontSize: CGFloat = 12
    private static let tileSubtitleHeight: CGFloat = 18
    private static let tileHeight = tileIconChromeSize
        + tileTitleHeight
        + tileSubtitleHeight
        + shortcutVerticalGapBase * 2
    private static let tileFocusStrokeWidth: CGFloat = 2
    private static let tileFocusCornerRadius: CGFloat = 24
    private static let panelCornerRadiusBase: CGFloat = 48
    private static let hintHeightBase: CGFloat = 14
    private static let emptyStateWidthBase: CGFloat = 380

    static func clampedScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, CGFloat(PickerScale.minimum)), CGFloat(PickerScale.maximum))
    }

    private static func scaled(_ value: CGFloat, by scale: CGFloat) -> CGFloat {
        value * clampedScale(scale)
    }

    static func iconSize(scale: CGFloat = 1) -> CGFloat {
        scaled(tileIconSize, by: scale)
    }

    static func iconChromeSize(scale: CGFloat = 1) -> CGFloat {
        scaled(tileIconChromeSize, by: scale)
    }

    static func fallbackIconSize(scale: CGFloat = 1) -> CGFloat {
        scaled(tileFallbackIconSize, by: scale)
    }

    static func itemWidth(scale: CGFloat = 1) -> CGFloat {
        scaled(tileWidth, by: scale)
    }

    static func itemHeight(scale: CGFloat = 1) -> CGFloat {
        scaled(tileHeight, by: scale)
    }

    static func itemSpacing(scale: CGFloat = 1) -> CGFloat {
        scaled(tileSpacing, by: scale)
    }

    static func horizontalPadding(scale: CGFloat = 1) -> CGFloat {
        scaled(tileHorizontalPadding, by: scale)
    }

    static func scrollHeight(showsIncognitoHint: Bool = false, scale: CGFloat = 1) -> CGFloat {
        let bottomPadding = showsIncognitoHint ? 0 : tileVerticalPadding
        return scaled(tileHeight + tileVerticalPadding + bottomPadding, by: scale)
    }

    static func verticalPadding(scale: CGFloat = 1) -> CGFloat {
        scaled(tileVerticalPadding, by: scale)
    }

    static func titleFontSize(scale: CGFloat = 1) -> CGFloat {
        scaled(tileTitleFontSize, by: scale)
    }

    static func titleHeight(scale: CGFloat = 1) -> CGFloat {
        scaled(tileTitleHeight, by: scale)
    }

    static func shortcutVerticalGap(scale: CGFloat = 1) -> CGFloat {
        scaled(shortcutVerticalGapBase, by: scale)
    }

    static func subtitleFontSize(scale: CGFloat = 1) -> CGFloat {
        scaled(tileSubtitleFontSize, by: scale)
    }

    static func subtitleHeight(scale: CGFloat = 1) -> CGFloat {
        scaled(tileSubtitleHeight, by: scale)
    }

    static func focusStrokeWidth(scale: CGFloat = 1) -> CGFloat {
        scaled(tileFocusStrokeWidth, by: scale)
    }

    static func focusCornerRadius(scale: CGFloat = 1) -> CGFloat {
        scaled(tileFocusCornerRadius, by: scale)
    }

    static func profileBadgeSize(scale: CGFloat = 1) -> CGFloat {
        scaled(16, by: scale)
    }

    static func profileBadgeBorderWidth(scale: CGFloat = 1) -> CGFloat {
        scaled(1.5, by: scale)
    }

    static func panelCornerRadius(scale: CGFloat = 1) -> CGFloat {
        scaled(panelCornerRadiusBase, by: scale)
    }

    static func panelHeight(showsIncognitoHint: Bool = false, scale: CGFloat = 1) -> CGFloat {
        let footerHeight = showsIncognitoHint
            ? shortcutVerticalGapBase + hintHeightBase + tileVerticalPadding
            : 0
        return scrollHeight(showsIncognitoHint: showsIncognitoHint, scale: scale)
            + scaled(footerHeight, by: scale)
    }

    static func hintHeight(scale: CGFloat = 1) -> CGFloat {
        scaled(hintHeightBase, by: scale)
    }

    static func hintBottomInset(scale: CGFloat = 1) -> CGFloat {
        scaled(tileVerticalPadding, by: scale)
    }

    static func contentWidth(
        itemCount: Int,
        scale: CGFloat = 1
    ) -> CGFloat {
        let count = max(1, itemCount)
        return horizontalPadding(scale: scale) * 2
            + CGFloat(count) * itemWidth(scale: scale)
            + CGFloat(max(0, count - 1)) * itemSpacing(scale: scale)
    }

    static func panelWidth(
        itemCount: Int,
        availableWidth: CGFloat,
        showsFileEmptyState: Bool = false,
        scale: CGFloat = 1
    ) -> CGFloat {
        let minPanelWidth = horizontalPadding(scale: scale) * 2 + itemWidth(scale: scale)
        let maxWidth = max(minPanelWidth, availableWidth - screenMargin * 2)
        let contentWidth = showsFileEmptyState
            ? scaled(emptyStateWidthBase, by: scale)
            : contentWidth(itemCount: itemCount, scale: scale)
        return min(max(contentWidth, minPanelWidth), maxWidth)
    }
}

enum PickerTypeAheadMatcher {
    static func firstMatchIndex(in items: [PickerItem], query: String) -> Int? {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return nil }

        if let prefixMatch = items.indices.first(where: { index in
            tokens(for: items[index]).contains { $0.hasPrefix(normalizedQuery) }
        }) {
            return prefixMatch
        }

        return items.indices.first { index in
            normalizedStrings(for: items[index]).contains { $0.contains(normalizedQuery) }
        }
    }

    private static func normalizedStrings(for item: PickerItem) -> [String] {
        item.searchableStrings.map(normalize).filter { !$0.isEmpty }
    }

    private static func tokens(for item: PickerItem) -> [String] {
        normalizedStrings(for: item).flatMap { value in
            value
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

enum PickerTapAction: Equatable {
    case ignore
    case open
}

enum PickerTapPolicy {
    static func action(
        for item: PickerItem,
        isPickerVisible: Bool,
        isManualPickerPresentation: Bool
    ) -> PickerTapAction {
        guard isPickerVisible else { return .ignore }
        return .open
    }
}

struct PickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.pickerCoordinator) private var pickerCoordinator

    private var presentationStyle: PickerPresentationStyle {
        appState.isManualPickerPresentation ? .appSwitcher : .routing
    }

    private var pickerItems: [PickerItem] {
        if !appState.pickerItemsSnapshot.isEmpty {
            return appState.pickerItemsSnapshot
        }

        return PickerItem.items(
            for: appState.pendingURL,
            pickerBrowsers: appState.pickerBrowsers,
            allBrowsers: appState.browsers,
            apps: appState.apps,
            appUsage: appState.appUsage,
            runningBundleIDs: appState.cachedRunningBundleIDs,
            windowsByAppID: appState.cachedWindowsByAppID,
            activations: appState.appActivations,
            regularBundleIDs: appState.regularAppBundleIDs,
            runningAppsByBundleID: appState.runningAppsByBundleID,
            showWindowlessApps: appState.showWindowlessApps,
            showBackgroundApps: appState.showBackgroundApps,
            hiddenAppIDs: appState.hiddenPickerAppIDs
        )
    }

    var body: some View {
        horizontalBody
    }

    private var horizontalBody: some View {
        let items = pickerItems
        let style = presentationStyle
        let scale = CGFloat(appState.pickerScale)
        let shortcuts = PickerShortcutPolicy.assignments(
            for: items,
            invocationSource: appState.pickerInvocationSource,
            selectWithNumberKeys: appState.selectWithNumberKeys
        )
        let showsIncognitoHint = appState.showsPickerIncognitoHint
        let panelHeight = PickerMetrics.panelHeight(showsIncognitoHint: showsIncognitoHint, scale: scale)
        let scrollHeight = PickerMetrics.scrollHeight(showsIncognitoHint: showsIncognitoHint, scale: scale)
        let emptyStateAction = PickerEmptyStatePolicy.action(
            for: appState.pendingURL,
            itemCount: items.count,
            invocationSource: appState.pickerInvocationSource
        )

        return VStack(spacing: 0) {
            if emptyStateAction == .configureApps {
                emptyFileState(scale: scale)
                    .frame(maxWidth: .infinity)
                    .frame(height: scrollHeight)
            } else {
                ScrollViewReader { proxy in
                    GeometryReader { geometry in
                        let contentOverflows = PickerMetrics.contentWidth(
                            itemCount: items.count,
                            scale: scale
                        ) > geometry.size.width + 1

                        // Lazy rendering matters here: file pickers can include many LaunchServices apps.
                        ScrollView(.horizontal, showsIndicators: contentOverflows) {
                            LazyHStack(spacing: PickerMetrics.itemSpacing(scale: scale)) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    pickerCell(
                                        item: item,
                                        index: index,
                                        shortcut: shortcuts[item.id],
                                        style: style,
                                        scale: scale
                                    )
                                    .id(item.id)
                                }
                            }
                            .padding(.horizontal, PickerMetrics.horizontalPadding(scale: scale))
                            .padding(.top, PickerMetrics.verticalPadding(scale: scale))
                            .padding(
                                .bottom,
                                showsIncognitoHint ? 0 : PickerMetrics.verticalPadding(scale: scale)
                            )
                        }
                        .scrollDisabled(!contentOverflows)
                        .background(HorizontalWheelScrollBridge())
                        .frame(height: scrollHeight)
                    }
                    .frame(height: scrollHeight)
                    .onChange(of: appState.focusedBrowserIndex) { _, _ in
                        scrollFocusedItemIntoView(proxy: proxy, items: items)
                    }
                }
            }

            if showsIncognitoHint {
                compactHintBar(scale: scale)
                    .padding(.top, PickerMetrics.shortcutVerticalGap(scale: scale))
                    .padding(.bottom, PickerMetrics.hintBottomInset(scale: scale))
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            prepareInitialFocus(with: items)
        }
        .frame(maxWidth: .infinity, minHeight: panelHeight, maxHeight: panelHeight, alignment: .top)
    }

    private func emptyFileState(scale: CGFloat) -> some View {
        VStack(spacing: 7 * scale) {
            Text(String(localized: "No app can open this file type"))
                .font(.system(size: 14 * scale, weight: .semibold))
            Text(String(localized: "Choose which editors can open any file type, then reopen the file."))
                .font(.system(size: 11 * scale))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button(String(localized: "Configure apps")) {
                pickerCoordinator?.configureAppsForUnmatchedFile(state: appState)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 24 * scale)
    }

    @ViewBuilder
    private func pickerCell(
        item: PickerItem,
        index: Int,
        shortcut: PickerShortcut?,
        style: PickerPresentationStyle = .routing,
        scale: CGFloat = 1
    ) -> some View {
        let hasVisibleProfiles = item.browser?.profiles.contains(where: \.isVisible) == true
        let isFocused = appState.focusedBrowserIndex == index

        Button {
            handleItemTap(item)
        } label: {
            PickerCell(
                item: item,
                isFocused: isFocused,
                shortcut: shortcut,
                compact: true,
                style: style,
                scale: scale
            )
        }
        .buttonStyle(.plain)
        .focusable(PickerCellFocusPolicy.allowsNativeFocus)
        .contentShape(Rectangle())
        .onHover { isHovered in
            guard isHovered, appState.isPickerVisible else { return }
            appState.focusedBrowserIndex = index
        }
        .contextMenu {
            if let app = item.app {
                Button {
                    pickerCoordinator?.openURL(with: app, windowTarget: item.windowTarget, state: appState)
                } label: {
                    Text("\(String(localized: "Open in")) \(item.displayName)")
                }
            } else if let browser = item.browser {
                Button(String(localized: "Open")) {
                    pickerCoordinator?.openURL(
                        with: browser,
                        mode: .normal,
                        profile: item.profile,
                        windowTarget: item.windowTarget,
                        state: appState
                    )
                }
                if item.windowTarget == nil, browser.supportsPrivateMode {
                    Button(String(localized: "Open Private")) {
                        pickerCoordinator?.openURL(with: browser, mode: .privateMode, profile: item.profile, state: appState)
                    }
                }
                if item.windowTarget == nil, item.profile == nil && hasVisibleProfiles {
                    Divider()
                    Menu(String(localized: "Open with Profile")) {
                        ForEach(browser.profiles.filter(\.isVisible)) { profile in
                            Button {
                                pickerCoordinator?.openURL(with: browser, mode: .normal, profile: profile, state: appState)
                            } label: {
                                if let email = profile.email {
                                    Text("\(profile.displayName) (\(email))")
                                } else {
                                    Text(profile.displayName)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func compactHintBar(scale: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "option")
                .font(.system(size: 8 * scale, weight: .medium))
            Text("/")
                .font(.system(size: 9 * scale))
            Image(systemName: "shift")
                .font(.system(size: 8 * scale, weight: .medium))
            Text(String(localized: "+ key for private mode"))
                .font(.system(size: 9 * scale))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: PickerMetrics.hintHeight(scale: scale), alignment: .center)
    }

    private func handleItemTap(_ item: PickerItem) {
        switch PickerTapPolicy.action(
            for: item,
            isPickerVisible: appState.isPickerVisible,
            isManualPickerPresentation: appState.isManualPickerPresentation
        ) {
        case .ignore:
            break
        case .open:
            open(item)
        }
    }

    private func open(_ item: PickerItem) {
        if let app = item.app {
            pickerCoordinator?.openURL(with: app, windowTarget: item.windowTarget, state: appState)
        } else if let profile = item.profile, let browser = item.browser {
            pickerCoordinator?.openURL(with: browser, mode: .normal, profile: profile, state: appState)
        } else if let browser = item.browser, item.windowTarget != nil {
            pickerCoordinator?.openURL(
                with: browser,
                mode: .normal,
                windowTarget: item.windowTarget,
                state: appState
            )
        } else if let browser = item.browser {
            pickerCoordinator?.openURL(with: browser, mode: .normal, state: appState)
        }
    }

    private func scrollFocusedItemIntoView(proxy: ScrollViewProxy, items: [PickerItem]) {
        guard items.indices.contains(appState.focusedBrowserIndex) else { return }
        let itemID = items[appState.focusedBrowserIndex].id
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(itemID, anchor: .center)
        }
    }

    private func prepareInitialFocus(with items: [PickerItem]) {
        // A pre-warmed (hidden) panel also runs onAppear; it must not reset focus or seed a
        // stale URL-less snapshot that a later real presentation would then trust.
        guard appState.isPickerVisible else { return }
        appState.focusedBrowserIndex = 0
        if appState.pickerItemsSnapshot.isEmpty, !items.isEmpty {
            appState.pickerItemsSnapshot = items
        }
    }
}

// MARK: - URL Bar Container

/// Reads `pendingURL`/`pendingURLTitle` itself so that when the background title fetch lands and
/// mutates `pendingURLTitle`, SwiftUI's Observation only re-evaluates this small view rather than
/// the entire `PickerView` body (which owns the item grid).
private struct PickerURLBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        URLBar(
            url: appState.pendingURL,
            title: appState.pendingURLTitle,
            additionalCount: appState.pendingAdditionalURLs.count
        )
    }
}

// MARK: - Horizontal Wheel Support

private struct HorizontalWheelScrollBridge: NSViewRepresentable {
    func makeNSView(context _: Context) -> HorizontalWheelScrollBridgeView {
        HorizontalWheelScrollBridgeView()
    }

    func updateNSView(_ nsView: HorizontalWheelScrollBridgeView, context _: Context) {
        nsView.refreshScrollView()
    }
}

private final class HorizontalWheelScrollBridgeView: NSView {
    private weak var scrollView: NSScrollView?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshScrollView()
        installMonitor()
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    deinit {
        removeMonitor()
    }

    func refreshScrollView() {
        DispatchQueue.main.async { [weak self] in
            self?.scrollView = self?.firstSuperview(of: NSScrollView.self)
        }
    }

    private func installMonitor() {
        removeMonitor()
        guard window != nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollWheel(event) ?? event
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window else { return event }
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
        guard let scrollView = scrollView ?? firstSuperview(of: NSScrollView.self),
              let documentView = scrollView.documentView
        else {
            return event
        }

        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return event }

        let visibleWidth = scrollView.contentView.bounds.width
        let maxX = max(0, documentView.bounds.width - visibleWidth)
        guard maxX > 1 else { return event }

        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
        let deltaX = -event.scrollingDeltaY * multiplier
        let current = scrollView.contentView.bounds.origin
        let nextX = min(max(current.x + deltaX, 0), maxX)
        guard nextX != current.x else { return event }

        scrollView.contentView.scroll(to: NSPoint(x: nextX, y: current.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return nil
    }
}

private extension NSView {
    func firstSuperview<T: NSView>(of _: T.Type) -> T? {
        var view = superview
        while let current = view {
            if let match = current as? T {
                return match
            }
            view = current.superview
        }
        return nil
    }
}

// MARK: - Picker Cell (supports both browsers and apps)

struct PickerCell: View {
    let item: PickerItem
    let isFocused: Bool
    let shortcut: PickerShortcut?
    var compact: Bool = false
    var style: PickerPresentationStyle = .routing
    var scale: CGFloat = 1

    var body: some View {
        if let browser = item.browser {
            BrowserCell(
                browser: browser,
                title: item.displayName,
                subtitle: style == .appSwitcher || item.windowTarget == nil ? nil : item.secondaryDisplayName,
                isFocused: isFocused,
                profile: item.profile,
                shortcut: shortcut,
                showsHotkey: false,
                showsProfileMenuIndicator: false,
                compact: compact,
                style: style,
                scale: scale
            )
        } else if let app = item.app {
            AppCell(
                app: app,
                title: item.displayName,
                subtitle: style == .appSwitcher ? nil : item.secondaryDisplayName,
                isFocused: isFocused,
                shortcut: shortcut,
                compact: compact,
                style: style,
                scale: scale
            )
        }
    }
}

// MARK: - App Cell

struct AppCell: View {
    let app: InstalledApp
    let title: String
    let subtitle: String?
    let isFocused: Bool
    let shortcut: PickerShortcut?
    var compact: Bool = false
    var style: PickerPresentationStyle = .routing
    var scale: CGFloat = 1

    init(
        app: InstalledApp,
        title: String? = nil,
        subtitle: String? = nil,
        isFocused: Bool,
        shortcut: PickerShortcut? = nil,
        compact: Bool = false,
        style: PickerPresentationStyle = .routing,
        scale: CGFloat = 1
    ) {
        self.app = app
        self.title = title ?? app.displayName
        self.subtitle = subtitle
        self.isFocused = isFocused
        self.shortcut = shortcut
        self.compact = compact
        self.style = style
        self.scale = scale
    }

    var body: some View {
        if compact {
            compactBody
        } else {
            normalBody
        }
    }

    private var compactBody: some View {
        let compactIconSize = PickerMetrics.iconSize(scale: scale)
        let compactIconChromeSize = PickerMetrics.iconChromeSize(scale: scale)
        let compactFallbackIconSize = PickerMetrics.fallbackIconSize(scale: scale)
        let compactCellWidth = PickerMetrics.itemWidth(scale: scale)
        let compactCellHeight = PickerMetrics.itemHeight(scale: scale)
        let focusCornerRadius = PickerMetrics.focusCornerRadius(scale: scale)
        let showsSecondaryRow = shortcut != nil || subtitle?.isEmpty == false

        return VStack(spacing: PickerMetrics.shortcutVerticalGap(scale: scale)) {
            ZStack {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: compactIconSize, height: compactIconSize)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: compactFallbackIconSize))
                        .frame(width: compactIconSize, height: compactIconSize)
                }
            }
            .frame(width: compactIconSize, height: compactIconSize)
            .frame(width: compactIconChromeSize, height: compactIconChromeSize)
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: focusCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: focusCornerRadius, style: .continuous)
                        .fill(Color("BrandAccentDeep").opacity(0.18))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: focusCornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color("BrandAccentDeep") : Color.clear,
                        lineWidth: PickerMetrics.focusStrokeWidth(scale: scale)
                    )
            )
            .shadow(
                color: isFocused ? Color("BrandAccentDeep").opacity(0.24) : .clear,
                radius: 12 * scale,
                y: 5 * scale
            )

            Text(title)
                .font(.system(size: PickerMetrics.titleFontSize(scale: scale), weight: .medium))
                .foregroundStyle(isFocused ? .primary : .secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
                .frame(width: compactCellWidth, height: PickerMetrics.titleHeight(scale: scale), alignment: .center)

            if showsSecondaryRow {
                HStack(spacing: 4 * scale) {
                    if let shortcut {
                        SelectionKeycapView(key: shortcut.key, compact: true, inline: true, scale: scale)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: PickerMetrics.subtitleFontSize(scale: scale), weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .truncationMode(.tail)
                    }
                }
                .frame(width: compactCellWidth, height: PickerMetrics.subtitleHeight(scale: scale), alignment: .center)
            }
        }
        .frame(width: compactCellWidth, height: compactCellHeight)
        .contentShape(Rectangle())
        .help(subtitle.map { "\(title) · \($0)" } ?? title)
    }

    private var normalBody: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 32))
                        .frame(width: 40, height: 40)
                }

            }

            Text(title)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: 72, height: 78)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topLeading) {
            if let shortcut {
                SelectionKeycapView(key: shortcut.key)
                    .offset(x: -8, y: -8)
                    .zIndex(2)
            }
        }
        .contentShape(Rectangle())
    }
}
