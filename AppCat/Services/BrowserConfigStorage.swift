import Foundation
import os

final class BrowserConfigStorage {
    static let shared = BrowserConfigStorage()

    private let fileManager = FileManager.default

    func save(_ browsers: [InstalledBrowser]) {
        var seen = Set<String>()
        let configs = browsers.compactMap { browser -> BrowserConfig? in
            guard seen.insert(browser.id).inserted else { return nil }
            return BrowserConfig(from: browser)
        }
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: ConfigDirectory.browsers, options: .atomic)
            Log.settings.debug("Saved \(configs.count) browser configs")
        } catch {
            Log.settings.error("Failed to save browser configs: \(error.localizedDescription)")
        }
    }

    func load() -> [BrowserConfig]? {
        guard fileManager.fileExists(atPath: ConfigDirectory.browsers.path) else { return nil }
        do {
            let data = try Data(contentsOf: ConfigDirectory.browsers)
            let configs = try JSONDecoder().decode([BrowserConfig].self, from: data)
            Log.settings.debug("Loaded \(configs.count) browser configs")
            return configs
        } catch {
            Log.settings.error("Failed to load browser configs: \(error.localizedDescription)")
            return nil
        }
    }
}
