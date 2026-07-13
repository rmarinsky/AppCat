import SwiftUI

/// Apps screen — the system-wide app navigator. Splits installed apps (top, most-used first)
/// from Apple/system apps (bottom, alphabetical). Each row shows the file formats an app opens
/// and an "Edit formats" button that opens the per-app format editor. The toggle controls
/// whether an app appears in the picker; open windows/projects surface while searching.
struct AppsScreenView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appManager) private var appManager

    @State private var search: String = ""
    @State private var windowsByApp: [String: [String]] = [:]
    @State private var editingApp: InstalledApp?
    @State private var editingHotkeyTarget: HotkeyTarget?

    private func windows(for app: InstalledApp) -> [String] {
        windowsByApp[app.id] ?? []
    }

    private func matchingWindows(for app: InstalledApp) -> [String] {
        let titles = windows(for: app)
        guard !search.isEmpty else { return titles }
        let q = search.lowercased()
        return titles.filter { $0.lowercased().contains(q) }
    }

    /// An app matches the search by name, by any file format it opens, or by an open window title.
    private func matches(_ app: InstalledApp, query q: String) -> Bool {
        app.displayName.lowercased().contains(q)
            || app.fileFormats.contains { $0.contains(q) }
            || windows(for: app).contains { $0.lowercased().contains(q) }
    }

    private var filteredInstalled: [InstalledApp] {
        guard !search.isEmpty else { return appState.installedApps }
        let q = search.lowercased()
        return appState.installedApps.filter { matches($0, query: q) }
    }

    private var filteredSystem: [InstalledApp] {
        guard !search.isEmpty else { return appState.systemApps }
        let q = search.lowercased()
        return appState.systemApps.filter { matches($0, query: q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                Text(String(localized: "Choose which apps open your files — and which formats each one handles."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                searchField

                if !WindowEnumerator.isTrusted {
                    accessibilityHint
                }

                if filteredInstalled.isEmpty, filteredSystem.isEmpty {
                    Text(emptyStateText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    if !filteredInstalled.isEmpty {
                        section(title: String(localized: "INSTALLED · MOST USED FIRST"), apps: filteredInstalled, showUsage: true)
                    }
                    if !filteredSystem.isEmpty {
                        section(title: String(localized: "APPLE & SYSTEM"), apps: filteredSystem, showUsage: false)
                    }
                    Text(String(localized: "System apps stay at the bottom. Toggle any app off to hide it from the picker."))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
        .onAppear { windowsByApp = WindowEnumerator.runningWindowTitles() }
        .sheet(item: $editingApp) { app in
            AppFormatEditorSheet(
                app: app,
                onSave: { customFormats, handlesAllFiles in
                    appState.updateAppFormats(
                        appID: app.id,
                        customFormats: customFormats,
                        handlesAllFiles: handlesAllFiles
                    )
                    editingApp = nil
                },
                onCancel: { editingApp = nil }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Spacer()
            #if DEBUG
                Menu {
                    Button(String(localized: "Picker handoff")) { testHandoff(.userPicked) }
                    Button(String(localized: "Rule handoff")) { testHandoff(.ruleMatched) }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color("AccentColor"))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "Preview the open-handoff animation"))
            #endif
            Button {
                windowsByApp = WindowEnumerator.runningWindowTitles()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Rescan open windows"))
        }
    }

    #if DEBUG
        /// Replays the Cat Pounce handoff overlay with the most-used app so the animation can be
        /// tuned without clicking real links. The overlay appears near the cursor.
        private func testHandoff(_ reason: HandoffReason) {
            let sample = appState.appsByFrequency.first
            HandoffOverlayController.shared.present(
                .init(
                    icon: sample?.icon,
                    destinationName: sample?.displayName ?? "Arc",
                    reason: reason
                ),
                locale: appState.appLanguage.locale
            )
        }
    #endif

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search apps or file formats"), text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("SurfaceInset"))
        )
    }

    private var accessibilityHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(Color("BrandAccentDeep"))
            Text(String(localized: "Grant Accessibility to see open windows & projects."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: "Open Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(Color("BrandAccentDeep"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("BrandTintSoft"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color("BrandTintBorder"), lineWidth: 1)
        )
    }

    private var emptyStateText: String {
        if search.isEmpty {
            return String(localized: "No apps detected.")
        }
        return String(format: String(localized: "No apps match %@."), search)
    }

    private func section(title: String, apps: [InstalledApp], showUsage: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.44)
                .foregroundStyle(.tertiary)
            card(apps: apps, showUsage: showUsage)
        }
    }

    private func card(apps: [InstalledApp], showUsage: Bool) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 {
                    Rectangle().fill(Color("HairlineBorder")).frame(height: 1)
                }
                appBlock(app, showUsage: showUsage)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func appBlock(_ app: InstalledApp, showUsage: Bool) -> some View {
        // Window/project sub-rows only surface while searching, so the default view stays
        // format-focused; the inline badge still shows the open-window count.
        let shownWindows = search.isEmpty ? [] : matchingWindows(for: app)

        VStack(spacing: 0) {
            row(app, showUsage: showUsage)
            ForEach(Array(shownWindows.prefix(8).enumerated()), id: \.offset) { _, title in
                windowRow(title)
            }
        }
    }

    private func row(_ app: InstalledApp, showUsage: Bool) -> some View {
        let count = appState.appUsage[app.id]?.count ?? 0
        let windowCount = windows(for: app).count
        return HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if windowCount >= 2 {
                        Text("\(windowCount) \(String(localized: "windows"))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color("SurfaceInset"))
                            )
                    }
                }
                formatSummary(app)
            }

            Spacer(minLength: 8)

            if showUsage, count > 0 {
                Text("\(String(localized: "used")) \(count)×")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            hotkeyButton(app) { result in
                handleAppHotkeyResult(result, appID: app.id)
            }

            Button { editingApp = app } label: {
                Text(String(localized: "Edit formats"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color("SurfaceInset"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help(String(localized: "Edit which file formats \(app.displayName) opens"))

            Toggle("", isOn: Binding(
                get: { app.isVisible },
                set: { setVisibility($0, appID: app.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
    }

    private func hotkeyButton(
        _ app: InstalledApp,
        onRecord: @escaping (HotkeyRecorder.Result) -> Void
    ) -> some View {
        let target = HotkeyTarget.app(id: app.id)
        return Button {
            editingHotkeyTarget = target
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "Shortcut"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if let key = app.hotkey {
                    SelectionKeycapView(key: key, compact: true, inline: true)
                } else {
                    Text(String(localized: "Set"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color("SurfaceSidebar"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(String(localized: "Set the key used to open \(app.displayName) in the picker"))
        .popover(isPresented: isEditingHotkey(target), arrowEdge: .bottom) {
            HotkeyRecorder { result in
                onRecord(result)
            }
        }
    }

    /// One-line "txt · md · json · ts · py · swift  +12" summary, or a fallback when the app
    /// declares no concrete formats.
    @ViewBuilder
    private func formatSummary(_ app: InstalledApp) -> some View {
        let formats = app.fileFormats
        if app.handlesAllFiles {
            Text(String(localized: "Any file type"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else if formats.isEmpty {
            Text(String(localized: "No declared formats"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        } else {
            let shown = formats.prefix(6)
            HStack(spacing: 0) {
                Text(shown.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if formats.count > shown.count {
                    Text("   +\(formats.count - shown.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func windowRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .padding(.bottom, 2)
    }

    private func isEditingHotkey(_ target: HotkeyTarget) -> Binding<Bool> {
        Binding(
            get: { editingHotkeyTarget == target },
            set: { isPresented in
                if !isPresented, editingHotkeyTarget == target {
                    editingHotkeyTarget = nil
                }
            }
        )
    }

    private func handleAppHotkeyResult(_ result: HotkeyRecorder.Result, appID: String) {
        switch result {
        case let .set(key, keyCode):
            setAppHotkey(key, keyCode: keyCode, appID: appID)
        case .clear:
            setAppHotkey(nil, keyCode: nil, appID: appID)
        case .cancel:
            break
        }
        editingHotkeyTarget = nil
    }

    private func setAppHotkey(_ key: Character?, keyCode: UInt16?, appID: String) {
        guard let idx = appState.apps.firstIndex(where: { $0.id == appID }) else { return }
        appState.apps[idx].hotkey = key
        appState.apps[idx].hotkeyKeyCode = keyCode
        appManager?.save(appState.apps)
    }

    private func setVisibility(_ isVisible: Bool, appID: String) {
        guard let idx = appState.apps.firstIndex(where: { $0.id == appID }) else { return }
        appState.apps[idx].isVisible = isVisible
        appManager?.save(appState.apps)
    }
}
