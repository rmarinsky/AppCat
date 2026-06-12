import AppKit
import os

@MainActor
final class AppDetector {

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
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 64, height: 64)
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
                icon: icon,
                version: version
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
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 64, height: 64)
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
                    icon: icon,
                    version: version
                ))
            }
        }

        Log.apps.info("Detected \(apps.count) installed apps")
        return apps
    }

    // MARK: - Private

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
