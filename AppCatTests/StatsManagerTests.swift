@testable import AppCat
import XCTest

@MainActor
final class StatsManagerTests: XCTestCase {
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

        manager.recordManualPickerSwitch(at: date)
        manager.recordManualPickerSwitch(at: date)

        let entry = manager.dailyStats.first
        XCTAssertEqual(manager.dailyStats.count, 1)
        XCTAssertEqual(entry?.day, DailyStats.dayKey(for: date))
        XCTAssertEqual(entry?.manualPickerSwitchCount, 2)
        XCTAssertEqual(entry?.secondsSaved, 2)
        XCTAssertEqual(manager.manualPickerSwitchCountTotal, 2)
        XCTAssertEqual(manager.secondsSavedTotal, 2)
        XCTAssertEqual(manager.totalOpenCount, 0)
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
