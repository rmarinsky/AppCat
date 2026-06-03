import SwiftUI

/// A picker grid item: a browser, browser+profile, or native app.
struct PickerItem: Identifiable {
    let id: String
    let browser: InstalledBrowser?
    let profile: BrowserProfile? // nil = plain browser entry
    let app: InstalledApp?

    var isBrowser: Bool { browser != nil }
    var isApp: Bool { app != nil }

    var displayName: String {
        if let profile { return profile.displayName }
        if let browser { return browser.displayName }
        if let app { return app.displayName }
        return ""
    }

    var icon: NSImage? {
        browser?.icon ?? app?.icon
    }

    var hotkey: Character? {
        profile?.hotkey ?? browser?.hotkey ?? app?.hotkey
    }

    var hotkeyKeyCode: UInt16? {
        profile?.hotkeyKeyCode ?? browser?.hotkeyKeyCode ?? app?.hotkeyKeyCode
    }

    init(browser: InstalledBrowser) {
        self.id = browser.id
        self.browser = browser
        self.profile = nil
        self.app = nil
    }

    init(browser: InstalledBrowser, profile: BrowserProfile) {
        self.id = "\(browser.id):\(profile.directoryName)"
        self.browser = browser
        self.profile = profile
        self.app = nil
    }

    init(app: InstalledApp) {
        self.id = "app:\(app.id)"
        self.browser = nil
        self.profile = nil
        self.app = app
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
        prioritizedAppIDs: Set<String> = []
    ) -> [PickerItem] {
        var all: [PickerItem] = apps.map { PickerItem(app: $0) }

        for browser in browsers {
            let visibleProfiles = browser.profiles.filter(\.isVisible)

            // If browser has enabled profiles, show only profiles in picker.
            if visibleProfiles.isEmpty, browser.isVisible {
                all.append(PickerItem(browser: browser))
            }

            for profile in visibleProfiles {
                all.append(PickerItem(browser: browser, profile: profile))
            }
        }

        let profileWithHotkey = all.filter { $0.profile != nil && $0.hotkey != nil }
        let otherWithHotkey = all.filter { $0.profile == nil && $0.hotkey != nil }
        let withoutHotkey = all.filter { $0.hotkey == nil }
        let ordered = profileWithHotkey + otherWithHotkey + withoutHotkey

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

    static func matchingApps(
        for url: URL?,
        in apps: [InstalledApp]
    ) -> [InstalledApp] {
        guard let url else { return [] }
        if url.isFileURL {
            return InstalledApp.matchingFileApps(for: url, in: apps)
        }
        return apps.filter { $0.matchesHost(of: url) }
    }

    static func matchingBrowsers(for url: URL?, in browsers: [InstalledBrowser]) -> [InstalledBrowser] {
        guard let url else { return browsers }
        guard url.isFileURL else { return browsers }
        return BrowserFileType.isBrowserReadableFile(url) ? browsers : []
    }
}

struct PickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.pickerCoordinator) private var pickerCoordinator

    @State private var hoveredIndex: Int?
    @State private var profilePopoverBrowserID: String?

    private var browsers: [InstalledBrowser] {
        PickerItem.matchingBrowsers(for: appState.pendingURL, in: appState.pickerBrowsers)
    }

    /// Only apps that match the pending URL's host or local file type.
    private var matchingApps: [InstalledApp] {
        PickerItem.matchingApps(
            for: appState.pendingURL,
            in: appState.visibleApps
        )
    }

    private var prioritizedAppIDs: Set<String> {
        Set(matchingApps.map(\.id))
    }

    private var pickerItems: [PickerItem] {
        PickerItem.buildItems(
            browsers: browsers,
            apps: matchingApps,
            prioritizedAppIDs: prioritizedAppIDs
        )
    }

    var body: some View {
        if appState.compactPickerView {
            compactBody
        } else {
            normalBody
        }
    }

    private var normalBody: some View {
        VStack(spacing: 0) {
            // URL bar
            URLBar(
                url: appState.pendingURL,
                title: appState.pendingURLTitle,
                additionalCount: appState.pendingAdditionalURLs.count
            )
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 8)

            // Browser grid
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 72, maximum: 80))],
                    spacing: 8
                ) {
                    ForEach(Array(pickerItems.enumerated()), id: \.element.id) { index, item in
                        pickerCell(item: item, index: index)
                    }
                }
                .padding(12)
            }

            if appState.pendingURL?.isFileURL != true {
                hintBar
            }
        }
        .frame(minWidth: 380, maxWidth: 380, minHeight: 120, idealHeight: 300, maxHeight: 400)
        .onAppear {
            appState.focusedBrowserIndex = 0
        }
    }

    private var compactBody: some View {
        VStack(spacing: 0) {
            // Single row of compact cells only
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(pickerItems.enumerated()), id: \.element.id) { index, item in
                        pickerCell(item: item, index: index, compact: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            if appState.pendingURL?.isFileURL != true {
                hintBar
            }
        }
        .onAppear {
            appState.focusedBrowserIndex = 0
        }
    }

    @ViewBuilder
    private func pickerCell(item: PickerItem, index: Int, compact: Bool = false) -> some View {
        let hasVisibleProfiles = item.browser?.profiles.contains(where: \.isVisible) == true

        PickerCell(item: item, isFocused: appState.focusedBrowserIndex == index || hoveredIndex == index, compact: compact)
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
                        pickerCoordinator?.openURL(with: app, state: appState)
                    } label: {
                        Text("\(String(localized: "Open in")) \(app.displayName)")
                    }
                } else if let browser = item.browser {
                    Button("Open") {
                        pickerCoordinator?.openURL(with: browser, mode: .normal, profile: item.profile, state: appState)
                    }
                    if browser.supportsPrivateMode {
                        Button("Open Private") {
                            pickerCoordinator?.openURL(with: browser, mode: .privateMode, profile: item.profile, state: appState)
                        }
                    }
                    if item.profile == nil && hasVisibleProfiles {
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

    private var hintBar: some View {
        Group {
            Divider()
                .padding(.horizontal, 8)

            HStack(spacing: 4) {
                Image(systemName: "option")
                    .font(.system(size: 9, weight: .medium))
                Text("/")
                    .font(.system(size: 10))
                Image(systemName: "shift")
                    .font(.system(size: 9, weight: .medium))
                Text("+ key for private mode")
                    .font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
        }
    }

    private func handleItemTap(_ item: PickerItem) {
        if let app = item.app {
            pickerCoordinator?.openURL(with: app, state: appState)
        } else if let profile = item.profile, let browser = item.browser {
            pickerCoordinator?.openURL(with: browser, mode: .normal, profile: profile, state: appState)
        } else if let browser = item.browser, browser.profiles.contains(where: \.isVisible) {
            profilePopoverBrowserID = browser.id
        } else if let browser = item.browser {
            pickerCoordinator?.openURL(with: browser, mode: .normal, state: appState)
        }
    }
}

// MARK: - Picker Cell (supports both browsers and apps)

struct PickerCell: View {
    let item: PickerItem
    let isFocused: Bool
    var compact: Bool = false

    var body: some View {
        if let browser = item.browser {
            BrowserCell(browser: browser, isFocused: isFocused, profile: item.profile, compact: compact)
        } else if let app = item.app {
            AppCell(app: app, isFocused: isFocused, compact: compact)
        }
    }
}

// MARK: - App Cell

struct AppCell: View {
    let app: InstalledApp
    let isFocused: Bool
    var compact: Bool = false

    var body: some View {
        if compact {
            compactBody
        } else {
            normalBody
        }
    }

    private var compactBody: some View {
        let compactIconSize: CGFloat = 84
        let compactFallbackIconSize: CGFloat = 58
        let compactCellSize: CGFloat = 98

        return ZStack(alignment: .topTrailing) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: compactIconSize, height: compactIconSize)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: compactFallbackIconSize))
                    .frame(width: compactIconSize, height: compactIconSize)
            }

            // Hotkey badge
            if let hotkey = app.hotkey {
                HotkeyKeycapView(hotkey: hotkey, compact: true)
                    .offset(x: 4, y: -4)
            }
        }
        .frame(width: compactCellSize, height: compactCellSize)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
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

                // Hotkey badge
                if let hotkey = app.hotkey {
                    HotkeyKeycapView(hotkey: hotkey)
                        .offset(x: 4, y: -4)
                }
            }

            Text(app.displayName)
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
        .contentShape(Rectangle())
    }
}
