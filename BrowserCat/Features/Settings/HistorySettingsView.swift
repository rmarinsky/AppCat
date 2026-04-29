import SwiftUI

struct HistorySettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.historyManager) private var historyManager
    @Environment(\.urlRulesManager) private var urlRulesManager

    @State private var selection = Set<UUID>()
    @State private var ruleFromHistory: URLRule?

    var body: some View {
        VStack(spacing: 0) {
            if appState.history.isEmpty {
                emptyState
            } else {
                historyList
            }

            Divider()

            bottomBar
        }
        .sheet(item: $ruleFromHistory) { rule in
            RuleEditorSheet(
                rule: rule,
                browsers: appState.browsers,
                apps: appState.visibleApps,
                onSave: { newRule in
                    var newRule = newRule
                    newRule.sortOrder = appState.urlRules.count
                    appState.urlRules.append(newRule)
                    urlRulesManager?.save(appState.urlRules)
                    ruleFromHistory = nil
                },
                onCancel: {
                    ruleFromHistory = nil
                }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No History")
                .font(.headline)
            Text("URLs you open will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List

    private var historyList: some View {
        List(selection: $selection) {
            ForEach(groupedEntries, id: \.label) { group in
                Section(group.label) {
                    ForEach(group.entries) { entry in
                        historyRow(entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button(String(localized: "Create Rule…")) {
                                    ruleFromHistory = makeRule(from: entry)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 10) {
            FaviconView(urlString: entry.url, fallbackDomain: entry.domain, size: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.domain)
                    .font(.system(size: 12, weight: .medium))
                if let title = entry.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.appName)
                        .font(.system(size: 11))
                    if let profile = entry.profileName {
                        Text("(\(profile))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.openedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button("Clear All") {
                historyManager?.clearAll(state: appState)
                selection.removeAll()
            }
            .disabled(appState.history.isEmpty)

            Spacer()

            Button("Remove Selected") {
                historyManager?.delete(ids: selection, state: appState)
                selection.removeAll()
            }
            .disabled(selection.isEmpty)
        }
        .padding(8)
    }

    // MARK: - Rule from history

    private func makeRule(from entry: HistoryEntry) -> URLRule {
        // Direct ID match (entries written by current app version)
        if let browserID = entry.browserID {
            return URLRule(
                pattern: entry.domain,
                matchType: .host,
                browserID: browserID,
                profileDirectoryName: entry.profileDirectoryName,
                targetType: entry.targetType ?? .browser,
                isEnabled: true,
                sortOrder: appState.urlRules.count
            )
        }

        // Legacy fallback: resolve by display name against currently installed browsers/apps
        if let browser = appState.browsers.first(where: { $0.displayName == entry.appName }) {
            let profileDir = entry.profileName.flatMap { name in
                browser.profiles.first(where: { $0.displayName == name })?.directoryName
            }
            return URLRule(
                pattern: entry.domain,
                matchType: .host,
                browserID: browser.id,
                profileDirectoryName: profileDir,
                targetType: .browser,
                isEnabled: true,
                sortOrder: appState.urlRules.count
            )
        }
        if let app = appState.apps.first(where: { $0.displayName == entry.appName }) {
            return URLRule(
                pattern: entry.domain,
                matchType: .host,
                browserID: app.id,
                profileDirectoryName: nil,
                targetType: .app,
                isEnabled: true,
                sortOrder: appState.urlRules.count
            )
        }

        // Last resort: prefill the pattern, let the user pick the browser/app in the editor
        return URLRule(
            pattern: entry.domain,
            matchType: .host,
            browserID: "",
            profileDirectoryName: nil,
            targetType: .browser,
            isEnabled: true,
            sortOrder: appState.urlRules.count
        )
    }

    // MARK: - Grouping

    private struct DateGroup {
        let label: String
        let entries: [HistoryEntry]
    }

    private var groupedEntries: [DateGroup] {
        let calendar = Calendar.current

        var today: [HistoryEntry] = []
        var yesterday: [HistoryEntry] = []
        var older: [HistoryEntry] = []

        for entry in appState.history {
            if calendar.isDateInToday(entry.openedAt) {
                today.append(entry)
            } else if calendar.isDateInYesterday(entry.openedAt) {
                yesterday.append(entry)
            } else {
                older.append(entry)
            }
        }

        var groups: [DateGroup] = []
        if !today.isEmpty { groups.append(DateGroup(label: String(localized: "Today"), entries: today)) }
        if !yesterday.isEmpty { groups.append(DateGroup(label: String(localized: "Yesterday"), entries: yesterday)) }
        if !older.isEmpty { groups.append(DateGroup(label: String(localized: "Older"), entries: older)) }
        return groups
    }
}
