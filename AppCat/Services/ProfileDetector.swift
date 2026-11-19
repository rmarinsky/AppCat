import Foundation
import os

/// Why a browser's profile list could not be read. Any failure keeps the last known profiles.
enum ProfileReadFailure: Equatable {
    /// macOS privacy protection (EPERM). Since macOS 27 another app's data is protected until the
    /// user allows it in Privacy & Security; the system never prompts.
    case privacyBlocked
    /// The file's own permissions (EACCES), which Privacy & Security cannot change.
    case filePermissions
    /// The file exists but could not be parsed, e.g. while the browser rewrites it.
    case unreadable
}

struct ProfileDetection: Equatable {
    var profiles: [BrowserProfile] = []
    var failure: ProfileReadFailure?
}

@MainActor
final class ProfileDetector {
    private let fileManager: FileManager
    private let applicationSupportDirectory: URL

    init(fileManager: FileManager = .default, applicationSupportDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? Self.defaultApplicationSupportDirectory(fileManager: fileManager)
    }

    func detectProfiles(for browser: InstalledBrowser) -> ProfileDetection {
        guard let profileType = browser.profileType,
              let profileDataPath = browser.profileDataPath
        else {
            return ProfileDetection()
        }

        let detection: ProfileDetection
        switch profileType {
        case .chromium:
            detection = detectChromiumProfiles(dataPath: profileDataPath)
        case .firefox:
            detection = detectFirefoxProfiles(dataPath: profileDataPath)
        }

        if let failure = detection.failure {
            Log.profiles.error("Could not read the profiles of \(browser.displayName): \(String(describing: failure))")
        } else if !detection.profiles.isEmpty {
            Log.profiles.info("Detected \(detection.profiles.count) profiles for \(browser.displayName)")
        }
        return detection
    }

    /// EPERM is a mandatory-access (privacy) denial and EACCES a file-permission one; Foundation
    /// wraps both in the same Cocoa error, so the POSIX code underneath decides.
    nonisolated static func readFailure(for error: Error) -> ProfileReadFailure? {
        var error = error as NSError
        if error.domain == NSCocoaErrorDomain, let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            error = underlying
        }
        guard error.domain == NSPOSIXErrorDomain else { return nil }
        switch Int32(error.code) {
        case EPERM: return .privacyBlocked
        case EACCES: return .filePermissions
        default: return nil
        }
    }

    private static func defaultApplicationSupportDirectory(fileManager: FileManager) -> URL {
        let homeAppSupport = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        if fileManager.fileExists(atPath: homeAppSupport.path) {
            return homeAppSupport
        }

        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    // MARK: - Chromium

    private func detectChromiumProfiles(dataPath: String) -> ProfileDetection {
        let browserDataDirectory = applicationSupportDirectory
            .appendingPathComponent(dataPath, isDirectory: true)
        let localStatePath = browserDataDirectory
            .appendingPathComponent("Local State")

        let data: Data
        do {
            data = try Data(contentsOf: localStatePath)
        } catch {
            Log.profiles.debug("No Chromium Local State found at \(localStatePath.path)")
            return ProfileDetection(failure: Self.readFailure(for: error))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any]
        else {
            Log.profiles.debug("Unreadable Chromium Local State at \(localStatePath.path)")
            return ProfileDetection(failure: .unreadable)
        }

        var profiles: [BrowserProfile] = []
        for (dirName, value) in infoCache {
            guard let info = value as? [String: Any] else { continue }
            if info["is_omitted_from_profile_list"] as? Bool == true { continue }

            let name = cleanString(info["name"] as? String) ?? dirName
            let email = cleanString(info["user_name"] as? String)
            let displayEmail = (email?.isEmpty == true) ? nil : email
            profiles.append(BrowserProfile(
                directoryName: dirName,
                displayName: name,
                email: displayEmail,
                avatarPath: chromiumAvatarPath(
                    browserDataDirectory: browserDataDirectory,
                    directoryName: dirName,
                    info: info
                )
            ))
        }

        return ProfileDetection(profiles: profiles.sorted(by: sortProfiles))
    }

    private func chromiumAvatarPath(
        browserDataDirectory: URL,
        directoryName: String,
        info: [String: Any]
    ) -> String? {
        let profileDirectory = browserDataDirectory.appendingPathComponent(directoryName, isDirectory: true)
        var candidates: [URL] = []

        if let fileName = cleanString(info["gaia_picture_file_name"] as? String) {
            let url = URL(fileURLWithPath: fileName, relativeTo: profileDirectory)
            candidates.append(url.standardizedFileURL)
        }

        candidates.append(profileDirectory.appendingPathComponent("Google Profile Picture.png"))

        if let accountAvatars = try? fileManager.contentsOfDirectory(
            at: profileDirectory.appendingPathComponent("Accounts/Avatar Images", isDirectory: true),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: accountAvatars.sorted { lhs, rhs in
                lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            })
        }

        return candidates.first { url in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                return false
            }
            let ext = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "heic", "tiff"].contains(ext)
        }?.path
    }

    // MARK: - Firefox

    private func detectFirefoxProfiles(dataPath: String) -> ProfileDetection {
        let profilesIniPath = applicationSupportDirectory
            .appendingPathComponent(dataPath)
            .appendingPathComponent("profiles.ini")

        let content: String
        do {
            content = try String(contentsOf: profilesIniPath, encoding: .utf8)
        } catch {
            Log.profiles.debug("No Firefox profiles.ini found at \(profilesIniPath.path)")
            return ProfileDetection(failure: Self.readFailure(for: error))
        }

        var profiles: [BrowserProfile] = []
        var currentSection: String?
        var currentValues: [String: String] = [:]

        func flushCurrentProfile() {
            guard currentSection?.hasPrefix("Profile") == true,
                  let name = cleanString(currentValues["Name"]),
                  let path = cleanString(currentValues["Path"])
            else {
                return
            }

            let dirName = URL(fileURLWithPath: path).lastPathComponent
            profiles.append(BrowserProfile(
                directoryName: dirName,
                displayName: name,
                email: nil
            ))
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                flushCurrentProfile()
                currentSection = String(trimmed.dropFirst().dropLast())
                currentValues = [:]
                continue
            }

            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<separator])
            let value = String(trimmed[trimmed.index(after: separator)...])
            currentValues[key] = value
        }

        flushCurrentProfile()

        return ProfileDetection(profiles: profiles.sorted(by: sortProfiles))
    }

    private func cleanString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func sortProfiles(_ lhs: BrowserProfile, _ rhs: BrowserProfile) -> Bool {
        switch (profileSortRank(lhs.directoryName), profileSortRank(rhs.directoryName)) {
        case let (left, right) where left != right:
            return left < right
        default:
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func profileSortRank(_ directoryName: String) -> Int {
        if directoryName == "Default" {
            return 0
        }

        if directoryName.hasPrefix("Profile ") {
            let suffix = directoryName.dropFirst("Profile ".count)
            if let number = Int(suffix) {
                return number
            }
        }

        return Int.max
    }
}
