import SwiftUI

/// Apps screen — the system-wide app navigator. Lists every installed app (browsers
/// excluded — they have their own screen), sorted by how often you route to it, so the
/// apps you use most float to the top. Toggle controls whether an app appears in the picker.
struct AppsScreenView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appManager) private var appManager

    @State private var search: String = ""

    private var filteredApps: [InstalledApp] {
        let sorted = appState.appsByFrequency
        guard !search.isEmpty else { return sorted }
        let q = search.lowercased()
        return sorted.filter { $0.displayName.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Apps")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                searchField

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
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search apps"), text: $search)
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

    private var card: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                if index > 0 {
                    Rectangle().fill(Color("HairlineBorder")).frame(height: 1)
                }
                row(app)
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

    private func row(_ app: InstalledApp) -> some View {
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

    private func setVisibility(_ isVisible: Bool, appID: String) {
        guard let idx = appState.apps.firstIndex(where: { $0.id == appID }) else { return }
        appState.apps[idx].isVisible = isVisible
        appManager?.save(appState.apps)
    }
}
