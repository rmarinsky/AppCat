import Foundation

struct BrowserProfile: Identifiable, Codable, Equatable, Hashable {
    let directoryName: String // "Default", "Profile 1" (Chromium) or profile name (Firefox)
    let displayName: String // "Roma", "travisperkins.co.uk"
    let email: String? // "newromka@gmail.com" or nil
    let avatarPath: String?
    var hotkey: Character?
    var hotkeyKeyCode: UInt16?
    var isVisible: Bool = true

    var id: String {
        directoryName
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case directoryName, displayName, email, avatarPath, hotkey, hotkeyKeyCode, isVisible
    }

    init(directoryName: String, displayName: String, email: String?, avatarPath: String? = nil, hotkey: Character? = nil, hotkeyKeyCode: UInt16? = nil, isVisible: Bool = true) {
        self.directoryName = directoryName
        self.displayName = displayName
        self.email = email
        self.avatarPath = avatarPath
        self.hotkey = hotkey
        self.hotkeyKeyCode = hotkeyKeyCode
        self.isVisible = isVisible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        directoryName = try container.decode(String.self, forKey: .directoryName)
        displayName = try container.decode(String.self, forKey: .displayName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        avatarPath = try container.decodeIfPresent(String.self, forKey: .avatarPath)
        let hotkeyStr = try container.decodeIfPresent(String.self, forKey: .hotkey)
        hotkey = hotkeyStr?.first
        hotkeyKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .hotkeyKeyCode)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(directoryName, forKey: .directoryName)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(avatarPath, forKey: .avatarPath)
        try container.encodeIfPresent(hotkey.map { String($0) }, forKey: .hotkey)
        try container.encodeIfPresent(hotkeyKeyCode, forKey: .hotkeyKeyCode)
        try container.encode(isVisible, forKey: .isVisible)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(directoryName)
    }
}
