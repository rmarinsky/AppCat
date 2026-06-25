import KeyboardShortcuts
import SwiftUI

/// Shortcuts settings — a 1:1 port of the Figma Settings/Shortcuts frame.
/// ACTIVATION holds the two real global hotkeys (recordable); WITHIN THE PICKER is a
/// reference list of the picker's built-in keys plus the number-key selection toggle.
struct ShortcutsSettingsView: View {
    @Environment(AppState.self) private var appState

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
            shortcutRow(
                String(localized: "Open picker manually"),
                subtitle: String(localized: "You can try ⌘Tab here. macOS owns it by default, so AppCat can use it only if the system shortcut is disabled or released.")
            ) {
                KeyboardShortcuts.Recorder(for: .openPickerManually)
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
            shortcutRow(String(localized: "Select picker item")) {
                HStack(spacing: 4) {
                    Keycap("1")
                    Text("…").foregroundStyle(.tertiary)
                    Keycap("0")
                }
            }
            divider
            shortcutRow(String(localized: "Confirm selection")) { Keycap("⏎") }
            divider
            shortcutRow(String(localized: "Cancel")) { Keycap("esc") }
            divider
            shortcutRow(String(localized: "Select with shortcut keys")) {
                Toggle("", isOn: Binding(
                    get: { appState.selectWithNumberKeys },
                    set: { newValue in
                        appState.selectWithNumberKeys = newValue
                        SettingsStorage.shared.selectWithNumberKeys = newValue
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Color.accentColor)
            }
        }
    }

    // MARK: - Building blocks

    private var divider: some View {
        Rectangle().fill(Color("HairlineBorder")).frame(height: 1)
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
