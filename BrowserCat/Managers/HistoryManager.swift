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

    @discardableResult
    func record(
        url: URL,
        title: String?,
        appName: String,
        profileName: String?,
        browserID: String?,
        profileDirectoryName: String?,
        targetType: URLRule.TargetType?,
        state: AppState
    ) -> UUID {
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
        return entry.id
    }

    /// Replaces the URL/domain of an existing entry — used after async server-redirect
    /// resolution lands a different final URL than what we recorded at click time.
    func updateURL(id: UUID, finalURL: URL, state: AppState) {
        guard let index = state.history.firstIndex(where: { $0.id == id }) else { return }
        let absolute = finalURL.absoluteString
        guard state.history[index].url != absolute else { return }
        state.history[index].url = absolute
        state.history[index].domain = finalURL.host ?? absolute
        HistoryStorage.shared.save(state.history)
        Log.history.debug("Updated history entry \(id.uuidString) to final URL \(absolute)")
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
