import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.defaultBrowserManager) private var defaultBrowserManager

    var body: some View {
        @Bindable var state = appState
        let sectionBinding = Binding<MainWindowSection?>(
            get: { state.mainWindowSection },
            set: { if let v = $0 { state.mainWindowSection = v } }
        )

        VStack(spacing: 0) {
            BrandTileView()
                .padding(.bottom, 4)

            List(selection: sectionBinding) {
                SidebarItemView(section: .overview, current: appState.mainWindowSection)
                    .tag(MainWindowSection.overview)

                SidebarItemView(section: .history, current: appState.mainWindowSection)
                    .tag(MainWindowSection.history)

                SidebarItemView(section: .suggestions, current: appState.mainWindowSection)
                    .tag(MainWindowSection.suggestions)

                Section {
                    SidebarItemView(section: .settingsGeneral, current: appState.mainWindowSection)
                        .tag(MainWindowSection.settingsGeneral)

                    SidebarItemView(section: .settingsBrowsers, current: appState.mainWindowSection)
                        .tag(MainWindowSection.settingsBrowsers)

                    SidebarItemView(section: .settingsRules, current: appState.mainWindowSection)
                        .tag(MainWindowSection.settingsRules)

                    SidebarItemView(section: .settingsShortcuts, current: appState.mainWindowSection)
                        .tag(MainWindowSection.settingsShortcuts)

                    SidebarItemView(section: .settingsAccount, current: appState.mainWindowSection)
                        .tag(MainWindowSection.settingsAccount)
                } header: {
                    Text("Settings")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                }
            }
            .listStyle(.sidebar)

            Divider()

            DefaultBrowserFooter()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }
}

// MARK: - Brand Tile

private struct BrandTileView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "cat.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            Text("BrowserCat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            ProBadgeView()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color("BrandAccentDeep"), Color.accentColor],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
}

private struct ProBadgeView: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color("ProBadgeText"))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color("ProBadgeBg"))
            )
    }
}

// MARK: - Sidebar Item

private struct SidebarItemView: View {
    let section: MainWindowSection
    let current: MainWindowSection
    private var isSelected: Bool { section == current }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.22) : Color("BrandTintSoft"))
                    .frame(width: 26, height: 26)
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : Color("BrandAccentDeep"))
            }
            Text(section.label)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? .white : .primary)
            Spacer()
        }
        .padding(.vertical, 1)
        .listRowBackground(
            isSelected
                ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color("BrandAccentDeep"))
                : nil
        )
    }
}

// MARK: - Footer

private struct DefaultBrowserFooter: View {
    @Environment(AppState.self) private var appState
    @Environment(\.defaultBrowserManager) private var defaultBrowserManager

    var body: some View {
        if appState.isDefaultBrowser {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Default browser")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Set as Default") {
                    appState.mainWindowSection = .settingsGeneral
                    defaultBrowserManager?.setAsDefault(state: appState)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Color("BrandAccentDeep"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
