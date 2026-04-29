import Foundation

enum SuggestionEngine {
    struct Config {
        var halfLifeDays: Double = 7.0
        var scoreThreshold: Double = 3.0
        var dominanceThreshold: Double = 0.7
        /// Minimum distinct calendar days OR minimum same-day occurrences — whichever fires first.
        /// Either condition unlocks suggestions, so heavy single-day usage isn't suppressed.
        var minDistinctDays: Int = 2
        var minSameDayOccurrences: Int = 5
        var maxPathSegments: Int = 2

        static let `default` = Config()
    }

    static func suggest(
        history: [HistoryEntry],
        rules: [URLRule],
        matcher: URLRuleMatcher,
        dismissedKeys: Set<String>,
        now: Date,
        config: Config = .default
    ) -> [RuleSuggestion] {
        struct Usable {
            let openedAt: Date
            let url: URL
            let browserID: String
            let profileDir: String?
        }

        let usable: [Usable] = history.compactMap { entry in
            guard entry.targetType == .browser,
                  let browserID = entry.browserID,
                  let url = URL(string: entry.url),
                  url.host != nil else { return nil }
            return Usable(
                openedAt: entry.openedAt,
                url: url,
                browserID: browserID,
                profileDir: entry.profileDirectoryName
            )
        }

        struct GroupKey: Hashable {
            let scope: SuggestionScope
            let browserID: String
            let profileDir: String?
        }
        struct GroupStats {
            var score: Double = 0
            var occurrenceCount: Int = 0
            var distinctDays: Set<Date> = []
            var lastSeen: Date = .distantPast
        }

        var groups: [GroupKey: GroupStats] = [:]
        let calendar = Calendar(identifier: .gregorian)
        let halfLifeDecay = log(2.0) / config.halfLifeDays

        for u in usable {
            let ageDays = max(0, now.timeIntervalSince(u.openedAt) / 86_400.0)
            let weight = exp(-halfLifeDecay * ageDays)
            let dayStart = calendar.startOfDay(for: u.openedAt)
            for scope in scopes(for: u.url, maxPathSegments: config.maxPathSegments) {
                let key = GroupKey(scope: scope, browserID: u.browserID, profileDir: u.profileDir)
                var stats = groups[key, default: GroupStats()]
                stats.score += weight
                stats.occurrenceCount += 1
                stats.distinctDays.insert(dayStart)
                if u.openedAt > stats.lastSeen { stats.lastSeen = u.openedAt }
                groups[key] = stats
            }
        }

        var scopeTotals: [SuggestionScope: Double] = [:]
        for (key, stats) in groups {
            scopeTotals[key.scope, default: 0] += stats.score
        }

        // Pass 1: profile-specific candidates. Track keys that pass gates separately
        // from dismissed-filtered output, so Pass 2 can suppress redundant "Any Profile"
        // suggestions even when the user already dismissed the specific-profile one.
        var candidates: [RuleSuggestion] = []
        var pass1Gated: Set<GroupKey> = []
        for (key, stats) in groups {
            guard let total = scopeTotals[key.scope], total > 0 else { continue }
            if stats.score < config.scoreThreshold { continue }
            if stats.score / total < config.dominanceThreshold { continue }
            if stats.distinctDays.count < config.minDistinctDays
                && stats.occurrenceCount < config.minSameDayOccurrences { continue }
            if let rep = representativeURL(for: key.scope),
               matcher.findMatchingRule(for: rep, rules: rules) != nil { continue }

            pass1Gated.insert(key)

            let s = makeSuggestion(
                scope: key.scope,
                browserID: key.browserID,
                profileDir: key.profileDir,
                score: stats.score,
                occurrenceCount: stats.occurrenceCount,
                lastSeen: stats.lastSeen
            )
            if dismissedKeys.contains(s.dismissalKey) { continue }
            candidates.append(s)
        }

        // Pass 2: "Any Profile" fallback. Skip a (scope, browserID) when a profile-
        // specific candidate already covers it on this scope OR a more-specific one.
        var combined: [GroupKey: GroupStats] = [:]
        for (key, stats) in groups {
            if pass1Gated.contains(where: { gk in
                gk.browserID == key.browserID &&
                    gk.profileDir != nil &&
                    scopeContains(parent: key.scope, child: gk.scope)
            }) {
                continue
            }
            let combinedKey = GroupKey(scope: key.scope, browserID: key.browserID, profileDir: nil)
            var c = combined[combinedKey, default: GroupStats()]
            c.score += stats.score
            c.occurrenceCount += stats.occurrenceCount
            c.distinctDays.formUnion(stats.distinctDays)
            if stats.lastSeen > c.lastSeen { c.lastSeen = stats.lastSeen }
            combined[combinedKey] = c
        }
        for (key, stats) in combined {
            guard let total = scopeTotals[key.scope], total > 0 else { continue }
            if stats.score < config.scoreThreshold { continue }
            if stats.score / total < config.dominanceThreshold { continue }
            if stats.distinctDays.count < config.minDistinctDays
                && stats.occurrenceCount < config.minSameDayOccurrences { continue }
            if let rep = representativeURL(for: key.scope),
               matcher.findMatchingRule(for: rep, rules: rules) != nil { continue }

            let s = makeSuggestion(
                scope: key.scope,
                browserID: key.browserID,
                profileDir: nil,
                score: stats.score,
                occurrenceCount: stats.occurrenceCount,
                lastSeen: stats.lastSeen
            )
            if dismissedKeys.contains(s.dismissalKey) { continue }
            candidates.append(s)
        }

        // Specificity dedup: same (browserID, profileDir, targetType) → keep least-specific scope
        let grouped = Dictionary(grouping: candidates) { c in
            "\(c.targetType.rawValue)|\(c.browserID)|\(c.profileDirectoryName ?? "*")"
        }
        var deduped: [RuleSuggestion] = []
        for (_, group) in grouped {
            if let least = group.min(by: { $0.scope.specificity < $1.scope.specificity }) {
                deduped.append(least)
            }
        }

        return deduped.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.scope.specificity > rhs.scope.specificity
            }
            return lhs.score > rhs.score
        }
    }

    // MARK: - Scope generation

    static func scopes(for url: URL, maxPathSegments: Int) -> [SuggestionScope] {
        guard let host = url.host?.lowercased() else { return [] }

        var result: [SuggestionScope] = []

        let pathSegments = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .prefix(maxPathSegments)
            .map(String.init)

        if !pathSegments.isEmpty {
            for i in stride(from: pathSegments.count, through: 1, by: -1) {
                let prefix = pathSegments.prefix(i).joined(separator: "/")
                result.append(.hostPath(host: host, pathPrefix: prefix))
            }
        }

        result.append(.fullHost(host))

        if let registrable = registrableDomain(of: host), registrable != host {
            result.append(.registrableDomain(registrable))
        }

        return result
    }

    // MARK: - Registrable domain (eTLD+1)

    private static let twoLabelPublicSuffixes: Set<String> = [
        "co.uk", "ac.uk", "gov.uk", "org.uk", "ltd.uk", "me.uk", "net.uk",
        "com.ua", "kiev.ua", "in.ua", "co.ua",
        "co.jp", "ne.jp", "or.jp", "ac.jp",
        "co.kr", "or.kr", "ne.kr",
        "com.au", "net.au", "org.au", "edu.au", "gov.au",
        "co.in", "net.in", "org.in",
        "co.nz", "net.nz", "org.nz",
        "com.br", "net.br", "org.br",
        "com.mx", "com.ar", "com.tr", "com.sg",
        "co.za", "co.il",
    ]

    static func registrableDomain(of host: String) -> String? {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        if parts.count >= 3 {
            let lastTwo = "\(parts[parts.count - 2]).\(parts[parts.count - 1])"
            if twoLabelPublicSuffixes.contains(lastTwo) {
                return "\(parts[parts.count - 3]).\(lastTwo)"
            }
        }
        return "\(parts[parts.count - 2]).\(parts[parts.count - 1])"
    }

    // MARK: - Pattern + representative URL

    static func patternForRule(scope: SuggestionScope) -> (matchType: URLRule.MatchType, pattern: String) {
        switch scope {
        case let .registrableDomain(d): return (.host, d)
        case let .fullHost(h): return (.host, h)
        case .hostPath: return (.regex, regexPattern(for: scope))
        }
    }

    static func regexPattern(for scope: SuggestionScope) -> String {
        switch scope {
        case let .hostPath(host: h, pathPrefix: p):
            let escapedHost = NSRegularExpression.escapedPattern(for: h)
            let escapedPath = NSRegularExpression.escapedPattern(for: p)
            return "^https?://\(escapedHost)/\(escapedPath)(/|$|\\?)"
        case let .fullHost(h):
            let escapedHost = NSRegularExpression.escapedPattern(for: h)
            return "^https?://\(escapedHost)(/|$|\\?)"
        case let .registrableDomain(d):
            let escapedDomain = NSRegularExpression.escapedPattern(for: d)
            return "^https?://([^/]*\\.)?\(escapedDomain)(/|$|\\?)"
        }
    }

    static func scopeContains(parent: SuggestionScope, child: SuggestionScope) -> Bool {
        switch (parent, child) {
        case let (.registrableDomain(d), .registrableDomain(d2)):
            return d == d2
        case let (.registrableDomain(d), .fullHost(h)),
             let (.registrableDomain(d), .hostPath(h, _)):
            return h == d || h.hasSuffix(".\(d)")
        case let (.fullHost(h), .fullHost(h2)):
            return h == h2
        case let (.fullHost(h), .hostPath(h2, _)):
            return h == h2
        case let (.hostPath(h, p), .hostPath(h2, p2)):
            return h == h2 && (p2 == p || p2.hasPrefix("\(p)/"))
        default:
            return false
        }
    }

    static func representativeURL(for scope: SuggestionScope) -> URL? {
        switch scope {
        case let .registrableDomain(d): return URL(string: "https://\(d)/")
        case let .fullHost(h): return URL(string: "https://\(h)/")
        case let .hostPath(host: h, pathPrefix: p): return URL(string: "https://\(h)/\(p)/")
        }
    }

    // MARK: -

    private static func makeSuggestion(
        scope: SuggestionScope,
        browserID: String,
        profileDir: String?,
        score: Double,
        occurrenceCount: Int,
        lastSeen: Date
    ) -> RuleSuggestion {
        let p = patternForRule(scope: scope)
        return RuleSuggestion(
            scope: scope,
            matchType: p.matchType,
            pattern: p.pattern,
            browserID: browserID,
            profileDirectoryName: profileDir,
            targetType: .browser,
            score: score,
            occurrenceCount: occurrenceCount,
            lastSeen: lastSeen
        )
    }
}
