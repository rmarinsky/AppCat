import Foundation

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let url: String
    let domain: String
    let title: String?
    let appName: String
    let profileName: String?
    let openedAt: Date

    let browserID: String?
    let profileDirectoryName: String?
    let targetType: URLRule.TargetType?

    init(
        id: UUID = UUID(),
        url: String,
        domain: String,
        title: String?,
        appName: String,
        profileName: String?,
        openedAt: Date = Date(),
        browserID: String? = nil,
        profileDirectoryName: String? = nil,
        targetType: URLRule.TargetType? = nil
    ) {
        self.id = id
        self.url = url
        self.domain = domain
        self.title = title
        self.appName = appName
        self.profileName = profileName
        self.openedAt = openedAt
        self.browserID = browserID
        self.profileDirectoryName = profileDirectoryName
        self.targetType = targetType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        domain = try container.decode(String.self, forKey: .domain)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        appName = try container.decode(String.self, forKey: .appName)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName)
        openedAt = try container.decode(Date.self, forKey: .openedAt)
        browserID = try container.decodeIfPresent(String.self, forKey: .browserID)
        profileDirectoryName = try container.decodeIfPresent(String.self, forKey: .profileDirectoryName)
        targetType = try container.decodeIfPresent(URLRule.TargetType.self, forKey: .targetType)
    }
}
