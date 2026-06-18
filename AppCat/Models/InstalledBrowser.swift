import AppKit
import Foundation

struct InstalledBrowser: Identifiable, Equatable {
    let id: String // bundleID
    var displayName: String
    var appURL: URL
    var isVisible: Bool
    var isIgnored: Bool = false
    var hotkey: Character?
    var hotkeyKeyCode: UInt16?
    var sortOrder: Int
    var supportsPrivateMode: Bool
    var privateModeArgs: [String]?
    var profileDataPath: String?
    var profileType: ProfileType?
    var profiles: [BrowserProfile] = []

    // Non-codable, loaded at runtime
    var icon: NSImage?
    var version: String?

    var hasProfiles: Bool {
        !profiles.isEmpty
    }

    static func == (lhs: InstalledBrowser, rhs: InstalledBrowser) -> Bool {
        lhs.id == rhs.id
            && lhs.displayName == rhs.displayName
            && lhs.appURL == rhs.appURL
            && lhs.isVisible == rhs.isVisible
            && lhs.isIgnored == rhs.isIgnored
            && lhs.hotkey == rhs.hotkey
            && lhs.hotkeyKeyCode == rhs.hotkeyKeyCode
            && lhs.sortOrder == rhs.sortOrder
            && lhs.supportsPrivateMode == rhs.supportsPrivateMode
            && lhs.profiles == rhs.profiles
    }
}

// MARK: - Codable support (without icon)

struct BrowserConfig: Codable {
    let id: String
    var displayName: String
    var isVisible: Bool
    var isIgnored: Bool
    var hotkey: String? // Store Character as String
    var hotkeyKeyCode: UInt16?
    var sortOrder: Int
    var profileHotkeys: [String: String]? // directoryName -> hotkey character
    var profileHotkeyKeyCodes: [String: UInt16]? // directoryName -> keyCode
    var profileVisibility: [String: Bool]? // directoryName -> isVisible

    init(from browser: InstalledBrowser) {
        id = browser.id
        displayName = browser.displayName
        isVisible = browser.isVisible
        isIgnored = browser.isIgnored
        hotkey = browser.hotkey.map { String($0) }
        hotkeyKeyCode = browser.hotkeyKeyCode
        sortOrder = browser.sortOrder

        let keys = browser.profiles.compactMap { profile -> (String, String)? in
            guard let key = profile.hotkey else { return nil }
            return (profile.directoryName, String(key))
        }
        profileHotkeys = keys.isEmpty ? nil : Dictionary(keys, uniquingKeysWith: { first, _ in first })

        let keyCodes = browser.profiles.compactMap { profile -> (String, UInt16)? in
            guard let code = profile.hotkeyKeyCode else { return nil }
            return (profile.directoryName, code)
        }
        profileHotkeyKeyCodes = keyCodes.isEmpty ? nil : Dictionary(keyCodes, uniquingKeysWith: { first, _ in first })

        let visibility = browser.profiles.map { ($0.directoryName, $0.isVisible) }
        profileVisibility = visibility.isEmpty ? nil : Dictionary(visibility, uniquingKeysWith: { first, _ in first })
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        isIgnored = try container.decodeIfPresent(Bool.self, forKey: .isIgnored) ?? false
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey)
        hotkeyKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .hotkeyKeyCode)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        profileHotkeys = try container.decodeIfPresent([String: String].self, forKey: .profileHotkeys)
        profileHotkeyKeyCodes = try container.decodeIfPresent([String: UInt16].self, forKey: .profileHotkeyKeyCodes)
        profileVisibility = try container.decodeIfPresent([String: Bool].self, forKey: .profileVisibility)
    }
}
