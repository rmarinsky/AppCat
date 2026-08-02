import Foundation
import os

final class BrowserConfigStorage {
    static let shared = BrowserConfigStorage()

    private let fileManager = FileManager.default
    private let fileURL: URL

    init(fileURL: URL = ConfigDirectory.browsers) {
        self.fileURL = fileURL
    }

    func save(_ browsers: [InstalledBrowser]) {
        var seen = Set<String>()
        let configs = browsers.compactMap { browser -> BrowserConfig? in
            guard seen.insert(browser.id).inserted else { return nil }
            return BrowserConfig(from: browser)
        }
        do {
            let data = try JSONEncoder().encode(configs)
            try data.write(to: fileURL, options: .atomic)
            Log.settings.debug("Saved \(configs.count) browser configs")
        } catch {
            Log.settings.error("Failed to save browser configs: \(error.localizedDescription)")
        }
    }

    func load() -> ConfigLoadResult<[BrowserConfig]> {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .missing }
        do {
            let data = try Data(contentsOf: fileURL)
            let configs = try JSONDecoder().decode([BrowserConfig].self, from: data)
            Log.settings.debug("Loaded \(configs.count) browser configs")
            return .loaded(configs)
        } catch {
            Log.settings.error("Failed to load browser configs: \(error.localizedDescription)")
            return .failed(error)
        }
    }
}
