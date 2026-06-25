import SwiftUI

/// Picker settings — controls which running apps appear in the manual app switcher and how they're
/// grouped. Per-app hide lives on the Apps screen (`app.isVisible`); this screen governs the
/// app-type filters that decide the switcher's contents.
struct PickerSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionCaption("APP SWITCHER")
                Text("Choose which running apps show up when you switch apps and windows.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                card {
                    toggleRow(
                        title: String(localized: "Show running apps without windows"),
                        subtitle: String(localized: "Apps that are running but have no open window appear dimmed, after the divider."),
                        isOn: Binding(
                            get: { appState.showWindowlessApps },
                            set: {
                                appState.showWindowlessApps = $0
                                SettingsStorage.shared.showWindowlessApps = $0
                            }
                        )
                    )
                    divider
                    toggleRow(
                        title: String(localized: "Show background & menu-bar apps"),
                        subtitle: String(localized: "Off by default. Menu-bar utilities (brightness, audio, etc.) and background apps stay out of the switcher."),
                        isOn: Binding(
                            get: { appState.showBackgroundApps },
                            set: {
                                appState.showBackgroundApps = $0
                                SettingsStorage.shared.showBackgroundApps = $0
                            }
                        )
                    )
                }

                sectionCaption("A SPECIFIC APP")
                    .padding(.top, 2)
                card {
                    manageInAppsRow
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 17)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
    }

    // MARK: - Rows

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        row(title: title, subtitle: subtitle) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Color.accentColor)
        }
    }

    private var manageInAppsRow: some View {
        row(
            title: String(localized: "Hide a specific app"),
            subtitle: String(localized: "Toggle any individual app off in the Apps list to keep it out of the picker.")
        ) {
            Button {
                appState.mainWindowSection = .settingsApps
            } label: {
                HStack(spacing: 4) {
                    Text("Open Apps")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color("BrandAccentDeep"))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Building blocks (match GeneralSettingsView)

    private func sectionCaption(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.tertiary)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color("SurfaceCard"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color("HairlineBorder"))
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    private func row<Accessory: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory()
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 56)
    }
}
