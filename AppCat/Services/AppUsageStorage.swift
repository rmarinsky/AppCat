import Foundation

/// File-backed routing frequency: how often AppCat opens a URL in a given app.
final class AppUsageFileStore {
    static let usage = AppUsageFileStore(
        file: ConfigDirectory.appUsage,
        queueLabel: "ua.com.rmarinsky.appcat.appusage-io"
    )
    private let file: URL
    private let ioQueue: DispatchQueue

    private init(file: URL, queueLabel: String) {
        self.file = file
        self.ioQueue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    func save(_ stats: [String: AppUsage]) {
        let stats = stats
        let fileURL = file
        ioQueue.async {
            do {
                let data = try JSONEncoder().encode(stats)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Log.app.error("Failed to save \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func load() -> [String: AppUsage] {
        let fileURL = file
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([String: AppUsage].self, from: data)
        } catch {
            Log.app.error("Failed to load \(fileURL.lastPathComponent): \(error.localizedDescription)")
            return [:]
        }
    }
}
