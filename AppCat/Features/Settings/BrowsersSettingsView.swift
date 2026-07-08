import SwiftUI
import UniformTypeIdentifiers

/// Browsers settings — a flat card lists the installed browsers (drag to reorder); each row
/// shows favicon, name, the picker number key (⌘N), and a visibility toggle. Browsers with
/// profiles reveal their profiles as nested rows, each with its own toggle so
/// you can include/exclude individual profiles from the picker.
///
/// Note: there is deliberately no "default browser" badge here — AppCat *itself* is the
/// system default ("браузер-киця"); no listed browser is the default.
struct BrowsersSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.browserManager) private var browserManager

    @State private var draggingID: String?
    @State private var editingHotkeyTarget: HotkeyTarget?

    private var browsers: [InstalledBrowser] {
        appState.browsers.filter { !$0.isIgnored }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "INSTALLED BROWSERS"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.44)
                    .foregroundStyle(.tertiary)

                card

                Text(String(localized: "Drag to reorder · shortcut keys pick by position · assign a key to open a browser or profile directly"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(Array(browsers.enumerated()), id: \.element.id) { index, browser in
                if index > 0 {
                    Rectangle()
                        .fill(Color("HairlineBorder"))
                        .frame(height: 1)
                }
                row(browser, index: index)

                if browser.hasProfiles {
                    ForEach(browser.profiles) { profile in
                        profileRow(browser, profile)
                    }
                }
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

    /// Picker number among *visible* browsers (1–9). nil when hidden or beyond 9.
    private func pickerNumber(for browser: InstalledBrowser) -> Int? {
        guard browser.isVisible else { return nil }
        let visible = browsers.filter(\.isVisible)
        guard let idx = visible.firstIndex(where: { $0.id == browser.id }), idx < 9 else { return nil }
        return idx + 1
    }

    private func row(_ browser: InstalledBrowser, index _: Int) -> some View {
        HStack(spacing: 10) {
            if let icon = browser.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 16))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }

            Text(browser.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            if browser.hasProfiles {
                Text("\(browser.profiles.count) \(String(localized: "profiles"))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color("SurfaceInset"))
                    )
            }

            Spacer(minLength: 8)

            if let number = pickerNumber(for: browser) {
                Text("⌘\(number)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color("SurfaceSidebar"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
                    )
            }

            hotkeyButton(
                key: browser.hotkey,
                target: .browser(id: browser.id),
                compact: false
            ) { result in
                handleBrowserHotkeyResult(result, browserID: browser.id)
            }

            Toggle("", isOn: Binding(
                get: { browser.isVisible },
                set: { setVisibility($0, browserID: browser.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .tint(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .opacity(draggingID == browser.id ? 0.4 : 1)
        .draggable(browser.id) {
            Text(browser.displayName)
                .font(.system(size: 13, weight: .medium))
                .padding(8)
                .onAppear { draggingID = browser.id }
        }
        .dropDestination(for: String.self) { items, _ in
            draggingID = nil
            guard let sourceID = items.first else { return false }
            move(sourceID: sourceID, ontoID: browser.id)
            return true
        } isTargeted: { _ in }
    }

    /// A profile nested under its browser. A thin tree connector + indentation signals the
    /// hierarchy; the toggle includes/excludes this profile from the picker.
    private func profileRow(_ browser: InstalledBrowser, _ profile: BrowserProfile) -> some View {
        HStack(spacing: 0) {
            // Tree connector line, aligned under the browser icon.
            Rectangle()
                .fill(Color("HairlineStrong"))
                .frame(width: 1, height: 22)
                .padding(.leading, 21)
                .padding(.trailing, 13)

            ProfileAvatarBadge(
                profile: profile,
                size: 18,
                borderWidth: profile.avatarPath == nil ? 0 : 1
            )
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let email = profile.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 8)

            Spacer(minLength: 8)

            hotkeyButton(
                key: profile.hotkey,
                target: .profile(browserId: browser.id, directoryName: profile.directoryName),
                compact: true
            ) { result in
                handleProfileHotkeyResult(
                    result,
                    browserID: browser.id,
                    profileID: profile.directoryName
                )
            }

            Toggle("", isOn: Binding(
                get: { profile.isVisible },
                set: { setProfileVisibility($0, browserID: browser.id, profileID: profile.directoryName) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .tint(Color.accentColor)
        }
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Color("SurfaceInset").opacity(0.35))
    }

    private func hotkeyButton(
        key: Character?,
        target: HotkeyTarget,
        compact: Bool,
        onRecord: @escaping (HotkeyRecorder.Result) -> Void
    ) -> some View {
        Button {
            editingHotkeyTarget = target
        } label: {
            HStack(spacing: 6) {
                Text(compact ? String(localized: "Key") : String(localized: "Shortcut"))
                    .font(.system(size: compact ? 10 : 11, weight: .medium))
                    .foregroundStyle(.secondary)

                if let key {
                    SelectionKeycapView(key: key, compact: true, inline: true)
                } else {
                    Text(String(localized: "Set"))
                        .font(.system(size: compact ? 10 : 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, compact ? 4 : 5)
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
        .help(String(localized: "Set the key used to open this browser or profile"))
        .popover(isPresented: isEditingHotkey(target), arrowEdge: .bottom) {
            HotkeyRecorder { result in
                onRecord(result)
            }
        }
    }

    // MARK: - Mutations

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

    private func handleBrowserHotkeyResult(_ result: HotkeyRecorder.Result, browserID: String) {
        switch result {
        case let .set(key, keyCode):
            setBrowserHotkey(key, keyCode: keyCode, browserID: browserID)
        case .clear:
            setBrowserHotkey(nil, keyCode: nil, browserID: browserID)
        case .cancel:
            break
        }
        editingHotkeyTarget = nil
    }

    private func handleProfileHotkeyResult(
        _ result: HotkeyRecorder.Result,
        browserID: String,
        profileID: String
    ) {
        switch result {
        case let .set(key, keyCode):
            setProfileHotkey(key, keyCode: keyCode, browserID: browserID, profileID: profileID)
        case .clear:
            setProfileHotkey(nil, keyCode: nil, browserID: browserID, profileID: profileID)
        case .cancel:
            break
        }
        editingHotkeyTarget = nil
    }

    private func setBrowserHotkey(_ key: Character?, keyCode: UInt16?, browserID: String) {
        guard let idx = appState.browsers.firstIndex(where: { $0.id == browserID }) else { return }
        appState.browsers[idx].hotkey = key
        appState.browsers[idx].hotkeyKeyCode = keyCode
        browserManager?.save(appState.browsers)
    }

    private func setProfileHotkey(
        _ key: Character?,
        keyCode: UInt16?,
        browserID: String,
        profileID: String
    ) {
        guard let bIdx = appState.browsers.firstIndex(where: { $0.id == browserID }),
              let pIdx = appState.browsers[bIdx].profiles.firstIndex(where: { $0.directoryName == profileID })
        else { return }
        appState.browsers[bIdx].profiles[pIdx].hotkey = key
        appState.browsers[bIdx].profiles[pIdx].hotkeyKeyCode = keyCode
        browserManager?.save(appState.browsers)
    }

    private func setVisibility(_ isVisible: Bool, browserID: String) {
        guard let idx = appState.browsers.firstIndex(where: { $0.id == browserID }) else { return }
        appState.browsers[idx].isVisible = isVisible
        if !isVisible {
            for p in appState.browsers[idx].profiles.indices {
                appState.browsers[idx].profiles[p].isVisible = false
            }
        }
        browserManager?.save(appState.browsers)
    }

    private func setProfileVisibility(_ isVisible: Bool, browserID: String, profileID: String) {
        guard let bIdx = appState.browsers.firstIndex(where: { $0.id == browserID }),
              let pIdx = appState.browsers[bIdx].profiles.firstIndex(where: { $0.directoryName == profileID })
        else { return }
        appState.browsers[bIdx].profiles[pIdx].isVisible = isVisible
        browserManager?.save(appState.browsers)
    }

    private func move(sourceID: String, ontoID: String) {
        guard sourceID != ontoID else { return }
        var ordered = browsers
        guard let from = ordered.firstIndex(where: { $0.id == sourceID }),
              let to = ordered.firstIndex(where: { $0.id == ontoID }) else { return }
        let item = ordered.remove(at: from)
        ordered.insert(item, at: to)
        // Reassign sortOrder following the new order, then persist into appState.
        for (newOrder, browser) in ordered.enumerated() {
            if let idx = appState.browsers.firstIndex(where: { $0.id == browser.id }) {
                appState.browsers[idx].sortOrder = newOrder
            }
        }
        browserManager?.save(appState.browsers)
    }
}
