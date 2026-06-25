import Foundation
import os

final class AppConfigStorage {
    static let shared = AppConfigStorage()

    private let fileManager = FileManager.default

    func save(_ apps: [InstalledApp]) {
        var seen = Set<String>()
        let configs = apps.compactMap { app -> AppConfig? in
            guard seen.insert(app.id).inserted else { return nil }
            return AppConfig(from: app)
        }
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: ConfigDirectory.apps, options: .atomic)
            Log.settings.debug("Saved \(configs.count) app configs")
        } catch {
            Log.settings.error("Failed to save app configs: \(error.localizedDescription)")
        }
    }

    func load() -> [AppConfig]? {
        guard fileManager.fileExists(atPath: ConfigDirectory.apps.path) else { return nil }
        do {
            let data = try Data(contentsOf: ConfigDirectory.apps)
            let configs = try JSONDecoder().decode([AppConfig].self, from: data)
            Log.settings.debug("Loaded \(configs.count) app configs")
            return configs
        } catch {
            Log.settings.error("Failed to load app configs: \(error.localizedDescription)")
            return nil
        }
    }
}
