import Foundation
import os

final class AppUsageStorage {
    static let shared = AppUsageStorage()
    private let fileManager = FileManager.default

    func save(_ usage: [String: AppUsage]) {
        do {
            let data = try JSONEncoder().encode(usage)
            try data.write(to: ConfigDirectory.appUsage, options: .atomic)
        } catch {
            Log.settings.error("Failed to save app usage: \(error.localizedDescription)")
        }
    }

    func load() -> [String: AppUsage] {
        guard fileManager.fileExists(atPath: ConfigDirectory.appUsage.path) else { return [:] }
        do {
            let data = try Data(contentsOf: ConfigDirectory.appUsage)
            return try JSONDecoder().decode([String: AppUsage].self, from: data)
        } catch {
            Log.settings.error("Failed to load app usage: \(error.localizedDescription)")
            return [:]
        }
    }
}
