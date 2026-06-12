import SwiftUI

/// Apps screen — the system-wide app navigator. Lists every installed app (browsers
/// excluded), sorted by how often you route to it. For multi-window apps it surfaces the
/// open windows/projects (via Accessibility) so you can see and filter which project each
/// Cursor/editor window holds. Toggle controls whether an app appears in the picker.
struct AppsScreenView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appManager) private var appManager

    @State private var search: String = ""
    @State private var windowsByApp: [String: [String]] = [:]

    private func windows(for app: InstalledApp) -> [String] {
        windowsByApp[app.id] ?? []
    }

    private func matchingWindows(for app: InstalledApp) -> [String] {
        let titles = windows(for: app)
        guard !search.isEmpty else { return titles }
        let q = search.lowercased()
        return titles.filter { $0.lowercased().contains(q) }
    }

    private var filteredApps: [InstalledApp] {
        let sorted = appState.appsByFrequency
        guard !search.isEmpty else { return sorted }
        let q = search.lowercased()
        return sorted.filter { app in
            app.displayName.lowercased().contains(q)
                || windows(for: app).contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Apps")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
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

                searchField

                if !WindowEnumerator.isTrusted {
                    accessibilityHint
                }

                Text("ALL APPS · SORTED BY USE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.44)
                    .foregroundStyle(.tertiary)

                if filteredApps.isEmpty {
                    Text(search.isEmpty ? "No apps detected." : "No apps match \u{201C}\(search)\u{201D}.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    card
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
        .onAppear { windowsByApp = WindowEnumerator.runningWindowTitles() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search apps or open projects"), text: $search)
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
            Text("Grant Accessibility to see open windows & projects.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Settings") {
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

    private var card: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                if index > 0 {
                    Rectangle().fill(Color("HairlineBorder")).frame(height: 1)
                }
                appBlock(app)
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
    private func appBlock(_ app: InstalledApp) -> some View {
        let wins = windows(for: app)
        // Show window/project sub-rows for multi-window apps, or when a title matches search.
        let shownWindows: [String] = {
            if !search.isEmpty { return matchingWindows(for: app) }
            return wins.count >= 2 ? wins : []
        }()

        VStack(spacing: 0) {
            row(app, windowCount: wins.count)
            ForEach(Array(shownWindows.prefix(8).enumerated()), id: \.offset) { _, title in
                windowRow(title)
            }
        }
    }

    private func row(_ app: InstalledApp, windowCount: Int) -> some View {
        let count = appState.appUsage[app.id]?.count ?? 0
        return HStack(spacing: 10) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 16))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.secondary)
            }

            Text(app.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if windowCount >= 2 {
                Text("\(windowCount) windows")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color("SurfaceInset"))
                    )
            }

            Spacer(minLength: 8)

            if count > 0 {
                Text("used \(count)×")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func windowRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "macwindow")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 22)
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

    private func setVisibility(_ isVisible: Bool, appID: String) {
        guard let idx = appState.apps.firstIndex(where: { $0.id == appID }) else { return }
        appState.apps[idx].isVisible = isVisible
        appManager?.save(appState.apps)
    }
}
