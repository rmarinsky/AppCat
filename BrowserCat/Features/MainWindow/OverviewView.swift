import Charts
import SwiftUI

struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.statsManager) private var statsManager

    @State private var scope: OverviewScope = .week

    var body: some View {
        Group {
            if let stats = statsManager, stats.totalOpenCount > 0 {
                content(stats: stats)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(String(localized: "Overview"))
    }

    // MARK: - Content

    private func content(stats: StatsManager) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                heroCard(stats: stats)
                metricGrid(stats: stats)
                chartCard(stats: stats)
                topRulesCard(stats: stats)
                overviewFooter(stats: stats)
            }
            .padding(16)
        }
    }

    // MARK: - Hero card (the ONE tinted card per screen)

    private func heroCard(stats: StatsManager) -> some View {
        let seconds = scopeSeconds(stats: stats)
        return VStack(alignment: .leading, spacing: 12) {
            // Scope picker
            Picker("", selection: $scope) {
                ForEach(OverviewScope.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Eyebrow
            Text("TIME NOT TYPED")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color("BrandAccentDeep"))
                .tracking(0.5)

            // Hero number
            Text(TimeSavedFormatter.short(seconds: seconds))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: seconds)

            // Witty subline
            Text(scope.subline)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            // Quiet trend (no green pill — arrow only)
            if scope == .month, let delta = stats.monthOverMonthDelta {
                quietTrend(delta: delta)
            }

            Divider()
                .opacity(0.5)

            // Route-flow hero graphic
            RouteFlowChip(history: appState.history, browsers: appState.browsers)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color("BrandTintSoft"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color("BrandTintBorder"), lineWidth: 1)
        )
    }

    private func quietTrend(delta: Double) -> some View {
        let percent = Int((abs(delta) * 100).rounded())
        let isUp = delta >= 0
        return HStack(spacing: 3) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isUp ? .green : Color.secondary)
            Text(isUp ? "+\(percent)% vs last month" : "\(percent)% vs last month")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func scopeSeconds(stats: StatsManager) -> Int {
        switch scope {
        case .day: stats.secondsSavedToday
        case .week: stats.secondsSavedThisWeek
        case .month: stats.secondsSavedThisMonth
        case .all: stats.secondsSavedTotal
        }
    }

    // MARK: - Metric grid (4 neutral cards)

    private func metricGrid(stats: StatsManager) -> some View {
        let totalAutoRouted = stats.dailyStats.reduce(0) { $0 + $1.autoRouteCount }
        let activeRules = appState.urlRules.filter(\.isEnabled).count

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(
                icon: "arrow.triangle.branch",
                value: "\(stats.totalOpenCount)",
                label: String(localized: "links herded")
            )
            MetricCard(
                icon: "bolt.fill",
                value: "\(totalAutoRouted)",
                label: String(localized: "auto-routed")
            )
            MetricCard(
                icon: "checkmark.circle.fill",
                value: "\(activeRules)",
                label: String(localized: "active rules")
            )
            TopBrowserCard(history: appState.history)
        }
    }

    // MARK: - Chart card

    private func chartCard(stats: StatsManager) -> some View {
        let series = stats.dailySeries(lastDays: 7)
        let maxSec = series.map(\.seconds).max() ?? 0
        let avgSec = series.isEmpty ? 0 : series.reduce(0) { $0 + $1.seconds } / series.count
        let calendar = Calendar.current

        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "This week"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Chart {
                // Hairline baseline
                RuleMark(y: .value("", 0))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.3))

                // Dashed average
                if avgSec > 0 {
                    RuleMark(y: .value("avg", avgSec))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                }

                ForEach(series, id: \.date) { point in
                    let isToday = calendar.isDateInToday(point.date)
                    let opacity = maxSec > 0
                        ? (isToday ? 1.0 : 0.25 + 0.6 * Double(point.seconds) / Double(maxSec))
                        : 0.3
                    let displaySeconds = point.seconds == 0 ? (isToday ? 0 : 1) : point.seconds

                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("s", displaySeconds)
                    )
                    .foregroundStyle(
                        isToday
                            ? Color("BrandAccentDeep")
                            : Color.accentColor.opacity(opacity)
                    )
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        if isToday && point.seconds > 0 {
                            Text(TimeSavedFormatter.short(seconds: point.seconds))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color("BrandAccentDeep"))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                        .font(.system(size: 9))
                }
            }
            .frame(height: 120)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.tertiary)
        )
    }

    // MARK: - Top rules

    private func topRulesCard(stats: StatsManager) -> some View {
        let entries = stats.topRules(lastDays: 7, limit: 5, currentRules: appState.urlRules)
        guard !entries.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Top rules"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    topRuleRow(entry: entry)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background.tertiary)
            )
        )
    }

    private func topRuleRow(entry: (rule: URLRule?, seconds: Int)) -> some View {
        let targetName: String = {
            guard let rule = entry.rule else { return String(localized: "Removed rule") }
            if let b = appState.browsers.first(where: { $0.id == rule.browserID }) {
                if let dir = rule.profileDirectoryName,
                   let p = b.profiles.first(where: { $0.directoryName == dir }) {
                    return "\(b.displayName) · \(p.displayName)"
                }
                return b.displayName
            }
            if let a = appState.apps.first(where: { $0.id == rule.browserID }) { return a.displayName }
            return String(localized: "Unknown")
        }()

        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color("BrandTintSoft"))
                    .frame(width: 26, height: 26)
                Image(systemName: entry.rule == nil ? "questionmark.circle" : "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color("BrandAccentDeep"))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.rule?.pattern ?? String(localized: "Removed rule"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(targetName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(TimeSavedFormatter.short(seconds: entry.seconds))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Footer

    private func overviewFooter(stats: StatsManager) -> some View {
        HStack(spacing: 6) {
            if let date = stats.firstUseDate {
                Text(String(localized: "Tracking since \(date.formatted(date: .abbreviated, time: .omitted))"))
            }
            Spacer()
            Text(String(localized: "Total: \(TimeSavedFormatter.short(seconds: stats.secondsSavedTotal))"))
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color("BrandTintSoft"))
                    .frame(width: 64, height: 64)
                Image(systemName: "clock.badge")
                    .font(.system(size: 28))
                    .foregroundStyle(Color("BrandAccentDeep"))
            }
            Text(String(localized: "No stats yet"))
                .font(.headline)
            Text(String(localized: "Open some links and BrowserCat will show how much time it saves you."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Scope enum

enum OverviewScope: String, CaseIterable, Identifiable {
    case day, week, month, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        case .all: String(localized: "All time")
        }
    }

    var subline: String {
        switch self {
        case .day: String(localized: "saved today by routing links automatically")
        case .week: String(localized: "saved this week — routing decisions you didn't even notice")
        case .month: String(localized: "saved this month opening the right browser first time")
        case .all: String(localized: "saved in total — and counting")
        }
    }
}

// MARK: - Metric card

private struct MetricCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color("BrandTintSoft"))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color("BrandAccentDeep"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.tertiary)
        )
    }
}

// MARK: - Top browser share card

private struct TopBrowserCard: View {
    let history: [HistoryEntry]

    private var topBrowser: (name: String, percent: Int) {
        let links = history.filter { $0.itemKind == .link }
        guard !links.isEmpty else { return ("–", 0) }
        var counts: [String: Int] = [:]
        for entry in links { counts[entry.appName, default: 0] += 1 }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return ("–", 0) }
        return (top.key, Int(Double(top.value) / Double(links.count) * 100))
    }

    var body: some View {
        let (name, pct) = topBrowser
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color("BrandTintSoft"))
                    .frame(width: 36, height: 36)
                Image(systemName: "globe")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color("BrandAccentDeep"))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(pct)%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.tertiary)
        )
    }
}

// MARK: - Route-flow hero graphic

private struct RouteFlowChip: View {
    let history: [HistoryEntry]
    let browsers: [InstalledBrowser]

    private var routeExample: (domain: String, browser: String, profile: String?)? {
        guard let last = history.first(where: { $0.itemKind == .link }) else { return nil }
        return (last.domain, last.appName, last.profileName)
    }

    var body: some View {
        if let route = routeExample {
            HStack(spacing: 6) {
                // Domain chip
                Text(route.domain.isEmpty ? "example.com" : route.domain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.background.secondary)
                    )

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color("BrandAccentDeep"))

                // Browser chip
                HStack(spacing: 4) {
                    Image(systemName: "safari")
                        .font(.system(size: 10))
                        .foregroundStyle(Color("BrandAccentDeep"))
                    Text(route.browser)
                        .font(.system(size: 11))
                    if let profile = route.profile {
                        Text("· \(profile)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.background.secondary)
                )
            }
        }
    }
}
