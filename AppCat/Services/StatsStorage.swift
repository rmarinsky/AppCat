import Foundation

protocol StatsStoring {
    func save(_ entries: [DailyStats])
    func load() -> [DailyStats]
}

final class StatsStorage: StatsStoring {
    static let shared = StatsStorage()

    private let fileManager = FileManager.default
    private let fileURL: URL
    // Serial, off-main; preserves write order. `entries` is a value-type snapshot.
    private let ioQueue = DispatchQueue(label: "ua.com.rmarinsky.appcat.stats-io", qos: .utility)

    init(fileURL: URL = ConfigDirectory.stats) {
        self.fileURL = fileURL
    }

    func save(_ entries: [DailyStats]) {
        ioQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(entries)
                try data.write(to: self.fileURL, options: .atomic)
                Log.settings.debug("Saved \(entries.count) daily stats entries")
            } catch {
                Log.settings.error("Failed to save stats: \(error.localizedDescription)")
            }
        }
    }

    func flush() {
        ioQueue.sync {}
    }

    func load() -> [DailyStats] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let entries = try JSONDecoder().decode([DailyStats].self, from: data)
            Log.settings.debug("Loaded \(entries.count) daily stats entries")
            return entries
        } catch {
            Log.settings.error("Failed to load stats: \(error.localizedDescription)")
            return []
        }
    }
}
