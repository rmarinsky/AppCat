import AppKit
import SwiftUI

/// Flat sidebar matching the Figma spec (node 197:717): solid SurfaceSidebar fill,
/// 30×30 gradient brand tile, plain icon+label rows, accent-deep active row, footer pill.
struct SidebarView: View {
    @Environment(AppState.self) private var appState

    private let primaryItems: [MainWindowSection] = [.overview, .history, .suggestions]
    private let settingsItems: [MainWindowSection] = [
        .settingsGeneral, .settingsBrowsers, .settingsApps, .settingsRules, .settingsShortcuts, .settingsAccount,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
                .padding(.horizontal, 16)
                .padding(.top, 40)
                .padding(.bottom, 18)

            VStack(spacing: 4) {
                ForEach(primaryItems, id: \.self) { navRow($0) }
            }

            Text("SETTINGS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
                .padding(.leading, 20)
                .padding(.top, 22)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                ForEach(settingsItems, id: \.self) { navRow($0) }
            }

            Spacer(minLength: 0)

            footer
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceSidebar"))
    }

    // MARK: - Brand header

    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color("BrandAccentDeep")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 30, height: 30)
                Image(systemName: "cat.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("BrowserCat")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("PRO")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color("ProBadgeText"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color("ProBadgeBg"))
                    )
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Nav row

    private func navRow(_ section: MainWindowSection) -> some View {
        let isSelected = appState.mainWindowSection == section
        return Button {
            appState.mainWindowSection = section
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 16, alignment: .center)
                Text(section.label)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color("BrandAccentDeep") : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: - Footer

    private var footer: some View {
        DefaultBrowserFooter()
    }
}

// MARK: - Footer pill

private struct DefaultBrowserFooter: View {
    @Environment(AppState.self) private var appState
    @Environment(\.defaultBrowserManager) private var defaultBrowserManager

    var body: some View {
        HStack(spacing: 8) {
            if appState.isDefaultBrowser {
                Circle()
                    .fill(Color("BrandSuccess"))
                    .frame(width: 8, height: 8)
                Text("Catching links")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            } else {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                Button {
                    appState.mainWindowSection = .settingsGeneral
                    defaultBrowserManager?.setAsDefault(state: appState)
                } label: {
                    Text("Set as default")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color("BrandAccentDeep"))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("SurfaceInset"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }
}
