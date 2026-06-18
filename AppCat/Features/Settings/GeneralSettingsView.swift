import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.defaultBrowserManager) private var defaultBrowserManager
    @State private var isShowingFileHandlerWarning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionCaption("GENERAL")
                card {
                    defaultBrowserRow
                    divider
                    webFilesRow
                    divider
                    launchAtLoginRow
                }

                sectionCaption("PICKER")
                    .padding(.top, 2)
                card {
                    recentItemsRow
                }

                sectionCaption("LANGUAGE")
                    .padding(.top, 2)
                card {
                    languageRow
                }

                sectionCaption("DEVELOPER")
                    .padding(.top, 2)
                card {
                    madeByRow
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 17)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
        .onAppear {
            defaultBrowserManager?.checkIsDefault(state: appState)
        }
        .alert(
            String(localized: "Set AppCat as default for files?"),
            isPresented: $isShowingFileHandlerWarning
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Continue")) {
                defaultBrowserManager?.setAsDefaultForWebFiles(state: appState)
            }
        } message: {
            Text(String(localized: "macOS will ask for each file group. This is optional and only needed if you want Finder double-clicks to route files through AppCat."))
        }
    }

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
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory()
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 48)
    }

    private var defaultBrowserRow: some View {
        row(
            title: appState.isDefaultBrowser
                ? String(localized: "AppCat handles all web links")
                : String(localized: "AppCat is not the default browser"),
            subtitle: String(localized: "Set as the default browser in macOS")
        ) {
            if appState.isDefaultBrowser {
                StatusPill(title: String(localized: "On"), isOn: true)
            } else if appState.isSettingDefaultBrowser {
                InlineButton(title: String(localized: "Setting…"), isDisabled: true) {}
            } else {
                InlineButton(title: String(localized: "Set")) {
                    defaultBrowserManager?.setAsDefault(state: appState)
                }
            }
        }
    }

    private var webFilesRow: some View {
        row(
            title: appState.isDefaultWebFileHandler
                ? String(localized: "AppCat handles web and dev files")
                : String(localized: "AppCat does not handle web and dev files"),
            subtitle: String(localized: "Optional. Finder double-clicks can route files through AppCat, but macOS will ask for each file group.")
        ) {
            if appState.isDefaultWebFileHandler {
                StatusPill(title: String(localized: "On"), isOn: true)
            } else if appState.isSettingDefaultWebFileHandler {
                InlineButton(title: String(localized: "Setting…"), isDisabled: true) {}
            } else {
                InlineButton(title: String(localized: "Configure…")) {
                    isShowingFileHandlerWarning = true
                }
            }
        }
    }

    private var launchAtLoginRow: some View {
        HStack {
            LaunchAtLogin.Toggle(String(localized: "Launch at login"))
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 48)
    }

    private var recentItemsRow: some View {
        row(title: String(localized: "Recent menu bar items")) {
            Picker("", selection: Binding(
                get: { appState.recentLinksCount },
                set: { newValue in
                    appState.recentLinksCount = newValue
                    SettingsStorage.shared.recentLinksCount = newValue
                }
            )) {
                ForEach(1 ... 5, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .labelsHidden()
            .frame(width: 94)
        }
    }

    private var languageRow: some View {
        row(
            title: String(localized: "App language"),
            subtitle: String(localized: "Restart AppCat to apply language changes.")
        ) {
            Picker("", selection: Binding(
                get: { appState.appLanguage },
                set: { newValue in
                    appState.appLanguage = newValue
                    SettingsStorage.shared.appLanguage = newValue
                    SettingsStorage.shared.applyLanguagePreference()
                }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.localizedDisplayName).tag(language)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
    }

    private var madeByRow: some View {
        row(title: String(localized: "Made by")) {
            Text("Roman Marinsky 🇺🇦")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let isOn: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isOn ? Color("BrandSuccess") : Color.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color("SurfaceInset"))
            )
    }
}

private struct InlineButton: View {
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color("BrandAccentDeep"))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.7 : 1)
    }
}
