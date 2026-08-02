import Foundation
import os

final class HistoryStorage {
    static let shared = HistoryStorage()

    private let fileManager = FileManager.default
    private let fileURL: URL
    // Serial queue keeps writes ordered (no torn files) and off the main thread. `entries` is a
    // value-type array, so the closure captures a safe snapshot.
    private let ioQueue = DispatchQueue(label: "ua.com.rmarinsky.appcat.history-io", qos: .utility)

    init(fileURL: URL = ConfigDirectory.history) {
        self.fileURL = fileURL
    }

    func save(_ entries: [HistoryEntry]) {
        ioQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(entries)
                try data.write(to: self.fileURL, options: .atomic)
                Log.settings.debug("Saved \(entries.count) history entries")
            } catch {
                Log.settings.error("Failed to save history: \(error.localizedDescription)")
            }
        }
    }

    func flush() {
        ioQueue.sync {}
    }

    func load() -> [HistoryEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode([HistoryEntry].self, from: data)
            Log.settings.debug("Loaded \(entries.count) history entries")
            return entries
        } catch {
            Log.settings.error("Failed to load history: \(error.localizedDescription)")
            return []
        }
    }
}
