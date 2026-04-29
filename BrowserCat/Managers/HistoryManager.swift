import Foundation
import os

@MainActor
final class HistoryManager {
    private let maxHistoryEntries = 500

    func load(into state: AppState) {
        var entries = HistoryStorage.shared.load()
        if entries.count > maxHistoryEntries {
            entries = Array(entries.prefix(maxHistoryEntries))
            HistoryStorage.shared.save(entries)
        }
        state.history = entries
    }

    func record(
        url: URL,
        title: String?,
        appName: String,
        profileName: String?,
        browserID: String?,
        profileDirectoryName: String?,
        targetType: URLRule.TargetType?,
        state: AppState
    ) {
        let domain = url.host ?? url.absoluteString
        let entry = HistoryEntry(
            url: url.absoluteString,
            domain: domain,
            title: title,
            appName: appName,
            profileName: profileName,
            browserID: browserID,
            profileDirectoryName: profileDirectoryName,
            targetType: targetType
        )
        state.history.insert(entry, at: 0)
        if state.history.count > maxHistoryEntries {
            state.history = Array(state.history.prefix(maxHistoryEntries))
        }
        HistoryStorage.shared.save(state.history)
        Log.history.debug("Recorded history entry for \(domain)")
    }

    func delete(ids: Set<UUID>, state: AppState) {
        state.history.removeAll { ids.contains($0.id) }
        HistoryStorage.shared.save(state.history)
        Log.history.debug("Deleted \(ids.count) history entries")
    }

    func clearAll(state: AppState) {
        state.history.removeAll()
        HistoryStorage.shared.save(state.history)
        Log.history.debug("Cleared all history")
    }
}
