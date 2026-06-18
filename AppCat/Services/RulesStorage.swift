import Foundation
import os

final class RulesStorage {
    static let shared = RulesStorage()

    private let fileManager = FileManager.default

    func save(_ rules: [URLRule]) {
        do {
            let data = try JSONEncoder().encode(rules)
            try data.write(to: ConfigDirectory.rules, options: .atomic)
            Log.settings.debug("Saved \(rules.count) URL rules")
        } catch {
            Log.settings.error("Failed to save URL rules: \(error.localizedDescription)")
        }
    }

    func load() -> [URLRule] {
        guard fileManager.fileExists(atPath: ConfigDirectory.rules.path) else { return [] }
        do {
            let data = try Data(contentsOf: ConfigDirectory.rules)
            let rules = try JSONDecoder().decode([URLRule].self, from: data)
            Log.settings.debug("Loaded \(rules.count) URL rules")
            return rules
        } catch {
            Log.settings.error("Failed to load URL rules: \(error.localizedDescription)")
            return []
        }
    }
}
