import Foundation
import Observation
import os

@Observable
@MainActor
final class StatsManager {
    private(set) var dailyStats: [DailyStats] = []
    private(set) var firstUseDate: Date?

    private static let maxDays = 365
    private static let maxRulesPerDay = 50

    private let urlRuleMatcher = URLRuleMatcher()

    // MARK: - Lifecycle

    func load() {
        let entries = StatsStorage.shared.load()
        dailyStats = entries
        firstUseDate = entries.compactMap(\.date).min()
        Log.settings.debug("StatsManager loaded \(entries.count) days")
    }

    func reset() {
        dailyStats = []
        firstUseDate = nil
        StatsStorage.shared.save([])
    }

    // MARK: - Recording

    func record(_ source: OpenSource, at date: Date = Date()) {
        let key = DailyStats.dayKey(for: date)
        var entry: DailyStats
        if let idx = dailyStats.firstIndex(where: { $0.day == key }) {
            entry = dailyStats[idx]
            dailyStats.remove(at: idx)
        } else {
            entry = DailyStats(day: key)
        }

        switch source {
        case let .autoRoute(ruleID):
            entry.autoRouteCount += 1
            if entry.rulesCounts.count < Self.maxRulesPerDay || entry.rulesCounts[ruleID] != nil {
                entry.rulesCounts[ruleID, default: 0] += 1
            }
        case .pickerHotkey:
            entry.pickerHotkeyCount += 1
        case .pickerClick:
            entry.pickerClickCount += 1
        }
        entry.secondsSaved += Int(source.secondsSaved)
        dailyStats.append(entry)

        trimAndSave()
        if firstUseDate == nil { firstUseDate = entry.date }
    }

    /// One-time migration: rebuild stats from existing history if stats.json is empty.
    /// Re-runs the URL rule matcher against past URLs to estimate auto-route counts.
    func backfillIfNeeded(history: [HistoryEntry], rules: [URLRule]) {
        guard dailyStats.isEmpty, !history.isEmpty else { return }

        var byDay: [String: DailyStats] = [:]
        for entry in history {
            let key = DailyStats.dayKey(for: entry.openedAt)
            var day = byDay[key] ?? DailyStats(day: key)
            if entry.itemKind == .link,
               let url = URL(string: entry.url),
               let rule = urlRuleMatcher.findMatchingRule(for: url, rules: rules)
            {
                day.autoRouteCount += 1
                day.secondsSaved += Int(TimeSavedConstants.autoRoute)
                if day.rulesCounts.count < Self.maxRulesPerDay || day.rulesCounts[rule.id] != nil {
                    day.rulesCounts[rule.id, default: 0] += 1
                }
            } else {
                // Best-guess: assume the user clicked rather than used a hotkey.
                day.pickerClickCount += 1
                day.secondsSaved += Int(TimeSavedConstants.pickerClick)
            }
            byDay[key] = day
        }

        dailyStats = byDay.values.sorted { $0.day < $1.day }
        firstUseDate = dailyStats.compactMap(\.date).min()
        trimAndSave()
        Log.settings.info("StatsManager backfilled \(self.dailyStats.count) days from history")
    }

    private func trimAndSave() {
        let sorted = dailyStats.sorted { $0.day < $1.day }
        let trimmed = sorted.suffix(Self.maxDays)
        dailyStats = Array(trimmed)
        StatsStorage.shared.save(dailyStats)
    }

    // MARK: - Derived metrics

    var secondsSavedToday: Int {
        let key = DailyStats.dayKey(for: Date())
        return dailyStats.first(where: { $0.day == key })?.secondsSaved ?? 0
    }

    var secondsSavedThisWeek: Int {
        sumSeconds(in: rangeOfThisWeek())
    }

    var secondsSavedThisMonth: Int {
        sumSeconds(in: rangeOfThisMonth())
    }

    var secondsSavedTotal: Int {
        dailyStats.reduce(0) { $0 + $1.secondsSaved }
    }

    var totalOpenCount: Int {
        dailyStats.reduce(0) { $0 + $1.autoRouteCount + $1.pickerHotkeyCount + $1.pickerClickCount }
    }

    /// Last `days` days, oldest → newest. Days with no opens get a 0-second entry so charts
    /// render a continuous timeline.
    func dailySeries(lastDays: Int) -> [(date: Date, seconds: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [(Date, Int)] = []
        for offset in (0..<lastDays).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = DailyStats.dayKey(for: date)
            let seconds = dailyStats.first(where: { $0.day == key })?.secondsSaved ?? 0
            result.append((date, seconds))
        }
        return result
    }

    /// Top rules over the last `days` days. Rules deleted from the user's rule list show up
    /// with `rule == nil` so their saved time is still credited.
    func topRules(lastDays: Int, limit: Int, currentRules: [URLRule]) -> [(rule: URLRule?, seconds: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -(lastDays - 1), to: today) else { return [] }

        var counts: [UUID: Int] = [:]
        for day in dailyStats {
            guard let date = day.date, date >= cutoff else { continue }
            for (ruleID, count) in day.rulesCounts {
                counts[ruleID, default: 0] += count
            }
        }

        let secondsPerAutoRoute = Int(TimeSavedConstants.autoRoute)
        let sorted = counts
            .map { (id: $0.key, seconds: $0.value * secondsPerAutoRoute) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(limit)

        return sorted.map { entry -> (rule: URLRule?, seconds: Int) in
            let rule = currentRules.first { $0.id == entry.id }
            return (rule, entry.seconds)
        }
    }

    /// Month-over-month delta, e.g. 0.32 = +32%. nil when previous month has no data.
    var monthOverMonthDelta: Double? {
        let current = secondsSavedThisMonth
        let prev = sumSeconds(in: rangeOfPreviousMonth())
        guard prev > 0 else { return nil }
        return (Double(current) - Double(prev)) / Double(prev)
    }

    // MARK: - Date helpers

    private func sumSeconds(in range: ClosedRange<Date>) -> Int {
        dailyStats.reduce(0) { acc, day in
            guard let date = day.date, range.contains(date) else { return acc }
            return acc + day.secondsSaved
        }
    }

    private func rangeOfThisWeek() -> ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let start = calendar.date(from: comps) ?? now
        return start...now
    }

    private func rangeOfThisMonth() -> ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: comps) ?? now
        return start...now
    }

    private func rangeOfPreviousMonth() -> ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.year, .month], from: now)
        let startOfThis = calendar.date(from: comps) ?? now
        guard let startOfPrev = calendar.date(byAdding: .month, value: -1, to: startOfThis),
              let endOfPrev = calendar.date(byAdding: .day, value: -1, to: startOfThis)
        else { return now...now }
        return startOfPrev...endOfPrev
    }
}
