import SwiftUI

struct AppsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.browserManager) private var browserManager
    @Environment(\.appManager) private var appManager

    @State private var hotkeyTarget: HotkeyTarget?
    @State private var showIgnored: Bool = false
    @State private var clearedTarget: HotkeyTarget?

    private enum Layout {
        static let rowHorizontalPadding: CGFloat = 16
        static let browserIconSize: CGFloat = 32
        static let browserRowSpacing: CGFloat = 12
        static let profileRowSpacing: CGFloat = 8

        // Profile row starts one icon-column deeper than browser row.
        static let profileIndent: CGFloat = browserIconSize
        static var profileDividerLeading: CGFloat {
            rowHorizontalPadding + browserIconSize + profileRowSpacing
        }
    }

    private var activeBrowsers: [InstalledBrowser] {
        appState.browsers.filter { !$0.isIgnored }
    }

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(activeBrowsers) { browser in
                    if let index = state.browsers.firstIndex(where: { $0.id == browser.id }) {
                        VStack(spacing: 0) {
                            browserRow(browser: browser, index: index)
                                .padding(.horizontal, Layout.rowHorizontalPadding)
                                .padding(.vertical, 10)

                            // Profiles
                            if browser.hasProfiles {
                                ForEach(Array(browser.profiles.enumerated()), id: \.element.id) { profileIdx, profile in
                                    Divider()
                                        .padding(.leading, Layout.profileDividerLeading)

                                    profileRow(
                                        profile: profile,
                                        browserIndex: index,
                                        profileIndex: profileIdx
                                    )
                                    .padding(.leading, Layout.profileIndent)
                                    .padding(.horizontal, Layout.rowHorizontalPadding)
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                        )
                        .contextMenu {
                            Button("Ignore") {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    state.browsers[index].isIgnored = true
                                    browserManager?.save(state.browsers)
                                }
                            }
                        }

                        Divider()
                    }
                }

                // Ignored section
                if !state.ignoredBrowsers.isEmpty {
                    Divider()

                    DisclosureGroup(isExpanded: $showIgnored) {
                        VStack(spacing: 0) {
                            ForEach(state.ignoredBrowsers) { browser in
                                HStack(spacing: 12) {
                                    if let icon = browser.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 22, height: 22)
                                    } else {
                                        Image(systemName: "globe")
                                            .font(.system(size: 16))
                                            .frame(width: 22, height: 22)
                                    }

                                    Text(browser.displayName)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Button("Restore") {
                                        if let idx = state.browsers.firstIndex(where: { $0.id == browser.id }) {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                                state.browsers[idx].isIgnored = false
                                                browserManager?.save(state.browsers)
                                            }
                                        }
                                    }
                                    .controlSize(.small)
                                }
                                .padding(.vertical, 4)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                        .padding(.horizontal, 16)
                    } label: {
                        Text("\(String(localized: "Ignored")) (\(state.ignoredBrowsers.count))")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showIgnored)
                }

                // Native Apps section
                if !state.apps.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Native Apps")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Shown for matching links and files")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        ForEach(state.apps) { app in
                            if let appIndex = state.apps.firstIndex(where: { $0.id == app.id }) {
                                HStack(spacing: 12) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 32, height: 32)
                                    } else {
                                        Image(systemName: "app.fill")
                                            .font(.system(size: 24))
                                            .frame(width: 32, height: 32)
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.displayName)
                                            .font(.system(size: 13, weight: .medium))
                                        if let version = app.version {
                                            Text(version)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    // Hotkey
                                    hotkeyButton(
                                        hotkey: app.hotkey,
                                        target: .app(id: app.id)
                                    )

                                    // Visibility toggle
                                    Toggle("", isOn: Binding(
                                        get: { app.isVisible },
                                        set: { newValue in
                                            appState.apps[appIndex].isVisible = newValue
                                            appManager?.save(appState.apps)
                                        }
                                    ))
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .labelsHidden()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)

                                Divider()
                            }
                        }
                    }
                }

            }
        }

            Divider()

            HStack {
                Button {
                    browserManager?.refreshBrowsers(into: appState)
                    appManager?.refreshApps(into: appState)
                } label: {
                    Label("Rescan Apps", systemImage: "arrow.clockwise")
                }

                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: - Browser Row

    @ViewBuilder
    private func browserRow(browser: InstalledBrowser, index: Int) -> some View {
        HStack(spacing: Layout.browserRowSpacing) {
            if let icon = browser.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: Layout.browserIconSize, height: Layout.browserIconSize)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 24))
                    .frame(width: Layout.browserIconSize, height: Layout.browserIconSize)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(browser.displayName)
                    .font(.system(size: 13, weight: .medium))
                if let version = browser.version {
                    Text(version)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            hotkeyButton(
                hotkey: browser.hotkey,
                target: .browser(id: browser.id)
            )

            Toggle("", isOn: Binding(
                get: { browser.isVisible },
                set: { newValue in
                    setBrowserVisibility(newValue, at: index)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
    }

    // MARK: - Profile Row

    @ViewBuilder
    private func profileRow(profile: BrowserProfile, browserIndex: Int, profileIndex: Int) -> some View {
        HStack(spacing: Layout.profileRowSpacing) {
            profileAvatar(for: profile)

            VStack(alignment: .leading, spacing: 0) {
                Text(profile.displayName)
                    .font(.system(size: 11))
                if let email = profile.email {
                    Text(email)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            hotkeyButton(
                hotkey: profile.hotkey,
                target: .profile(browserId: appState.browsers[browserIndex].id, directoryName: profile.directoryName)
            )

            Toggle("", isOn: Binding(
                get: { profile.isVisible },
                set: { newValue in
                    appState.browsers[browserIndex].profiles[profileIndex].isVisible = newValue
                    browserManager?.save(appState.browsers)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
    }

    // MARK: - Hotkey Button

    @ViewBuilder
    private func hotkeyButton(hotkey: Character?, target: HotkeyTarget) -> some View {
        let isCleared = clearedTarget == target

        Button {
            hotkeyTarget = target
        } label: {
            Text(hotkey != nil ? String(hotkey!).uppercased() : String(localized: "SET KEY"))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(hotkey != nil ? .primary : .tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 72)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isCleared ? Color.orange : Color.secondary.opacity(0.25),
                            lineWidth: isCleared ? 1.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .help(isCleared ? String(localized: "Key was already in use and has been reassigned") : "")
        .popover(isPresented: Binding(
            get: { hotkeyTarget == target },
            set: { if !$0 { hotkeyTarget = nil } }
        )) {
            HotkeyRecorder { result in
                handleHotkeyRecord(result, target: target)
            }
        }
    }

    private func handleHotkeyRecord(_ result: HotkeyRecorder.Result, target: HotkeyTarget) {
        switch result {
        case let .set(key, keyCode):
            applyHotkey(key: key, keyCode: keyCode, target: target)
            hotkeyTarget = nil
        case .clear:
            clearHotkey(target: target)
            hotkeyTarget = nil
        case .cancel:
            hotkeyTarget = nil
        }
    }

    private func applyHotkey(key: Character, keyCode: UInt16, target: HotkeyTarget) {
        clearDuplicateHotkey(keyCode, excludingTarget: target)

        switch target {
        case let .app(id):
            if let aIdx = appState.apps.firstIndex(where: { $0.id == id }) {
                appState.apps[aIdx].hotkey = key
                appState.apps[aIdx].hotkeyKeyCode = keyCode
            }
            appManager?.save(appState.apps)

        case let .browser(id):
            if let bIdx = appState.browsers.firstIndex(where: { $0.id == id }) {
                appState.browsers[bIdx].hotkey = key
                appState.browsers[bIdx].hotkeyKeyCode = keyCode
            }
            browserManager?.save(appState.browsers)

        case let .profile(browserId, directoryName):
            if let bIdx = appState.browsers.firstIndex(where: { $0.id == browserId }),
               let pIdx = appState.browsers[bIdx].profiles.firstIndex(where: { $0.directoryName == directoryName })
            {
                appState.browsers[bIdx].profiles[pIdx].hotkey = key
                appState.browsers[bIdx].profiles[pIdx].hotkeyKeyCode = keyCode
            }
            browserManager?.save(appState.browsers)
        }
    }

    private func clearHotkey(target: HotkeyTarget) {
        switch target {
        case let .app(id):
            if let aIdx = appState.apps.firstIndex(where: { $0.id == id }) {
                appState.apps[aIdx].hotkey = nil
                appState.apps[aIdx].hotkeyKeyCode = nil
            }
            appManager?.save(appState.apps)

        case let .browser(id):
            if let bIdx = appState.browsers.firstIndex(where: { $0.id == id }) {
                appState.browsers[bIdx].hotkey = nil
                appState.browsers[bIdx].hotkeyKeyCode = nil
            }
            browserManager?.save(appState.browsers)

        case let .profile(browserId, directoryName):
            if let bIdx = appState.browsers.firstIndex(where: { $0.id == browserId }),
               let pIdx = appState.browsers[bIdx].profiles.firstIndex(where: { $0.directoryName == directoryName })
            {
                appState.browsers[bIdx].profiles[pIdx].hotkey = nil
                appState.browsers[bIdx].profiles[pIdx].hotkeyKeyCode = nil
            }
            browserManager?.save(appState.browsers)
        }
    }

    private func clearDuplicateHotkey(_ keyCode: UInt16, excludingTarget: HotkeyTarget) {
        // Check app hotkeys
        for aIdx in appState.apps.indices {
            let app = appState.apps[aIdx]
            let appTarget = HotkeyTarget.app(id: app.id)
            if app.hotkeyKeyCode == keyCode && appTarget != excludingTarget {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.apps[aIdx].hotkey = nil
                    appState.apps[aIdx].hotkeyKeyCode = nil
                    clearedTarget = appTarget
                }
                appManager?.save(appState.apps)
                scheduleClearedDismiss()
                return
            }
        }

        for bIdx in appState.browsers.indices {
            let browser = appState.browsers[bIdx]

            // Check browser-level hotkey
            let browserTarget = HotkeyTarget.browser(id: browser.id)
            if browser.hotkeyKeyCode == keyCode && browserTarget != excludingTarget {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.browsers[bIdx].hotkey = nil
                    appState.browsers[bIdx].hotkeyKeyCode = nil
                    clearedTarget = browserTarget
                }
                browserManager?.save(appState.browsers)
                scheduleClearedDismiss()
                return
            }

            // Check profile hotkeys
            for pIdx in browser.profiles.indices {
                let profile = browser.profiles[pIdx]
                let profileTarget = HotkeyTarget.profile(browserId: browser.id, directoryName: profile.directoryName)
                if profile.hotkeyKeyCode == keyCode && profileTarget != excludingTarget {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState.browsers[bIdx].profiles[pIdx].hotkey = nil
                        appState.browsers[bIdx].profiles[pIdx].hotkeyKeyCode = nil
                        clearedTarget = profileTarget
                    }
                    browserManager?.save(appState.browsers)
                    scheduleClearedDismiss()
                    return
                }
            }
        }
    }

    private func scheduleClearedDismiss() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.3)) {
                clearedTarget = nil
            }
        }
    }

    private func setBrowserVisibility(_ isVisible: Bool, at index: Int) {
        appState.browsers[index].isVisible = isVisible

        if !isVisible {
            for profileIndex in appState.browsers[index].profiles.indices {
                appState.browsers[index].profiles[profileIndex].isVisible = false
            }
        }

        browserManager?.save(appState.browsers)
    }

    // MARK: - Profile Avatar

    private func profileAvatar(for profile: BrowserProfile) -> some View {
        let initial = profile.displayName.first.map { String($0).uppercased() } ?? "?"
        return Text(initial)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color.profileAvatar(for: profile.displayName), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1))
    }
}
