import Foundation

/// Per-day aggregate of URL opens and time saved.
/// Persisted to `stats.json`; up to 365 days kept.
struct DailyStats: Codable, Equatable {
    /// "yyyy-MM-dd" in the user's local time zone at the time of writing.
    let day: String
    var autoRouteCount: Int
    var pickerHotkeyCount: Int
    var pickerClickCount: Int
    /// Per-rule usage counts — used to build the "Top rules" leaderboard.
    /// Capped to 50 rules per day to keep the file small.
    var rulesCounts: [UUID: Int]
    /// Denormalized total seconds saved on this day. Recomputed on every record.
    var secondsSaved: Int

    init(
        day: String,
        autoRouteCount: Int = 0,
        pickerHotkeyCount: Int = 0,
        pickerClickCount: Int = 0,
        rulesCounts: [UUID: Int] = [:],
        secondsSaved: Int = 0
    ) {
        self.day = day
        self.autoRouteCount = autoRouteCount
        self.pickerHotkeyCount = pickerHotkeyCount
        self.pickerClickCount = pickerClickCount
        self.rulesCounts = rulesCounts
        self.secondsSaved = secondsSaved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        autoRouteCount = try container.decodeIfPresent(Int.self, forKey: .autoRouteCount) ?? 0
        pickerHotkeyCount = try container.decodeIfPresent(Int.self, forKey: .pickerHotkeyCount) ?? 0
        pickerClickCount = try container.decodeIfPresent(Int.self, forKey: .pickerClickCount) ?? 0
        rulesCounts = try container.decodeIfPresent([UUID: Int].self, forKey: .rulesCounts) ?? [:]
        secondsSaved = try container.decodeIfPresent(Int.self, forKey: .secondsSaved) ?? 0
    }

    /// `Calendar.current` at the moment this is parsed; date is interpreted at start-of-day.
    var date: Date? {
        DailyStats.dayFormatter.date(from: day)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
