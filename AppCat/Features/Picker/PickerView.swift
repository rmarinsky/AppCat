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
        browser?.icon ?? app?.icon
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
        return apps.filter { $0.isVisible && $0.matchesHost(of: url) }
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
        showWindowlessApps: Bool = true,
        showBackgroundApps: Bool = false
    ) -> [PickerItem] {
        let browsers = matchingBrowsers(for: url, in: pickerBrowsers)
        let browserIDs = Set(allBrowsers.map(\.id))
        if url == nil {
            let runningBundleIDs = providedRunningBundleIDs ?? Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let windowsByAppID = providedWindowsByAppID ?? WindowEnumerator.runningWindows()
            return switcherItems(
                apps: apps,
                browsers: browsers,
                allBrowsers: allBrowsers,
                browserIDs: browserIDs,
                runningBundleIDs: runningBundleIDs,
                regularBundleIDs: regularBundleIDs,
                windowsByAppID: windowsByAppID,
                activations: activations,
                showWindowlessApps: showWindowlessApps,
                showBackgroundApps: showBackgroundApps
            )
        }

        let matchingApps = matchingApps(
            for: url,
            in: apps,
            excludingBundleIDs: browserIDs,
            includingLaunchServicesCandidates: true
        )
        let orderedApps: [InstalledApp]
        if url?.isFileURL == true {
            orderedApps = matchingApps
        } else {
            orderedApps = matchingApps.sorted { lhs, rhs in
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
        )
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
                items: browserSwitcherItems(for: browser, windows: windows)
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
                items: appSwitcherItems(for: app, windows: windows)
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
                items: items
            ))
        }

        // Most-used first, recency as tiebreak, then name for a stable order among never-used apps.
        func before(_ x: Entry, _ y: Entry) -> Bool {
            let rx = activations[x.id], ry = activations[y.id]
            let cx = rx?.count ?? 0, cy = ry?.count ?? 0
            if cx != cy { return cx > cy }
            let dx = rx?.lastUsed ?? .distantPast, dy = ry?.lastUsed ?? .distantPast
            if dx != dy { return dx > dy }
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

    private static func appSwitcherItems(for app: InstalledApp, windows: [AppWindowTarget]) -> [PickerItem] {
        guard windows.count >= 2 else { return [PickerItem(app: app)] }
        return windows.map { PickerItem(app: app, windowTarget: $0) }
    }

    private static func browserSwitcherItems(for browser: InstalledBrowser, windows: [AppWindowTarget]) -> [PickerItem] {
        guard windows.count >= 2 else {
            return browser.isVisible ? [PickerItem(browser: browser)] : buildItems(browsers: [browser], apps: [])
        }
        return windows.map { PickerItem(browser: browser, windowTarget: $0) }
    }
}

enum PickerPresentationStyle {
    case routing
    case appSwitcher
}

enum PickerMetrics {
    static let screenMargin: CGFloat = 8

    static func iconSize(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 84 : 56
    }

    static func fallbackIconSize(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 60 : 40
    }

    static func itemWidth(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 100 : 72
    }

    static func itemHeight(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 136 : 94
    }

    static func itemSpacing(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 2 : 2
    }

    static func horizontalPadding(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 24 : 10
    }

    static func scrollHeight(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 150 : 100
    }

    static func topPadding(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 12 : 4
    }

    static func titleFontSize(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 13 : 11
    }

    static func titleHeight(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 17 : 15
    }

    static func subtitleFontSize(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 11 : 10
    }

    static func subtitleHeight(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 19 : 17
    }

    static func focusStrokeWidth(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 3 : 2.25
    }

    static func focusCornerRadius(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 20 : 12
    }

    static func panelCornerRadius(for style: PickerPresentationStyle = .routing) -> CGFloat {
        style == .appSwitcher ? 24 : 16
    }

    static func panelHeight(showsHint: Bool, style: PickerPresentationStyle = .routing) -> CGFloat {
        if style == .appSwitcher { return 162 }
        return showsHint ? 120 : 104
    }

    static func contentWidth(itemCount: Int, style: PickerPresentationStyle = .routing) -> CGFloat {
        let count = max(1, itemCount)
        return horizontalPadding(for: style) * 2
            + CGFloat(count) * itemWidth(for: style)
            + CGFloat(max(0, count - 1)) * itemSpacing(for: style)
    }

    static func panelWidth(
        itemCount: Int,
        availableWidth: CGFloat,
        style: PickerPresentationStyle = .routing
    ) -> CGFloat {
        let minPanelWidth = horizontalPadding(for: style) * 2 + itemWidth(for: style)
        let maxWidth = max(minPanelWidth, availableWidth - screenMargin * 2)
        return min(max(contentWidth(itemCount: itemCount, style: style), minPanelWidth), maxWidth)
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

struct PickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.pickerCoordinator) private var pickerCoordinator

    @State private var hoveredIndex: Int?
    @State private var profilePopoverBrowserID: String?

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
            showWindowlessApps: appState.showWindowlessApps,
            showBackgroundApps: appState.showBackgroundApps
        )
    }

    var body: some View {
        horizontalBody
    }

    private var horizontalBody: some View {
        let items = pickerItems
        let style = presentationStyle
        let shortcuts = PickerShortcutAssigner.assignments(
            for: items,
            positionalEnabled: appState.selectWithNumberKeys
        )
        let showsHint = style == .routing && appState.pendingURL != nil && appState.pendingURL?.isFileURL != true
        let panelHeight = PickerMetrics.panelHeight(showsHint: showsHint, style: style)

        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                // Lazy rendering matters here: file pickers can include many LaunchServices apps.
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: PickerMetrics.itemSpacing(for: style)) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if style == .appSwitcher, index > 0,
                               item.isBackgroundRunning, !items[index - 1].isBackgroundRunning
                            {
                                switcherGroupDivider
                            }
                            pickerCell(
                                item: item,
                                index: index,
                                shortcut: shortcuts[item.id],
                                style: style
                            )
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, PickerMetrics.horizontalPadding(for: style))
                    .padding(.top, PickerMetrics.topPadding(for: style))
                    .padding(.bottom, 0)
                }
                .background(HorizontalWheelScrollBridge())
                .frame(height: PickerMetrics.scrollHeight(for: style))
                .onChange(of: appState.focusedBrowserIndex) { _, _ in
                    scrollFocusedItemIntoView(proxy: proxy, items: items)
                }
            }

            if showsHint {
                compactHintBar
            }
        }
        .onAppear {
            prepareInitialFocus(with: items)
        }
        .frame(maxWidth: .infinity, minHeight: panelHeight, maxHeight: panelHeight, alignment: .top)
    }

    @ViewBuilder
    private func pickerCell(
        item: PickerItem,
        index: Int,
        shortcut: PickerShortcut?,
        style: PickerPresentationStyle = .routing
    ) -> some View {
        let hasVisibleProfiles = item.browser?.profiles.contains(where: \.isVisible) == true
        let isFocused = appState.focusedBrowserIndex == index || hoveredIndex == index

        PickerCell(
            item: item,
            isFocused: isFocused,
            shortcut: shortcut,
            compact: true,
            style: style
        )
        // Dim running-but-windowless apps so the eye lands on the active desktops first; a focused
        // or hovered tile returns to full strength.
        .opacity(item.isBackgroundRunning && style == .appSwitcher && !isFocused ? 0.5 : 1)
        .onTapGesture {
            handleItemTap(item)
        }
        .popover(isPresented: Binding(
            get: { item.browser != nil && item.profile == nil && hasVisibleProfiles && profilePopoverBrowserID == item.browser?.id },
            set: { if !$0 { profilePopoverBrowserID = nil } }
        )) {
            if let browser = item.browser {
                ProfilePopover(browser: browser) { profile in
                    profilePopoverBrowserID = nil
                    pickerCoordinator?.openURL(with: browser, mode: .normal, profile: profile, state: appState)
                }
            }
        }
        .onHover { isHovered in
            hoveredIndex = isHovered ? index : nil
        }
        .contextMenu {
            if let app = item.app {
                Button {
                    pickerCoordinator?.openURL(with: app, windowTarget: item.windowTarget, state: appState)
                } label: {
                    Text("\(String(localized: "Open in")) \(item.displayName)")
                }
            } else if let browser = item.browser {
                Button("Open") {
                    pickerCoordinator?.openURL(
                        with: browser,
                        mode: .normal,
                        profile: item.profile,
                        windowTarget: item.windowTarget,
                        state: appState
                    )
                }
                if item.windowTarget == nil, browser.supportsPrivateMode {
                    Button("Open Private") {
                        pickerCoordinator?.openURL(with: browser, mode: .privateMode, profile: item.profile, state: appState)
                    }
                }
                if item.windowTarget == nil, item.profile == nil && hasVisibleProfiles {
                    Divider()
                    Menu("Open with Profile") {
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

    /// Separates the "has open windows" group from the dimmed "running, no windows" group.
    private var switcherGroupDivider: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.primary.opacity(0.14))
            .frame(width: 1, height: 92)
            .padding(.horizontal, 9)
    }

    private var compactHintBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "option")
                .font(.system(size: 8, weight: .medium))
            Text("/")
                .font(.system(size: 9))
            Image(systemName: "shift")
                .font(.system(size: 8, weight: .medium))
            Text("+ key for private mode")
                .font(.system(size: 9))
        }
        .foregroundStyle(.secondary)
        .padding(.top, 0)
        .padding(.bottom, 6)
    }

    private func handleItemTap(_ item: PickerItem) {
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
        } else if let browser = item.browser, browser.profiles.contains(where: \.isVisible) {
            profilePopoverBrowserID = browser.id
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

    var body: some View {
        if let browser = item.browser {
            BrowserCell(
                browser: browser,
                title: item.displayName,
                subtitle: item.windowTarget == nil ? nil : item.secondaryDisplayName,
                isFocused: isFocused,
                profile: item.profile,
                shortcut: shortcut,
                showsHotkey: false,
                compact: compact,
                style: style
            )
        } else if let app = item.app {
            AppCell(
                app: app,
                title: item.displayName,
                subtitle: item.secondaryDisplayName,
                isFocused: isFocused,
                shortcut: shortcut,
                compact: compact,
                style: style
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

    init(
        app: InstalledApp,
        title: String? = nil,
        subtitle: String? = nil,
        isFocused: Bool,
        shortcut: PickerShortcut? = nil,
        compact: Bool = false,
        style: PickerPresentationStyle = .routing
    ) {
        self.app = app
        self.title = title ?? app.displayName
        self.subtitle = subtitle
        self.isFocused = isFocused
        self.shortcut = shortcut
        self.compact = compact
        self.style = style
    }

    var body: some View {
        if compact {
            compactBody
        } else {
            normalBody
        }
    }

    private var compactBody: some View {
        let compactIconSize = PickerMetrics.iconSize(for: style)
        let compactFallbackIconSize = PickerMetrics.fallbackIconSize(for: style)
        let compactCellWidth = PickerMetrics.itemWidth(for: style)
        let compactCellHeight = PickerMetrics.itemHeight(for: style)
        let focusCornerRadius = PickerMetrics.focusCornerRadius(for: style)

        return VStack(spacing: 2) {
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
            .background {
                if isFocused {
                    RoundedRectangle(cornerRadius: focusCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: focusCornerRadius, style: .continuous)
                        .fill(Color("BrandAccentDeep").opacity(style == .appSwitcher ? 0.18 : 0.14))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: focusCornerRadius, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color("BrandAccentDeep") : Color.clear,
                        lineWidth: PickerMetrics.focusStrokeWidth(for: style)
                    )
            )
            .shadow(
                color: isFocused ? Color("BrandAccentDeep").opacity(style == .appSwitcher ? 0.24 : 0.12) : .clear,
                radius: style == .appSwitcher ? 12 : 5,
                y: style == .appSwitcher ? 5 : 2
            )

            Text(title)
                .font(.system(size: PickerMetrics.titleFontSize(for: style), weight: .medium))
                .foregroundStyle(isFocused ? .primary : .secondary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
                .frame(width: compactCellWidth, height: PickerMetrics.titleHeight(for: style), alignment: .center)

            if let subtitle {
                HStack(spacing: 4) {
                    if let shortcut {
                        SelectionKeycapView(key: shortcut.key, compact: true, inline: true)
                    }

                    Text(subtitle)
                        .font(.system(size: PickerMetrics.subtitleFontSize(for: style), weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .truncationMode(.tail)
                }
                .frame(width: compactCellWidth, height: PickerMetrics.subtitleHeight(for: style), alignment: .center)
            } else {
                HStack(spacing: 4) {
                    if let shortcut {
                        SelectionKeycapView(key: shortcut.key, compact: true, inline: true)
                    }
                }
                .frame(width: compactCellWidth, height: PickerMetrics.subtitleHeight(for: style), alignment: .center)
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
