import AppKit
import Foundation
import UniformTypeIdentifiers

struct InstalledApp: Identifiable, Equatable {
    let id: String // bundleID
    var displayName: String
    var appURL: URL
    /// Custom URL schemes this app handles (e.g., ["slack", "slack-beta"])
    var urlSchemes: [String]
    /// Web host patterns this app can open (from AppDefinition registry)
    var hostPatterns: [String]
    var isVisible: Bool
    var sortOrder: Int
    var hotkey: Character?
    var hotkeyKeyCode: UInt16?

    /// Apple / system app (bundle under `/System/` or a `com.apple.*` id). These sort to the
    /// bottom of the Apps screen, under their own "Apple & System" section.
    var isSystemApp: Bool = false
    /// User-edited list of file extensions this app should open. `nil` means "use whatever the
    /// app declares" (`detectedFormats`); a non-nil value overrides it (add/remove in the editor).
    var customFormats: [String]?
    /// When on, AppCat routes files whose type macOS can't match to this app.
    var opensUnknownTypes: Bool = false

    // Non-codable, loaded at runtime
    var icon: NSImage?
    var version: String?
    /// File extensions read from the app's Info.plist (`CFBundleDocumentTypes`) at detection
    /// time. The source of truth that `customFormats` overrides; not persisted.
    var detectedFormats: [String] = []

    /// Effective list of file extensions this app opens — the user's override when set,
    /// otherwise the formats declared by the app itself.
    var fileFormats: [String] {
        customFormats ?? detectedFormats
    }

    /// True when the app advertises *some* file support — concrete formats, or a registry
    /// "handles all files" editor. Apps that declare nothing useful sink to the bottom of the
    /// Apps screen; there's no point ranking a file-less app above ones you actually open files in.
    var declaresFileSupport: Bool {
        !fileFormats.isEmpty || AppDefinition.registryByID[id]?.handlesAllFiles == true
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.appURL == rhs.appURL
            && lhs.urlSchemes == rhs.urlSchemes
            && lhs.hostPatterns == rhs.hostPatterns
            && lhs.isVisible == rhs.isVisible
            && lhs.sortOrder == rhs.sortOrder
            && lhs.hotkey == rhs.hotkey
            && lhs.hotkeyKeyCode == rhs.hotkeyKeyCode
            && lhs.isSystemApp == rhs.isSystemApp
            && lhs.customFormats == rhs.customFormats
            && lhs.opensUnknownTypes == rhs.opensUnknownTypes
            && lhs.detectedFormats == rhs.detectedFormats
    }

    /// Check if this app handles the given URL based on host patterns
    func matchesHost(of url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hostPatterns.contains { pattern in
            let p = pattern.lowercased()
            return host == p || host.hasSuffix(".\(p)")
        }
    }

    func matchesFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }

        if matchesConfiguredFileFormat(url) {
            return true
        }

        // A non-nil override is explicit: the user trimmed/extended the app's file list in
        // settings, so don't re-add broad registry defaults behind their back.
        if customFormats != nil {
            return false
        }

        return AppDefinition.registryByID[id]?.matchesFile(url) == true
    }

    static func matchingFileApps(
        for url: URL,
        in apps: [InstalledApp],
        excludingBundleIDs excludedBundleIDs: Set<String> = [],
        includingLaunchServicesCandidates: Bool = false
    ) -> [InstalledApp] {
        guard url.isFileURL else { return [] }

        // Apps the system itself says can open this file (LaunchServices), so any installed
        // app — not just the curated registry — becomes a target for files others can't open.
        let currentBundleID = Bundle.main.bundleIdentifier
        let excludedIDs = excludedBundleIDs.union([currentBundleID].compactMap { $0 })
        let capableAppURLs: [URL] = includingLaunchServicesCandidates
            ? NSWorkspace.shared.urlsForApplications(toOpen: url)
            : []
        let capableIDs = Set(
            capableAppURLs
                .compactMap { Bundle(url: $0)?.bundleIdentifier }
                .filter { !excludedIDs.contains($0) }
        )
        let isUnknownType = isUnknownFileType(url, capableIDs: capableIDs)
        let knownIDs = Set(apps.map(\.id))
        let launchServicesApps: [InstalledApp] = capableAppURLs.enumerated().compactMap { index, appURL in
            guard let app = launchServicesApp(from: appURL, sortOrder: apps.count + index),
                  !excludedIDs.contains(app.id),
                  !knownIDs.contains(app.id)
            else { return nil }
            return app
        }

        return (apps + launchServicesApps)
            .compactMap { app -> (app: InstalledApp, rank: Int)? in
                let isLaunchServicesCandidate = capableIDs.contains(app.id)
                guard app.isVisible || isLaunchServicesCandidate else { return nil }
                if let rank = fileMatchRank(for: app, url: url, capableIDs: capableIDs, isUnknownType: isUnknownType) {
                    return (app, rank)
                }
                return nil
            }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank {
                    return lhs.rank < rhs.rank
                }

                let lhsPriority = AppDefinition.registryByID[lhs.app.id]?.filePickerPriority ?? Int.max
                let rhsPriority = AppDefinition.registryByID[rhs.app.id]?.filePickerPriority ?? Int.max
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                if lhs.app.sortOrder != rhs.app.sortOrder {
                    return lhs.app.sortOrder < rhs.app.sortOrder
                }
                return lhs.app.displayName.localizedCaseInsensitiveCompare(rhs.app.displayName) == .orderedAscending
            }
            .map(\.app)
    }

    static func normalizedFileFormat(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = trimmed.hasPrefix(".") ? String(trimmed.dropFirst()) : trimmed
        guard !value.isEmpty, value != "*" else { return nil }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_+"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return value
    }

    private func matchesConfiguredFileFormat(_ url: URL) -> Bool {
        let formats = fileFormats.compactMap(Self.normalizedFileFormat)
        guard !formats.isEmpty else { return false }

        let tokens = BrowserFileType.fileMatchTokens(for: url)
        let contentType = Self.contentType(for: url)

        return formats.contains { format in
            if tokens.contains(format) {
                return true
            }
            guard let contentType else { return false }
            if contentType.identifier == format {
                return true
            }
            return UTType(format).map { contentType.conforms(to: $0) } ?? false
        }
    }

    private static func fileMatchRank(
        for app: InstalledApp,
        url: URL,
        capableIDs: Set<String>,
        isUnknownType: Bool
    ) -> Int? {
        if app.matchesFile(url) {
            return app.customFormats == nil ? 1 : 0
        }

        // LaunchServices is still the compatibility net: this preserves the old behavior where
        // the picker lists whatever macOS says can open this concrete file.
        if app.customFormats == nil, capableIDs.contains(app.id) {
            return 2
        }

        if isUnknownType, app.opensUnknownTypes {
            return 3
        }

        return nil
    }

    private static func isUnknownFileType(_ url: URL, capableIDs: Set<String>) -> Bool {
        if capableIDs.isEmpty {
            return true
        }

        guard let type = contentType(for: url) else {
            return true
        }

        return type.identifier.hasPrefix("dyn.")
            || type.identifier == UTType.data.identifier
    }

    private static func contentType(for url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        let ext = url.pathExtension
        guard !ext.isEmpty else { return nil }
        return UTType(filenameExtension: ext)
    }

    private static func launchServicesApp(from appURL: URL, sortOrder: Int) -> InstalledApp? {
        guard let bundle = Bundle(url: appURL), let bundleID = bundle.bundleIdentifier else { return nil }

        let finderName = FileManager.default.displayName(atPath: appURL.path)
        let fallbackName = finderName.hasSuffix(".app")
            ? String(finderName.dropLast(4))
            : appURL.deletingPathExtension().lastPathComponent
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? fallbackName

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 64, height: 64)
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String

        return InstalledApp(
            id: bundleID,
            displayName: displayName,
            appURL: appURL,
            urlSchemes: [],
            hostPatterns: [],
            isVisible: true,
            sortOrder: sortOrder,
            isSystemApp: bundleID.hasPrefix("com.apple.") || appURL.path.hasPrefix("/System/"),
            icon: icon,
            version: version,
            detectedFormats: []
        )
    }
}

// MARK: - Codable support (without icon)

struct AppConfig: Codable {
    let id: String
    var displayName: String
    var isVisible: Bool
    var hotkey: String?
    var hotkeyKeyCode: UInt16?
    var sortOrder: Int
    /// User override of the app's file formats. Optional so older `apps.json` (written before
    /// the format editor existed) still decodes — a missing key reads back as `nil`.
    var customFormats: [String]?
    var opensUnknownTypes: Bool?

    init(from app: InstalledApp) {
        id = app.id
        displayName = app.displayName
        isVisible = app.isVisible
        hotkey = app.hotkey.map { String($0) }
        hotkeyKeyCode = app.hotkeyKeyCode
        sortOrder = app.sortOrder
        customFormats = app.customFormats
        opensUnknownTypes = app.opensUnknownTypes
    }
}
