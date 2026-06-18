import AppKit
import SwiftUI

struct HistorySettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.urlRulesManager) private var urlRulesManager

    @State private var ruleFromHistory: URLRule?
    @State private var searchText: String = ""
    @State private var scope: HistoryScope = .today
    @State private var visibleCount: Int = 80
    @State private var cachedFilteredEntries: [HistoryEntry] = []

    private let ruleMatcher = URLRuleMatcher()
    private let pageSize = 80

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Color("HairlineBorder"))
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    filterBar
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 17)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color("SurfaceWindow"))
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
        .onAppear { updateFilter() }
        .onChange(of: scope) { updateFilter() }
        .onChange(of: searchText) { updateFilter() }
        .onChange(of: appState.history.count) { updateFilter() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            SearchField(text: $searchText)
                .frame(width: 220)
        }
        .padding(.horizontal, 24)
        .frame(height: 44)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(HistoryScope.allCases) { option in
                FilterPill(
                    title: option.label,
                    isSelected: scope == option,
                    action: { scope = option }
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.history.isEmpty {
            emptyPanel(
                icon: "clock",
                title: String(localized: "No History"),
                message: String(localized: "Links and files you open will appear here.")
            )
        } else if cachedFilteredEntries.isEmpty {
            emptyPanel(
                icon: "magnifyingglass",
                title: String(localized: "No Results"),
                message: String(localized: "Try a different search or filter.")
            )
        } else {
            historyList
        }
    }

    private func emptyPanel(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }

    // MARK: - List

    private var historyList: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(groupedVisibleEntries) { group in
                historyCard(title: group.title, entries: group.entries)
            }

            if hasMoreEntries {
                loadMoreTrigger
            }
        }
    }

    private func historyCard(title: String, entries: [HistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.44)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                historyRow(entry)
                if index < entries.count - 1 {
                    Rectangle()
                        .fill(Color("HairlineBorder"))
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("SurfaceCard"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
        )
    }

    private var loadMoreTrigger: some View {
        HStack {
            Spacer()
            Text("Loading more…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
            Spacer()
        }
        .onAppear {
            loadMoreEntries()
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            entryIcon(entry)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText(for: entry))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let secondary = secondaryText(for: entry) {
                    Text(secondary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            targetColumn(for: entry)
                .frame(width: 148, alignment: .leading)

            statusView(for: entry)
                .frame(width: 136, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.openedAt, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                Text(dayLabel(for: entry.openedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .contentShape(Rectangle())
        .contextMenu {
            if canCreateRule(from: entry), !ruleAlreadyCovers(entry) {
                Button(String(localized: "Create Rule…")) {
                    ruleFromHistory = makeRule(from: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func entryIcon(_ entry: HistoryEntry) -> some View {
        switch entry.itemKind {
        case .link:
            FaviconView(domain: entry.domain, size: 16)
        case .file:
            Image(systemName: "doc")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }

    private func targetColumn(for entry: HistoryEntry) -> some View {
        let target = targetInfo(for: entry)

        return HStack(spacing: 8) {
            targetIcon(target)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(target.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle = target.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func targetIcon(_ target: HistoryTargetInfo) -> some View {
        if let icon = target.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: target.fallbackSystemImage)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusView(for entry: HistoryEntry) -> some View {
        if let rule = matchingRule(for: entry) {
            Text(String(localized: "Rule: \(rule.pattern)"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color("BrandSuccess"))
                )
        } else {
            Text(entry.itemKind == .link ? String(localized: "Manual pick") : String(localized: "File"))
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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
            if let title = normalized(entry.title), title.localizedCaseInsensitiveCompare(entry.domain) != .orderedSame {
                return title
            }
            return readableURLDetail(entry.url)
        case .file:
            let parts = [
                normalized(entry.fileFormat),
                normalized(entry.fileExtension).map { ".\($0)" },
                normalized(entry.contentTypeIdentifier),
            ].compactMap { $0 }
            return parts.first ?? String(localized: "File")
        }
    }

    private func targetInfo(for entry: HistoryEntry) -> HistoryTargetInfo {
        let browser = targetBrowser(for: entry)
        let app = targetApp(for: entry)

        if entry.targetType == .app, let app {
            return HistoryTargetInfo(
                name: app.displayName,
                subtitle: nil,
                icon: app.icon,
                fallbackSystemImage: "app"
            )
        }

        if let browser {
            return HistoryTargetInfo(
                name: browser.displayName,
                subtitle: normalized(entry.profileName),
                icon: browser.icon,
                fallbackSystemImage: "globe"
            )
        }

        if let app {
            return HistoryTargetInfo(
                name: app.displayName,
                subtitle: nil,
                icon: app.icon,
                fallbackSystemImage: "app"
            )
        }

        return HistoryTargetInfo(
            name: normalized(entry.appName) ?? String(localized: "Unknown"),
            subtitle: normalized(entry.profileName),
            icon: nil,
            fallbackSystemImage: entry.targetType == .app ? "app" : "globe"
        )
    }

    private func targetBrowser(for entry: HistoryEntry) -> InstalledBrowser? {
        if let browserID = entry.browserID,
           let browser = appState.browsers.first(where: { $0.id == browserID })
        {
            return browser
        }
        return appState.browsers.first { $0.displayName == entry.appName }
    }

    private func targetApp(for entry: HistoryEntry) -> InstalledApp? {
        if let browserID = entry.browserID,
           let app = appState.apps.first(where: { $0.id == browserID })
        {
            return app
        }
        return appState.apps.first { $0.displayName == entry.appName }
    }

    private func readableURLDetail(_ rawURL: String) -> String? {
        guard let url = URL(string: rawURL) else { return normalized(rawURL) }

        let path = url.path
        if !path.isEmpty, path != "/" {
            return url.query.map { "\(path)?\($0)" } ?? path
        }

        return url.query.map { "?\($0)" }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(localized: "Today")
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func matchingRule(for entry: HistoryEntry) -> URLRule? {
        guard entry.itemKind == .link, let url = URL(string: entry.url) else { return nil }
        return ruleMatcher.findMatchingRule(for: url, rules: appState.urlRules)
    }

    private func ruleAlreadyCovers(_ entry: HistoryEntry) -> Bool {
        matchingRule(for: entry) != nil
    }

    private func canCreateRule(from entry: HistoryEntry) -> Bool {
        entry.itemKind == .link && (entry.browserID != nil || legacyTargetResolves(for: entry))
    }

    private func legacyTargetResolves(for entry: HistoryEntry) -> Bool {
        appState.browsers.contains(where: { $0.displayName == entry.appName })
            || appState.apps.contains(where: { $0.displayName == entry.appName })
    }

    // MARK: - Rule from history

    private func makeRule(from entry: HistoryEntry) -> URLRule {
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

    // MARK: - Filtering

    private var visibleEntries: [HistoryEntry] {
        Array(cachedFilteredEntries.prefix(visibleCount))
    }

    private var hasMoreEntries: Bool {
        visibleCount < cachedFilteredEntries.count
    }

    private var groupedVisibleEntries: [HistoryDateGroup] {
        var groups: [HistoryDateGroup] = []
        let calendar = Calendar.current

        for entry in visibleEntries {
            let day = calendar.startOfDay(for: entry.openedAt)
            if let lastIndex = groups.indices.last, groups[lastIndex].day == day {
                groups[lastIndex].entries.append(entry)
            } else {
                groups.append(HistoryDateGroup(day: day, title: sectionTitle(for: entry.openedAt), entries: [entry]))
            }
        }

        return groups
    }

    private func updateFilter() {
        let scoped = appState.history.filter { scope.includes($0.openedAt) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cachedFilteredEntries = query.isEmpty ? scoped : scoped.filter {
            $0.domain.lowercased().contains(query)
                || ($0.title?.lowercased().contains(query) ?? false)
                || $0.appName.lowercased().contains(query)
                || $0.url.lowercased().contains(query)
                || ($0.fileName?.lowercased().contains(query) ?? false)
        }
        visibleCount = min(pageSize, cachedFilteredEntries.count)
    }

    private func loadMoreEntries() {
        guard hasMoreEntries else { return }
        visibleCount = min(visibleCount + pageSize, cachedFilteredEntries.count)
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return String(localized: "Today")
        }
        if calendar.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.wide).year())
    }
}

// MARK: - Local controls

private struct HistoryDateGroup: Identifiable {
    let day: Date
    let title: String
    var entries: [HistoryEntry]

    var id: Date {
        day
    }
}

private struct HistoryTargetInfo {
    let name: String
    let subtitle: String?
    let icon: NSImage?
    let fallbackSystemImage: String
}

private enum HistoryScope: CaseIterable, Identifiable {
    case all
    case today
    case week
    case month

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .today: String(localized: "Today")
        case .week: String(localized: "This week")
        case .month: String(localized: "This month")
        }
    }

    func includes(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDateInToday(date)
        case .week:
            return calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(date, equalTo: Date(), toGranularity: .month)
        }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(String(localized: "Search links"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color("SurfaceInset"))
        )
    }
}

private struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Color("BrandAccentDeep") : Color("SurfaceInset"))
                )
        }
        .buttonStyle(.plain)
    }
}
