import SwiftUI
import UniformTypeIdentifiers

/// Browsers settings — a 1:1 port of Figma node 166:2. A single flat card lists the
/// installed browsers (drag to reorder); each row shows favicon, name, an optional
/// DEFAULT badge, the picker number key (⌘N), and a visibility toggle.
struct BrowsersSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.browserManager) private var browserManager

    @State private var draggingID: String?

    private var browsers: [InstalledBrowser] {
        appState.browsers.filter { !$0.isIgnored }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Browsers")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("INSTALLED BROWSERS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.44)
                    .foregroundStyle(.tertiary)

                card

                Text("Drag to reorder · number keys select a browser in the picker")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(22)
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

    private func row(_ browser: InstalledBrowser, index: Int) -> some View {
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

            if index == 0, browser.isVisible {
                Text("DEFAULT")
                    .font(.system(size: 10, weight: .semibold))
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

    // MARK: - Mutations

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
