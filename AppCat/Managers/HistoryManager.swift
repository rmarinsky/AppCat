import Foundation
import os
import UniformTypeIdentifiers

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
        let metadata = metadata(for: url)
        let domain = metadata.domain
        let entry = HistoryEntry(
            url: url.absoluteString,
            domain: domain,
            title: title,
            appName: appName,
            profileName: profileName,
            browserID: browserID,
            profileDirectoryName: profileDirectoryName,
            targetType: targetType,
            itemKind: metadata.itemKind,
            fileName: metadata.fileName,
            fileExtension: metadata.fileExtension,
            fileFormat: metadata.fileFormat,
            contentTypeIdentifier: metadata.contentTypeIdentifier
        )
        state.history.insert(entry, at: 0)
        if state.history.count > maxHistoryEntries {
            state.history = Array(state.history.prefix(maxHistoryEntries))
        }
        HistoryStorage.shared.save(state.history)
        log(entry)
        return entry.id
    }

    /// Batched variant for one open request that carries several URLs (e.g. a Finder multi-file
    /// open). Inserts every entry, trims to the cap, and persists **once** instead of re-encoding
    /// and re-writing the whole history per URL. Returns the new entry ids in the same order as
    /// `urls` (the title applies only to the first). Insertion order mirrors the per-URL path
    /// (later URLs end up frontmost) to preserve display behaviour.
    @discardableResult
    func record(
        urls: [URL],
        title: String?,
        appName: String,
        profileName: String?,
        browserID: String?,
        profileDirectoryName: String?,
        targetType: URLRule.TargetType?,
        state: AppState
    ) -> [UUID] {
        guard !urls.isEmpty else { return [] }

        var newEntries: [HistoryEntry] = []
        newEntries.reserveCapacity(urls.count)
        for (index, url) in urls.enumerated() {
            let metadata = metadata(for: url)
            let entry = HistoryEntry(
                url: url.absoluteString,
                domain: metadata.domain,
                title: index == 0 ? title : nil,
                appName: appName,
                profileName: profileName,
                browserID: browserID,
                profileDirectoryName: profileDirectoryName,
                targetType: targetType,
                itemKind: metadata.itemKind,
                fileName: metadata.fileName,
                fileExtension: metadata.fileExtension,
                fileFormat: metadata.fileFormat,
                contentTypeIdentifier: metadata.contentTypeIdentifier
            )
            newEntries.append(entry)
            log(entry)
        }

        state.history.insert(contentsOf: newEntries.reversed(), at: 0)
        if state.history.count > maxHistoryEntries {
            state.history = Array(state.history.prefix(maxHistoryEntries))
        }
        HistoryStorage.shared.save(state.history)
        return newEntries.map(\.id)
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

    private struct EntryMetadata {
        let itemKind: HistoryEntry.ItemKind
        let domain: String
        let fileName: String?
        let fileExtension: String?
        let fileFormat: String?
        let contentTypeIdentifier: String?
    }

    private func metadata(for url: URL) -> EntryMetadata {
        guard url.isFileURL else {
            return EntryMetadata(
                itemKind: .link,
                domain: url.host ?? url.absoluteString,
                fileName: nil,
                fileExtension: nil,
                fileFormat: nil,
                contentTypeIdentifier: nil
            )
        }

        let fileName = url.lastPathComponent.isEmpty ? url.standardizedFileURL.path : url.lastPathComponent
        let fileExtension = normalizedFileExtension(for: url)
        let contentType = contentType(for: url)
        let fileFormat = fileFormat(for: url, fileExtension: fileExtension, contentType: contentType)

        return EntryMetadata(
            itemKind: .file,
            domain: fileName,
            fileName: fileName,
            fileExtension: fileExtension,
            fileFormat: fileFormat,
            contentTypeIdentifier: contentType?.identifier
        )
    }

    private func normalizedFileExtension(for url: URL) -> String? {
        let value = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }

    private func contentType(for url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        if let fileExtension = normalizedFileExtension(for: url) {
            return UTType(filenameExtension: fileExtension)
        }
        return nil
    }

    private func fileFormat(for url: URL, fileExtension: String?, contentType: UTType?) -> String? {
        let fileName = url.lastPathComponent
        if fileName.hasPrefix(".") || fileExtension == nil {
            return fileName.isEmpty ? contentType?.identifier : fileName
        }
        if let fileExtension {
            return ".\(fileExtension)"
        }
        return contentType?.identifier
    }

    private func log(_ entry: HistoryEntry) {
        switch entry.itemKind {
        case .link:
            Log.history.info("Opened link \(entry.url) in \(entry.appName)")
        case .file:
            let format = entry.fileFormat ?? entry.contentTypeIdentifier ?? "unknown"
            let fileName = entry.fileName ?? entry.url
            Log.history.info("Opened file \(fileName) format=\(format) in \(entry.appName)")
        }
    }
}
