import Foundation
import os

final class SuggestionDismissalStorage {
    static let shared = SuggestionDismissalStorage()

    private let fileManager = FileManager.default

    func save(_ keys: Set<String>) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(keys).sorted())
            try data.write(to: ConfigDirectory.dismissedSuggestions, options: .atomic)
        } catch {
            Log.settings.error("Failed to save dismissed suggestions: \(error.localizedDescription)")
        }
    }

    func load() -> Set<String> {
        guard fileManager.fileExists(atPath: ConfigDirectory.dismissedSuggestions.path) else { return [] }
        do {
            let data = try Data(contentsOf: ConfigDirectory.dismissedSuggestions)
            let decoder = JSONDecoder()
            let keys = try decoder.decode([String].self, from: data)
            return Set(keys)
        } catch {
            Log.settings.error("Failed to load dismissed suggestions: \(error.localizedDescription)")
            return []
        }
    }
}
