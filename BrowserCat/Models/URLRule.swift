import Foundation

struct URLRule: Identifiable, Codable, Equatable {
    let id: UUID
    var pattern: String
    var matchType: MatchType
    var browserID: String
    var profileDirectoryName: String?
    var targetType: TargetType
    var isEnabled: Bool
    var sortOrder: Int

    enum MatchType: String, Codable, CaseIterable {
        case host
        case hostContains
        case urlContains
        case regex

        var displayName: String {
            switch self {
            case .host: String(localized: "Exact site")
            case .hostContains: String(localized: "Part of site address")
            case .urlContains: String(localized: "Part of link")
            case .regex: String(localized: "Advanced pattern")
            }
        }

        var helpText: String {
            switch self {
            case .host: String(localized: "Matches the exact site address (e.g. github.com or any subdomain).")
            case .hostContains: String(localized: "Matches when the site address contains the text.")
            case .urlContains: String(localized: "Matches when any part of the link — including the path after / — contains the text.")
            case .regex: String(localized: "Regular expression for advanced users.")
            }
        }
    }

    enum TargetType: String, Codable, CaseIterable {
        case browser
        case app

        var displayName: String {
            switch self {
            case .browser: String(localized: "Browser")
            case .app: String(localized: "App")
            }
        }
    }

    init(
        id: UUID = UUID(),
        pattern: String = "",
        matchType: MatchType = .host,
        browserID: String = "",
        profileDirectoryName: String? = nil,
        targetType: TargetType = .browser,
        isEnabled: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.pattern = pattern
        self.matchType = matchType
        self.browserID = browserID
        self.profileDirectoryName = profileDirectoryName
        self.targetType = targetType
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
    }

    // Backward-compatible decoding: default targetType to .browser if missing
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        pattern = try container.decode(String.self, forKey: .pattern)
        matchType = try container.decode(MatchType.self, forKey: .matchType)
        browserID = try container.decode(String.self, forKey: .browserID)
        profileDirectoryName = try container.decodeIfPresent(String.self, forKey: .profileDirectoryName)
        targetType = try container.decodeIfPresent(TargetType.self, forKey: .targetType) ?? .browser
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
    }
}
