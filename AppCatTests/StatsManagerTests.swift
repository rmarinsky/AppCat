@testable import AppCat
import XCTest

@MainActor
final class StatsManagerTests: XCTestCase {
    func testStatsFlushWaitsForQueuedSave() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("stats-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let storage = StatsStorage(fileURL: fileURL)
        let entries = [DailyStats(day: "2026-08-02", pickerClickCount: 1)]

        storage.save(entries)
        storage.flush()

        XCTAssertEqual(storage.load(), entries)
    }

    func testDailyStatsLegacyDecodeDefaultsManualPickerSwitchCountToZero() throws {
        let data = """
        {
          "day": "2026-07-08",
          "autoRouteCount": 2,
          "pickerHotkeyCount": 1,
          "pickerClickCount": 3,
          "secondsSaved": 19
        }
        """.data(using: .utf8)!

        let stats = try JSONDecoder().decode(DailyStats.self, from: data)

        XCTAssertEqual(stats.manualPickerSwitchCount, 0)
        XCTAssertEqual(stats.manualPickerTargetCounts, [:])
        XCTAssertEqual(stats.secondsSaved, 19)
    }

    func testRecordManualPickerSwitchAddsCountAndConservativeSecond() {
        let storage = FakeStatsStorage()
        let manager = StatsManager(storage: storage)
        let date = DateComponents(
            calendar: .current,
            year: 2026,
            month: 7,
            day: 8,
            hour: 12
        ).date!

        manager.recordManualPickerSwitch(targetID: "Com.Test.Editor", at: date)
        manager.recordManualPickerSwitch(targetID: "com.test.editor", at: date)

        let entry = manager.dailyStats.first
        XCTAssertEqual(manager.dailyStats.count, 1)
        XCTAssertEqual(entry?.day, DailyStats.dayKey(for: date))
        XCTAssertEqual(entry?.manualPickerSwitchCount, 2)
        XCTAssertEqual(entry?.manualPickerTargetCounts, ["com.test.editor": 2])
        XCTAssertEqual(entry?.secondsSaved, 2)
        XCTAssertEqual(manager.manualPickerSwitchCountTotal, 2)
        XCTAssertEqual(manager.secondsSavedTotal, 2)
        XCTAssertEqual(manager.totalOpenCount, 0)
        XCTAssertEqual(storage.savedEntries.last, manager.dailyStats)
    }

    func testRecentManualPickerTargetCountsUsesTrailingSevenCalendarDays() throws {
        let storage = FakeStatsStorage()
        let manager = StatsManager(storage: storage)
        let calendar = Calendar.current
        let today = try XCTUnwrap(DateComponents(
            calendar: calendar,
            year: 2026,
            month: 7,
            day: 29,
            hour: 12
        ).date)
        let sixDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: today))
        let sevenDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: today))

        manager.recordManualPickerSwitch(targetID: "com.test.expired", at: sevenDaysAgo)
        manager.recordManualPickerSwitch(targetID: "com.test.editor", at: sixDaysAgo)
        manager.recordManualPickerSwitch(targetID: "com.test.editor", at: today)

        XCTAssertEqual(
            manager.recentManualPickerTargetCounts(days: 7, today: today),
            ["com.test.editor": 2]
        )
    }

    func testLoadRemovesExpiredPickerTargetIdentityButKeepsAggregateStats() throws {
        let calendar = Calendar.current
        let today = try XCTUnwrap(DateComponents(
            calendar: calendar,
            year: 2026,
            month: 7,
            day: 29,
            hour: 12
        ).date)
        let recentDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: today))
        let expiredDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: today))
        let expired = DailyStats(
            day: DailyStats.dayKey(for: expiredDate),
            manualPickerSwitchCount: 3,
            manualPickerTargetCounts: ["com.test.expired": 3],
            secondsSaved: 3
        )
        let recent = DailyStats(
            day: DailyStats.dayKey(for: recentDate),
            manualPickerSwitchCount: 2,
            manualPickerTargetCounts: ["com.test.recent": 2],
            secondsSaved: 2
        )
        let storage = FakeStatsStorage(loadedEntries: [expired, recent])
        let manager = StatsManager(storage: storage)

        manager.load(today: today)

        XCTAssertEqual(manager.dailyStats[0].manualPickerTargetCounts, [:])
        XCTAssertEqual(manager.dailyStats[0].manualPickerSwitchCount, 3)
        XCTAssertEqual(manager.dailyStats[0].secondsSaved, 3)
        XCTAssertEqual(manager.dailyStats[1].manualPickerTargetCounts, ["com.test.recent": 2])
        XCTAssertEqual(storage.savedEntries.last, manager.dailyStats)
    }

    func testRecordingRemovesExpiredPickerTargetIdentity() throws {
        let calendar = Calendar.current
        let today = try XCTUnwrap(DateComponents(
            calendar: calendar,
            year: 2026,
            month: 7,
            day: 29,
            hour: 12
        ).date)
        let expiredDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: today))
        let storage = FakeStatsStorage(loadedEntries: [
            DailyStats(
                day: DailyStats.dayKey(for: expiredDate),
                manualPickerSwitchCount: 1,
                manualPickerTargetCounts: ["com.test.expired": 1],
                secondsSaved: 1
            ),
        ])
        let manager = StatsManager(storage: storage)
        manager.load(today: expiredDate)

        manager.recordManualPickerSwitch(targetID: "com.test.current", at: today)

        XCTAssertEqual(manager.dailyStats[0].manualPickerTargetCounts, [:])
        XCTAssertEqual(manager.dailyStats[0].manualPickerSwitchCount, 1)
    }

    func testLoadClearsFutureAndInvalidPickerTargetIdentities() throws {
        let calendar = Calendar.current
        let today = try XCTUnwrap(DateComponents(
            calendar: calendar,
            year: 2026,
            month: 7,
            day: 29,
            hour: 12
        ).date)
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let future = DailyStats(
            day: DailyStats.dayKey(for: tomorrow),
            manualPickerSwitchCount: 2,
            manualPickerTargetCounts: ["com.test.future": 2],
            secondsSaved: 2
        )
        let invalid = DailyStats(
            day: "not-a-day",
            manualPickerSwitchCount: 3,
            manualPickerTargetCounts: ["com.test.invalid": 3],
            secondsSaved: 3
        )
        let storage = FakeStatsStorage(loadedEntries: [future, invalid])
        let manager = StatsManager(storage: storage)

        manager.load(today: today)

        XCTAssertEqual(manager.dailyStats.map(\.manualPickerTargetCounts), [[:], [:]])
        XCTAssertEqual(manager.dailyStats.map(\.manualPickerSwitchCount), [2, 3])
        XCTAssertEqual(manager.dailyStats.map(\.secondsSaved), [2, 3])
        XCTAssertEqual(storage.savedEntries.last, manager.dailyStats)
    }
}

private final class FakeStatsStorage: StatsStoring {
    private let loadedEntries: [DailyStats]
    private(set) var savedEntries: [[DailyStats]] = []

    init(loadedEntries: [DailyStats] = []) {
        self.loadedEntries = loadedEntries
    }

    func load() -> [DailyStats] {
        loadedEntries
    }

    func save(_ entries: [DailyStats]) {
        savedEntries.append(entries)
    }
}
