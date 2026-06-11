import LaunchAtLogin
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.defaultBrowserManager) private var defaultBrowserManager

    var body: some View {
        Form {
            Section("Default Browser") {
                HStack {
                    if appState.isDefaultBrowser {
                        Label("BrowserCat is the default browser", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color("BrandAccentDeep"))
                    } else {
                        Label("BrowserCat is not the default browser", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Set as Default") {
                            defaultBrowserManager?.setAsDefault(state: appState)
                        }
                    }
                }

                Text("Set as Default also configures supported web and dev file handlers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Web & Dev Files") {
                HStack {
                    if appState.isDefaultWebFileHandler {
                        Label("BrowserCat handles web and dev files", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color("BrandAccentDeep"))
                    } else {
                        Label("BrowserCat does not handle web and dev files", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Set for Files") {
                            defaultBrowserManager?.setAsDefaultForWebFiles(state: appState)
                        }
                    }
                }

                Text("Applies to browser-readable files plus developer/config files like .env, YAML, shell scripts, Dockerfile, Makefile, and systemd units.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                LaunchAtLogin.Toggle("Launch at login")
            }

            Section("Picker") {
                Toggle("Compact view", isOn: Binding(
                    get: { appState.compactPickerView },
                    set: { newValue in
                        appState.compactPickerView = newValue
                        SettingsStorage.shared.compactPickerView = newValue
                    }
                ))
            }

            Section("Menu Bar") {
                Picker("Recent items", selection: Binding(
                    get: { appState.recentLinksCount },
                    set: { newValue in
                        appState.recentLinksCount = newValue
                        SettingsStorage.shared.recentLinksCount = newValue
                    }
                )) {
                    ForEach(1...5, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }

            Section("Language") {
                Picker("App language", selection: Binding(
                    get: { appState.appLanguage },
                    set: { newValue in
                        appState.appLanguage = newValue
                        SettingsStorage.shared.appLanguage = newValue
                        SettingsStorage.shared.applyLanguagePreference()
                    }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayNameKey).tag(language)
                    }
                }

                Text("Restart BrowserCat to apply language changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Developer") {
                LabeledContent("Made by") {
                    Text("Roman Marinsky \u{1F1FA}\u{1F1E6}")
                }
            }

        }
        .formStyle(.grouped)
        .onAppear {
            defaultBrowserManager?.checkIsDefault(state: appState)
        }
    }
}
