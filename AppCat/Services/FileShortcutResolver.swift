import Foundation
import os

enum FileShortcutResolver {
    static func resolve(_ url: URL) -> URL {
        guard url.isFileURL else { return url }

        switch url.pathExtension.lowercased() {
        case "webloc", "inetloc":
            return resolvePropertyListShortcut(url) ?? url
        case "url":
            return resolveInternetShortcut(url) ?? url
        default:
            return url
        }
    }

    private static func resolvePropertyListShortcut(_ url: URL) -> URL? {
        do {
            let data = try Data(contentsOf: url)
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

    private static func resolveInternetShortcut(_ url: URL) -> URL? {
        do {
            let data = try Data(contentsOf: url)
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
