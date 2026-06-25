import AppKit
import os

@MainActor
final class BrowserDetector {
    func detectBrowsers() -> [InstalledBrowser] {
        guard let httpURL = URL(string: "https://example.com") else { return [] }

        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: httpURL)

        var browsers: [InstalledBrowser] = []
        var seenBundleIDs: Set<String> = []
        var index = 0

        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL),
                  let bundleID = bundle.bundleIdentifier,
                  !bundleID.hasPrefix("ua.com.rmarinsky.appcat"),
                  seenBundleIDs.insert(bundleID).inserted
            else {
                continue
            }

            let definition = BrowserDefinition.registry[bundleID]
            let displayName = definition?.displayName
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? appURL.deletingPathExtension().lastPathComponent

            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 64, height: 64)

            let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String

            let browser = InstalledBrowser(
                id: bundleID,
                displayName: displayName,
                appURL: appURL,
                isVisible: true,
                hotkey: nil,
                sortOrder: index,
                supportsPrivateMode: definition?.supportsPrivateMode ?? false,
                privateModeArgs: definition?.privateModeArgs,
                profileDataPath: definition?.profileDataPath,
                profileType: definition?.profileType,
                icon: icon,
                version: version
            )
            browsers.append(browser)
            index += 1

            Log.browser.debug("Detected browser: \(displayName) (\(bundleID))")
        }

        Log.browser.info("Detected \(browsers.count) browsers")
        return browsers
    }
}
