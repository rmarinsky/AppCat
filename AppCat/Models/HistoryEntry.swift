import Foundation

struct HistoryEntry: Identifiable, Codable, Equatable {
    enum ItemKind: String, Codable {
        case link
        case file
    }

    let id: UUID
    var url: String
    var domain: String
    let title: String?
    let appName: String
    let profileName: String?
    let openedAt: Date

    let browserID: String?
    let profileDirectoryName: String?
    let targetType: URLRule.TargetType?
    let itemKind: ItemKind
    let fileName: String?
    let fileExtension: String?
    let fileFormat: String?
    let contentTypeIdentifier: String?

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
        targetType: URLRule.TargetType? = nil,
        itemKind: ItemKind = .link,
        fileName: String? = nil,
        fileExtension: String? = nil,
        fileFormat: String? = nil,
        contentTypeIdentifier: String? = nil
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
        self.itemKind = itemKind
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileFormat = fileFormat
        self.contentTypeIdentifier = contentTypeIdentifier
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
        itemKind = try container.decodeIfPresent(ItemKind.self, forKey: .itemKind)
            ?? (url.hasPrefix("file://") ? .file : .link)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension)
        fileFormat = try container.decodeIfPresent(String.self, forKey: .fileFormat)
        contentTypeIdentifier = try container.decodeIfPresent(String.self, forKey: .contentTypeIdentifier)
    }
}
