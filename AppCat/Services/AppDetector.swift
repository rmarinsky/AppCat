import AppKit
import os
import UniformTypeIdentifiers

/// Deliberately not `@MainActor`: detection is pure disk/Bundle/LaunchServices work
/// (`FileManager`, `Bundle`, `NSWorkspace.icon`), all safe off the main thread — so
/// `AppManager.refreshAppsInBackground` can run a full rescan detached.
final class AppDetector: Sendable {
    /// Detect installed apps from the curated AppDefinition registry.
    /// Only shows apps explicitly listed in the registry (like Browserosaurus).
    func detectApps() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seenBundleIDs: Set<String> = []
        var index = 0

        for definition in AppDefinition.registry {
            guard seenBundleIDs.insert(definition.bundleID).inserted else { continue }

            guard let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: definition.bundleID
            ) else { continue }

            let bundle = Bundle(url: appURL)
            let icon = AppIconLoader.icon(forFile: appURL.path)
            let version = bundle?.infoDictionary?["CFBundleShortVersionString"] as? String

            let schemes = readURLSchemes(from: appURL)

            apps.append(InstalledApp(
                id: definition.bundleID,
                displayName: definition.displayName,
                appURL: appURL,
                urlSchemes: schemes.isEmpty ? [definition.urlScheme].compactMap { $0 } : schemes,
                hostPatterns: definition.hostPatterns,
                isVisible: true,
                sortOrder: index,
                isSystemApp: Self.isSystemApp(bundleID: definition.bundleID, appURL: appURL),
                icon: icon,
                version: version,
                detectedFormats: readFileFormats(from: appURL, definition: definition)
            ))
            index += 1
        }

        Log.apps.info("Detected \(apps.count) apps")
        return apps
    }

    /// Detect *all* installed apps from the standard application directories.
    /// Registry apps keep their curated metadata (host patterns, deep links); everything
    /// else becomes a generic open target. Browsers are filtered out later by AppManager.
    func detectAllApps() -> [InstalledApp] {
        let fm = FileManager.default
        let dirs = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ].map { URL(fileURLWithPath: $0) }

        var seen: Set<String> = []
        var apps: [InstalledApp] = []
        let mainID = Bundle.main.bundleIdentifier

        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                guard id != mainID, seen.insert(id).inserted else { continue }

                let definition = AppDefinition.registryByID[id]
                let finderName = fm.displayName(atPath: url.path)
                let name = finderName.hasSuffix(".app") ? String(finderName.dropLast(4)) : finderName
                let icon = AppIconLoader.icon(forFile: url.path)
                let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
                let schemes = readURLSchemes(from: url)

                apps.append(InstalledApp(
                    id: id,
                    displayName: definition?.displayName ?? name,
                    appURL: url,
                    urlSchemes: schemes.isEmpty ? [definition?.urlScheme].compactMap { $0 } : schemes,
                    hostPatterns: definition?.hostPatterns ?? [],
                    isVisible: true,
                    sortOrder: apps.count,
                    isSystemApp: Self.isSystemApp(bundleID: id, appURL: url),
                    icon: icon,
                    version: version,
                    detectedFormats: readFileFormats(from: url, definition: definition)
                ))
            }
        }

        Log.apps.info("Detected \(apps.count) installed apps")
        return apps
    }

    // MARK: - Private

    /// An app counts as Apple/system when it ships under `/System/` or carries a `com.apple.*`
    /// bundle id. These are grouped at the bottom of the Apps screen.
    private static func isSystemApp(bundleID: String, appURL: URL) -> Bool {
        bundleID.hasPrefix("com.apple.") || appURL.path.hasPrefix("/System/")
    }

    /// File extensions an app declares it can open, read from its Info.plist
    /// `CFBundleDocumentTypes` (both `CFBundleTypeExtensions` and the extensions behind each
    /// `LSItemContentTypes` UTI). Registry editors that declare nothing concrete fall back to
    /// their curated developer patterns, so a "handles everything" editor still shows a useful
    /// starter list the user can trim.
    private func readFileFormats(from appURL: URL, definition: AppDefinition?) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func add(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let ext = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
            guard ext.count >= 1, ext.count <= 5, ext != "*",
                  ext.allSatisfy({ $0.isLetter || $0.isNumber }),
                  !Self.formatStopwords.contains(ext)
            else { return }
            if seen.insert(ext).inserted { ordered.append(ext) }
        }

        if let bundle = Bundle(url: appURL),
           let docTypes = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]]
        {
            for docType in docTypes {
                (docType["CFBundleTypeExtensions"] as? [String])?.forEach(add)
                for uti in docType["LSItemContentTypes"] as? [String] ?? [] {
                    guard let type = UTType(uti) else { continue }
                    type.preferredFilenameExtension.map(add)
                    (type.tags[.filenameExtension] ?? []).forEach(add)
                }
            }
        }

        // Enrich/seed from the curated registry patterns (drops the non-extension tokens like
        // "dockerfile" or ".env" variants via the same cleanliness filter in `add`).
        if let definition, ordered.count < 6 {
            definition.filePatterns.forEach(add)
        }

        return ordered
    }

    /// Tokens that pass the extension shape test but are really filenames/words, not formats.
    private static let formatStopwords: Set<String> = [
        "local", "test", "path", "mount", "conf", "fish", "make", "task", "lock", "sample",
    ]

    /// Read CFBundleURLTypes -> CFBundleURLSchemes from an app bundle
    private func readURLSchemes(from appURL: URL) -> [String] {
        guard let bundle = Bundle(url: appURL),
              let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        else { return [] }

        var schemes: [String] = []
        for urlType in urlTypes {
            if let typeSchemes = urlType["CFBundleURLSchemes"] as? [String] {
                schemes.append(contentsOf: typeSchemes)
            }
        }
        return schemes.filter { scheme in
            let s = scheme.lowercased()
            return !["http", "https", "file", "mailto", "tel", "sms", "ftp", "ssh"].contains(s)
        }
    }
}
