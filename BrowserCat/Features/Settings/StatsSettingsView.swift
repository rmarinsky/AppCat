import Charts
import SwiftUI

struct StatsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.statsManager) private var statsManager

    @State private var scope: Scope = .month

    enum Scope: String, CaseIterable, Identifiable {
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
    }

    var body: some View {
        Group {
            if let stats = statsManager, stats.totalOpenCount > 0 {
                content(stats: stats)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(stats: StatsManager) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                heroCard(stats: stats)
                chartCard(stats: stats)
                topRulesCard(stats: stats)
                footer(stats: stats)
            }
            .padding(16)
        }
    }

    // MARK: - Hero card

    private func heroCard(stats: StatsManager) -> some View {
        let secondsForScope: Int = switch scope {
        case .day: stats.secondsSavedToday
        case .week: stats.secondsSavedThisWeek
        case .month: stats.secondsSavedThisMonth
        case .all: stats.secondsSavedTotal
        }

        return VStack(spacing: 12) {
            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 6) {
                Text(TimeSavedFormatter.short(seconds: secondsForScope))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: secondsForScope)

                Text(scopeSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if scope == .month, let delta = stats.monthOverMonthDelta {
                    deltaPill(delta: delta)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.tertiary)
        )
    }

    private var scopeSubtitle: String {
        switch scope {
        case .day: String(localized: "saved today")
        case .week: String(localized: "saved this week")
        case .month: String(localized: "saved this month")
        case .all: String(localized: "saved in total")
        }
    }

    private func deltaPill(delta: Double) -> some View {
        let percent = Int((delta * 100).rounded())
        let isUp = delta >= 0
        return HStack(spacing: 4) {
            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text(isUp ? "+\(percent)% \(String(localized: "vs last month"))"
                      : "\(percent)% \(String(localized: "vs last month"))")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(isUp ? Color.green : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill((isUp ? Color.green : Color.secondary).opacity(0.12))
        )
    }

    // MARK: - Chart

    private func chartCard(stats: StatsManager) -> some View {
        let series = stats.dailySeries(lastDays: 30)
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Last 30 days"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Chart {
                ForEach(series, id: \.date) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Seconds", point.seconds)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(3)
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { value in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                        .font(.system(size: 9))
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.tertiary)
        )
    }

    // MARK: - Top rules

    private func topRulesCard(stats: StatsManager) -> some View {
        let entries = stats.topRules(lastDays: 30, limit: 5, currentRules: appState.urlRules)
        return VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Top rules"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if entries.isEmpty {
                Text(String(localized: "Add a URL rule to see auto-routing stats here."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    topRuleRow(entry: entry)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.tertiary)
        )
    }

    @ViewBuilder
    private func topRuleRow(entry: (rule: URLRule?, seconds: Int)) -> some View {
        let target: String = {
            guard let rule = entry.rule else { return String(localized: "Removed rule") }
            if let browser = appState.browsers.first(where: { $0.id == rule.browserID }) {
                if let dir = rule.profileDirectoryName,
                   let profile = browser.profiles.first(where: { $0.directoryName == dir })
                {
                    return "\(browser.displayName) · \(profile.displayName)"
                }
                return browser.displayName
            }
            if let app = appState.apps.first(where: { $0.id == rule.browserID }) {
                return app.displayName
            }
            return String(localized: "Unknown")
        }()

        HStack(spacing: 10) {
            Image(systemName: entry.rule == nil ? "questionmark.circle" : "arrow.triangle.branch")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.rule?.pattern ?? String(localized: "Removed rule"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(target)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(TimeSavedFormatter.short(seconds: entry.seconds))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(stats: StatsManager) -> some View {
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
        VStack(spacing: 8) {
            Image(systemName: "clock.badge")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(String(localized: "No stats yet"))
                .font(.headline)
            Text(String(localized: "Open some links and BrowserCat will show how much time it saves you."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}
