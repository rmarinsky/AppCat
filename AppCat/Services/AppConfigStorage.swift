import Foundation
import os

final class AppConfigStorage {
    static let shared = AppConfigStorage()

    private let fileManager = FileManager.default
    private let fileURL: URL

    init(fileURL: URL = ConfigDirectory.apps) {
        self.fileURL = fileURL
    }

    func save(_ apps: [InstalledApp]) {
        var seen = Set<String>()
        let configs = apps.compactMap { app -> AppConfig? in
            guard seen.insert(app.id).inserted else { return nil }
            return AppConfig(from: app)
        }
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: fileURL, options: .atomic)
            Log.settings.debug("Saved \(configs.count) app configs")
        } catch {
            Log.settings.error("Failed to save app configs: \(error.localizedDescription)")
        }
    }

    func load() -> ConfigLoadResult<[AppConfig]> {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let data = try Data(contentsOf: fileURL)
            let configs = try JSONDecoder().decode([AppConfig].self, from: data)
            Log.settings.debug("Loaded \(configs.count) app configs")
            return .loaded(configs)
        } catch {
            Log.settings.error("Failed to load app configs: \(error.localizedDescription)")
            return .failed(error)
        }
    }
}
