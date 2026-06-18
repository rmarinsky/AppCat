import Foundation
import os

struct SuggestionState: Codable {
    var suggestions: [RuleSuggestion]
    var lastAnalyzedAt: Date?

    static let empty = SuggestionState(suggestions: [], lastAnalyzedAt: nil)
}

final class SuggestionStateStorage {
    static let shared = SuggestionStateStorage()

    private let fileManager = FileManager.default

    func save(_ state: SuggestionState) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: ConfigDirectory.suggestionState, options: .atomic)
        } catch {
            Log.settings.error("Failed to save suggestion state: \(error.localizedDescription)")
        }
    }

    func load() -> SuggestionState {
        guard fileManager.fileExists(atPath: ConfigDirectory.suggestionState.path) else { return .empty }
        do {
            let data = try Data(contentsOf: ConfigDirectory.suggestionState)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SuggestionState.self, from: data)
        } catch {
            Log.settings.error("Failed to load suggestion state: \(error.localizedDescription)")
            return .empty
        }
    }
}
