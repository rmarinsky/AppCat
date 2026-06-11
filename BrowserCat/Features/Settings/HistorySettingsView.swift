import SwiftUI

struct HistorySettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.historyManager) private var historyManager
    @Environment(\.urlRulesManager) private var urlRulesManager

    @State private var selection = Set<UUID>()
    @State private var ruleFromHistory: URLRule?
    @State private var searchText: String = ""
    private let ruleMatcher = URLRuleMatcher()

    var body: some View {
        VStack(spacing: 0) {
            if appState.history.isEmpty {
                emptyState
            } else if groupedEntries.isEmpty {
                ContentUnavailableView.search
            } else {
                historyList
            }

            Divider()

            bottomBar
        }
        .searchable(text: $searchText, prompt: String(localized: "Search history"))
        .navigationTitle(String(localized: "History"))
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
            Text("Links and files you open will appear here.")
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
                                if canCreateRule(from: entry), !ruleAlreadyCovers(entry) {
                                    Button(String(localized: "Create Rule…")) {
                                        ruleFromHistory = makeRule(from: entry)
                                    }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        let hasRule = ruleAlreadyCovers(entry)
        let canCreate = canCreateRule(from: entry)

        return HStack(spacing: 10) {
            entryIcon(entry)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText(for: entry))
                    .font(.system(size: 12, weight: .medium))
                if let subtitle = secondaryText(for: entry) {
                    Text(subtitle)
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

            createRuleButton(for: entry, hasRule: hasRule, canCreate: canCreate)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func entryIcon(_ entry: HistoryEntry) -> some View {
        switch entry.itemKind {
        case .link:
            FaviconView(urlString: entry.url, fallbackDomain: entry.domain, size: 20)
        case .file:
            Image(systemName: "doc")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
    }

    private func primaryText(for entry: HistoryEntry) -> String {
        switch entry.itemKind {
        case .link:
            return entry.domain
        case .file:
            return entry.fileName ?? entry.domain
        }
    }

    private func secondaryText(for entry: HistoryEntry) -> String? {
        switch entry.itemKind {
        case .link:
            return normalized(entry.title)
        case .file:
            let format = entry.fileFormat ?? entry.contentTypeIdentifier
            let path = URL(string: entry.url)?.path
            if let format, let path {
                return "\(format) · \(path)"
            }
            return format ?? path
        }
    }

    private func createRuleButton(for entry: HistoryEntry, hasRule: Bool, canCreate: Bool) -> some View {
        Button {
            ruleFromHistory = makeRule(from: entry)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hasRule || !canCreate ? .secondary : .primary)
                if !hasRule, canCreate {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color("BrandAccentDeep"))
                        .background(Circle().fill(Color(NSColor.controlBackgroundColor)).padding(-1))
                        .offset(x: 4, y: 3)
                }
            }
            .frame(width: 22, height: 18)
        }
        .buttonStyle(.borderless)
        .disabled(hasRule || !canCreate)
        .help(hasRule
            ? String(localized: "A rule already covers this URL")
            : (canCreate
                ? String(localized: "Create Rule…")
                : String(localized: "Cannot create rule — original target unavailable")))
    }

    private func ruleAlreadyCovers(_ entry: HistoryEntry) -> Bool {
        guard entry.itemKind == .link else { return false }
        guard let url = URL(string: entry.url) else { return false }
        return ruleMatcher.findMatchingRule(for: url, rules: appState.urlRules) != nil
    }

    private func canCreateRule(from entry: HistoryEntry) -> Bool {
        entry.itemKind == .link && (entry.browserID != nil || legacyTargetResolves(for: entry))
    }

    private func legacyTargetResolves(for entry: HistoryEntry) -> Bool {
        appState.browsers.contains(where: { $0.displayName == entry.appName })
            || appState.apps.contains(where: { $0.displayName == entry.appName })
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

    private var filteredEntries: [HistoryEntry] {
        guard !searchText.isEmpty else { return appState.history }
        let query = searchText.lowercased()
        return appState.history.filter {
            $0.domain.lowercased().contains(query)
                || ($0.title?.lowercased().contains(query) ?? false)
                || $0.appName.lowercased().contains(query)
                || $0.url.lowercased().contains(query)
        }
    }

    private var groupedEntries: [DateGroup] {
        let calendar = Calendar.current

        var today: [HistoryEntry] = []
        var yesterday: [HistoryEntry] = []
        var older: [HistoryEntry] = []

        for entry in filteredEntries {
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

    private func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
