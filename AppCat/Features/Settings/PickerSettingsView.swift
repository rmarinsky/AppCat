import AppKit
import SwiftUI

/// Picker settings — controls which running apps appear in the manual app switcher and how they're
/// grouped, plus picker-only app exclusions for noisy menu-bar/background utilities.
struct PickerSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var hiddenAppSearch = ""

    private struct AppCandidate: Identifiable {
        let id: String
        let displayName: String
        let icon: NSImage?
    }

    private var appCandidates: [AppCandidate] {
        var seen = Set<String>()
        let apps = appState.apps.map { AppCandidate(id: $0.id, displayName: $0.displayName, icon: $0.icon) }
        let browsers = appState.browsers.map { AppCandidate(id: $0.id, displayName: $0.displayName, icon: $0.icon) }
        return (apps + browsers)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var hiddenApps: [AppCandidate] {
        appState.hiddenPickerAppIDs
            .map { id in
                appCandidates.first { $0.id == id } ?? AppCandidate(id: id, displayName: id, icon: nil)
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var searchResults: [AppCandidate] {
        let query = hiddenAppSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return Array(appCandidates
            .filter { candidate in
                !appState.hiddenPickerAppIDs.contains(candidate.id)
                    && (candidate.displayName.lowercased().contains(query) || candidate.id.lowercased().contains(query))
            }
            .prefix(8))
    }

    private var pickerScalePercent: String {
        "\(Int((appState.pickerScale * 100).rounded()))%"
    }

    private var pickerScaleBinding: Binding<Double> {
        Binding(
            get: { appState.pickerScale },
            set: { value in
                let clampedValue = PickerScale.clamped(value)
                appState.pickerScale = clampedValue
                SettingsStorage.shared.pickerScale = clampedValue
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionCaption("APPEARANCE")
                SettingsCard {
                    pickerScaleRow
                }

                SettingsSectionCaption("APP SWITCHER")
                Text("Choose which running apps show up when you switch apps and windows.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                SettingsCard {
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

                SettingsSectionCaption("NEVER SHOW IN PICKER")
                    .padding(.top, 2)
                SettingsCard {
                    hiddenAppsEditor
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

    // MARK: - Hidden apps

    private var pickerScaleRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "Picker size"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(String(localized: "Scales the picker panel, icons, labels, and key hints."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(pickerScalePercent)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "app.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)

                Slider(
                    value: pickerScaleBinding,
                    in: PickerScale.minimum...PickerScale.maximum
                )
                .controlSize(.small)
                .tint(Color("BrandAccentDeep"))

                Image(systemName: "app.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var hiddenAppsEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Hide apps from every picker"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Text(String(localized: "Use this for menu-bar utilities, background helpers, or anything you never want to see in link/file/app switching."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                hiddenAppSearchField

                if !searchResults.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(searchResults) { candidate in
                            Button {
                                addHiddenApp(candidate.id)
                            } label: {
                                candidateRow(candidate, trailingSystemImage: "plus")
                            }
                            .buttonStyle(.plain)
                            if candidate.id != searchResults.last?.id {
                                divider.padding(.horizontal, 0)
                            }
                        }
                    }
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
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            divider

            if hiddenApps.isEmpty {
                Text(String(localized: "No hidden apps yet."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(hiddenApps) { candidate in
                        HStack(spacing: 10) {
                            appIcon(candidate.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.displayName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(candidate.id)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                removeHiddenApp(candidate.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help(String(format: String(localized: "Show %@ in the picker again"), candidate.displayName))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        if candidate.id != hiddenApps.last?.id {
                            divider
                        }
                    }
                }
            }
        }
    }

    private var hiddenAppSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search apps to hide"), text: $hiddenAppSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { addFirstSearchResult() }
            if !hiddenAppSearch.isEmpty {
                Button { hiddenAppSearch = "" } label: {
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

    private func candidateRow(_ candidate: AppCandidate, trailingSystemImage: String) -> some View {
        HStack(spacing: 10) {
            appIcon(candidate.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(candidate.id)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: trailingSystemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color("BrandAccentDeep"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func appIcon(_ icon: NSImage?) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
                .cornerRadius(5)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
    }

    private func addFirstSearchResult() {
        guard let first = searchResults.first else { return }
        addHiddenApp(first.id)
    }

    private func addHiddenApp(_ id: String) {
        var ids = appState.hiddenPickerAppIDs
        ids.insert(id)
        setHiddenAppIDs(ids)
        hiddenAppSearch = ""
    }

    private func removeHiddenApp(_ id: String) {
        var ids = appState.hiddenPickerAppIDs
        ids.remove(id)
        setHiddenAppIDs(ids)
    }

    private func setHiddenAppIDs(_ ids: Set<String>) {
        appState.hiddenPickerAppIDs = ids
        appState.pickerItemsSnapshot = []
        SettingsStorage.shared.hiddenPickerAppIDs = ids
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
