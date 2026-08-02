import Foundation
import os

enum FileShortcutResolver {
    private static let maxShortcutBytes = 1_048_576

    static func resolve(
        _ url: URL,
        readData: (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) -> URL {
        guard url.isFileURL else { return url }

        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= maxShortcutBytes
        else { return url }

        switch url.pathExtension.lowercased() {
        case "webloc", "inetloc":
            return resolvePropertyListShortcut(url, readData: readData) ?? url
        case "url":
            return resolveInternetShortcut(url, readData: readData) ?? url
        default:
            return url
        }
    }

    private static func resolvePropertyListShortcut(
        _ url: URL,
        readData: (URL) throws -> Data
    ) -> URL? {
        do {
            let data = try readData(url)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard let dictionary = plist as? [String: Any],
                  let urlString = dictionary["URL"] as? String,
                  let resolvedURL = URL(string: urlString)
            else {
                return nil
            }
            return resolvedURL
        } catch {
            Log.app.debug("Failed to resolve shortcut \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    private static func resolveInternetShortcut(
        _ url: URL,
        readData: (URL) throws -> Data
    ) -> URL? {
        do {
            let data = try readData(url)
            guard let contents = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(data: data, encoding: .windowsCP1252)
            else {
                return nil
            }

            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.lowercased().hasPrefix("url=") else { continue }

                let value = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let resolvedURL = URL(string: value) else { return nil }
                return resolvedURL
            }
            return nil
        } catch {
            Log.app.debug("Failed to resolve internet shortcut \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
}
