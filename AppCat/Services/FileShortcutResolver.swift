import Foundation
import os

enum FileShortcutResolver {
    private static let maxShortcutBytes = 1_048_576

    static func resolve(
        _ url: URL,
        readData: (URL) throws -> Data = { try readShortcutData($0) }
    ) -> URL {
        guard url.isFileURL else { return url }

        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= maxShortcutBytes
        else { return url }

        let pathExtension = url.pathExtension.lowercased()
        guard ["webloc", "inetloc", "url"].contains(pathExtension) else { return url }

        do {
            let data = try readData(url)
            guard data.count <= maxShortcutBytes else { return url }
            switch pathExtension {
            case "webloc", "inetloc":
                return try resolvePropertyListShortcut(data) ?? url
            default:
                return resolveInternetShortcut(data) ?? url
            }
        } catch {
            Log.app.debug("Failed to resolve shortcut \(url.path): \(error.localizedDescription)")
            return url
        }
    }

    private static func readShortcutData(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: maxShortcutBytes + 1) ?? Data()
    }

    private static func resolvePropertyListShortcut(_ data: Data) throws -> URL? {
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = plist as? [String: Any],
              let urlString = dictionary["URL"] as? String
        else { return nil }
        return URL(string: urlString)
    }

    private static func resolveInternetShortcut(_ data: Data) -> URL? {
        guard let contents = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(data: data, encoding: .windowsCP1252)
        else { return nil }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("url=") else { continue }

            let value = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: value)
        }
        return nil
    }
}
