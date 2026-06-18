import Foundation

enum SuggestionScope: Hashable, Codable {
    case registrableDomain(String)
    case fullHost(String)
    case hostPath(host: String, pathPrefix: String)

    var displayHost: String {
        switch self {
        case let .registrableDomain(d): return d
        case let .fullHost(h): return h
        case let .hostPath(host: h, pathPrefix: _): return h
        }
    }

    var pathSuffix: String? {
        if case let .hostPath(host: _, pathPrefix: p) = self { return p }
        return nil
    }

    var specificity: Int {
        switch self {
        case .registrableDomain: return 0
        case .fullHost: return 1
        case let .hostPath(host: _, pathPrefix: p):
            return 2 + p.split(separator: "/").count
        }
    }
}

struct RuleSuggestion: Identifiable, Equatable, Codable {
    let id: UUID
    let scope: SuggestionScope
    let matchType: URLRule.MatchType
    let pattern: String
    let browserID: String
    let profileDirectoryName: String?
    let targetType: URLRule.TargetType
    let score: Double
    let occurrenceCount: Int
    let lastSeen: Date

    var dismissalKey: String {
        let scopeKey: String
        switch scope {
        case let .registrableDomain(d): scopeKey = "rd:\(d)"
        case let .fullHost(h): scopeKey = "fh:\(h)"
        case let .hostPath(host: h, pathPrefix: p): scopeKey = "hp:\(h)/\(p)"
        }
        return "\(scopeKey)|\(targetType.rawValue)|\(browserID)|\(profileDirectoryName ?? "*")"
    }

    init(
        id: UUID = UUID(),
        scope: SuggestionScope,
        matchType: URLRule.MatchType,
        pattern: String,
        browserID: String,
        profileDirectoryName: String?,
        targetType: URLRule.TargetType,
        score: Double,
        occurrenceCount: Int,
        lastSeen: Date
    ) {
        self.id = id
        self.scope = scope
        self.matchType = matchType
        self.pattern = pattern
        self.browserID = browserID
        self.profileDirectoryName = profileDirectoryName
        self.targetType = targetType
        self.score = score
        self.occurrenceCount = occurrenceCount
        self.lastSeen = lastSeen
    }
}
