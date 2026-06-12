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
                Text("Shortcuts")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)

                sectionCaption("ACTIVATION")
                activationCard

                sectionCaption("WITHIN THE PICKER")
                    .padding(.top, 8)
                pickerCard
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
    }

    private func sectionCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.44)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Activation (real global hotkeys)

    private var activationCard: some View {
        card {
            shortcutRow(String(localized: "Open picker manually")) {
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
        card {
            shortcutRow(String(localized: "Select browser")) {
                HStack(spacing: 4) {
                    Keycap("1")
                    Text("…").foregroundStyle(.tertiary)
                    Keycap("9")
                }
            }
            divider
            shortcutRow(String(localized: "Confirm selection")) { Keycap("⏎") }
            divider
            shortcutRow(String(localized: "Cancel")) { Keycap("esc") }
            divider
            shortcutRow(String(localized: "Select with number keys")) {
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

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
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

    private var divider: some View {
        Rectangle().fill(Color("HairlineBorder")).frame(height: 1)
    }

    private func shortcutRow(_ label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
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
    init(_ text: String) { self.text = text }

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
