import KeyboardShortcuts
import SwiftUI

/// Shortcuts settings — a 1:1 port of the Figma Settings/Shortcuts frame.
/// ACTIVATION holds the two real global hotkeys (recordable); WITHIN THE PICKER is a
/// reference list of the picker's built-in keys plus mode-specific direct selection.
struct ShortcutsSettingsView: View {
    @Environment(AppState.self) private var appState

    private var directSelectionAvailable: Bool {
        appState.pickerActivationMode == .toggleShortcut || appState.pickerServiceKey != .off
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionCaption("ACTIVATION")
                activationCard

                SettingsSectionCaption("WITHIN THE PICKER")
                    .padding(.top, 8)
                pickerCard
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
    }

    // MARK: - Activation (real global hotkeys)

    private var activationCard: some View {
        SettingsCard(cornerRadius: 8) {
            shortcutRow(String(localized: "Activation mode")) {
                Picker("", selection: Binding(
                    get: { appState.pickerActivationMode },
                    set: { mode in
                        appState.setPickerActivationMode(mode)
                        requestInputMonitoringIfNeeded()
                    }
                )) {
                    ForEach(PickerActivationMode.allCases) { mode in
                        Text(mode.localizedDisplayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            divider
            if appState.pickerActivationMode == .toggleShortcut {
                shortcutRow(
                    String(localized: "Open picker manually"),
                    subtitle: String(localized: "Default is ⌥Tab. Record any macOS-accepted global shortcut here.")
                ) {
                    KeyboardShortcuts.Recorder(for: .openPickerManually)
                }
                divider
            } else {
                shortcutRow(
                    String(localized: "Hold to switch"),
                    subtitle: String(localized: "Hold ⌥, press Tab to move forward, press ⇧Tab to move back, release ⌥ to open.")
                ) {
                    HStack(spacing: 4) {
                        Keycap("⌥")
                        Keycap("⇥")
                    }
                }
                divider
            }
            shortcutRow(String(localized: "Service key")) {
                Picker("", selection: Binding(
                    get: { appState.pickerServiceKey },
                    set: { key in
                        appState.setPickerServiceKey(key)
                        requestInputMonitoringIfNeeded()
                    }
                )) {
                    ForEach(PickerServiceKey.allCases) { key in
                        Text(key.localizedDisplayName).tag(key)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            if appState.pickerServiceKey != .off {
                divider
                shortcutRow(String(localized: "Service key taps")) {
                    Picker("", selection: Binding(
                        get: { appState.pickerServiceTapCount },
                        set: { count in
                            appState.setPickerServiceTapCount(count)
                        }
                    )) {
                        ForEach(PickerServiceTapCount.allCases) { count in
                            Text(count.localizedDisplayName).tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                divider
                shortcutRow(
                    String(localized: "Input Monitoring"),
                    subtitle: String(localized: "Required for hold-to-switch and service-key taps.")
                ) {
                    Button(String(localized: "Open Settings")) {
                        PickerActivationPermission.requestInputMonitoring()
                        PickerActivationPermission.openInputMonitoringSettings()
                        appState.refreshPickerActivationSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            divider
            shortcutRow(String(localized: "Re-open last picker")) {
                KeyboardShortcuts.Recorder(for: .reopenLastPicker)
            }
        }
    }

    // MARK: - Within the picker (reference + toggle)

    private var pickerCard: some View {
        SettingsCard(cornerRadius: 8) {
            if directSelectionAvailable {
                shortcutRow(String(localized: "Select picker item")) {
                    HStack(spacing: 4) {
                        Keycap("1")
                        Text("…").foregroundStyle(.tertiary)
                        Keycap("0")
                    }
                }
                divider
            }
            shortcutRow(String(localized: "Confirm selection")) { Keycap("⏎") }
            divider
            shortcutRow(String(localized: "Cancel")) { Keycap("esc") }
            if directSelectionAvailable {
                divider
                shortcutRow(String(localized: "Select with shortcut keys")) {
                    Toggle("", isOn: Binding(
                        get: { appState.selectWithNumberKeys },
                        set: { newValue in
                            appState.setSelectWithNumberKeys(newValue)
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .tint(Color.accentColor)
                }
            }
        }
    }

    // MARK: - Building blocks

    private var divider: some View {
        Rectangle().fill(Color("HairlineBorder")).frame(height: 1)
    }

    private func requestInputMonitoringIfNeeded() {
        guard appState.pickerActivationMode == .holdOptionTab || appState.pickerServiceKey != .off else {
            return
        }
        PickerActivationPermission.requestInputMonitoring()
    }

    private func shortcutRow(
        _ label: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
    }
}

/// A static reference keycap (e.g. ⏎, esc, 1).
private struct Keycap: View {
    let text: String
    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
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
}
