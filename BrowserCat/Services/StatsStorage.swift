import Foundation

final class StatsStorage {
    static let shared = StatsStorage()

    private let fileManager = FileManager.default

    func save(_ entries: [DailyStats]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: ConfigDirectory.stats, options: .atomic)
            Log.settings.debug("Saved \(entries.count) daily stats entries")
        } catch {
            Log.settings.error("Failed to save stats: \(error.localizedDescription)")
        }
    }

    func load() -> [DailyStats] {
        guard fileManager.fileExists(atPath: ConfigDirectory.stats.path) else { return [] }
        do {
            let data = try Data(contentsOf: ConfigDirectory.stats)
            let entries = try JSONDecoder().decode([DailyStats].self, from: data)
            Log.settings.debug("Loaded \(entries.count) daily stats entries")
            return entries
        } catch {
            Log.settings.error("Failed to load stats: \(error.localizedDescription)")
            return []
        }
    }
}
