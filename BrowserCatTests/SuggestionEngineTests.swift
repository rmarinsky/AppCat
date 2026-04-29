import XCTest
@testable import BrowserCat

final class SuggestionEngineTests: XCTestCase {
    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_800_000_000) // fixed reference time
    private let chromeID = "com.google.Chrome"
    private let firefoxID = "org.mozilla.firefox"

    private func makeEntry(
        url: String,
        browserID: String?,
        profileDir: String?,
        daysAgo: Double,
        targetType: URLRule.TargetType? = .browser
    ) -> HistoryEntry {
        let opened = now.addingTimeInterval(-daysAgo * 86_400)
        let parsed = URL(string: url)
        return HistoryEntry(
            url: url,
            domain: parsed?.host ?? url,
            title: nil,
            appName: browserID ?? "",
            profileName: profileDir,
            openedAt: opened,
            browserID: browserID,
            profileDirectoryName: profileDir,
            targetType: targetType
        )
    }

    // MARK: - Score threshold

    func testEmptyHistoryProducesNoSuggestions() {
        let result = SuggestionEngine.suggest(
            history: [],
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testBelowScoreThresholdProducesNoSuggestion() {
        // 2 opens — below threshold of 3.0 (counting decay, even less)
        let history = [
            makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Default", daysAgo: 0),
            makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Default", daysAgo: 1),
        ]
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testCrossesScoreThreshold() {
        // 5 recent opens, all to same target → strong signal
        let history = (0 ..< 5).map { i in
            makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Default", daysAgo: Double(i))
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertEqual(result.count, 1)
        let s = result[0]
        XCTAssertEqual(s.browserID, chromeID)
        XCTAssertEqual(s.profileDirectoryName, "Default")
        XCTAssertEqual(s.matchType, .host)
        XCTAssertEqual(s.pattern, "example.com")
    }

    // MARK: - Distinct days gate

    func testFewOpensSameDayBlocked() {
        // 4 opens on the same day — fails both gates (< 2 distinct days AND < 5 same-day opens)
        let history = (0 ..< 4).map { _ in
            makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Default", daysAgo: 0.001)
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testHeavySameDayUsageProducesSuggestion() {
        // 6 opens, all on the same day — passes the same-day-occurrences gate (>=5)
        // even though distinct-days is only 1. Heavy single-day usage shouldn't be suppressed.
        let history = (0 ..< 6).map { _ in
            makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Default", daysAgo: 0.001)
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertFalse(result.isEmpty, "Heavy same-day usage (>=5 opens) should still produce a suggestion")
    }

    // MARK: - Dominance gate

    func testMixedTargetsBlocksHostLevelSuggestion() {
        // example.com: 4 opens in Chrome, 4 opens in Firefox → no dominance
        var history: [HistoryEntry] = []
        for i in 0 ..< 4 {
            history.append(makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Default", daysAgo: Double(i)))
            history.append(makeEntry(url: "https://example.com/", browserID: firefoxID, profileDir: nil, daysAgo: Double(i) + 0.5))
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertTrue(result.isEmpty, "Host-level suggestions should not appear when targets are split evenly")
    }

    // MARK: - Existing rule exclusion

    func testExistingRuleSuppressesSuggestion() {
        let history = (0 ..< 5).map { i in
            makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Default", daysAgo: Double(i))
        }
        let existingRule = URLRule(
            pattern: "example.com",
            matchType: .host,
            browserID: firefoxID,
            targetType: .browser
        )
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [existingRule],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Dismissed-keys

    func testDismissedSuggestionExcluded() {
        let history = (0 ..< 5).map { i in
            makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Default", daysAgo: Double(i))
        }
        let dismissalKey = "fh:example.com|browser|\(chromeID)|Default"
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [dismissalKey],
            now: now
        )
        // Note: actual key uses fullHost prefix; verify by computing one
        let withoutDismiss = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertEqual(withoutDismiss.count, 1)
        let actualKey = withoutDismiss[0].dismissalKey
        let dismissed = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [actualKey],
            now: now
        )
        XCTAssertTrue(dismissed.isEmpty)
        _ = result // silence warning
    }

    // MARK: - Skips entries without IDs

    func testEntriesWithoutBrowserIDIgnored() {
        let history = (0 ..< 5).map { i in
            makeEntry(url: "https://example.com/", browserID: nil, profileDir: nil, daysAgo: Double(i))
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testAppEntriesIgnored() {
        let history = (0 ..< 5).map { i in
            makeEntry(url: "https://example.com/", browserID: "com.tinyspeck.slackmacgap", profileDir: nil, daysAgo: Double(i), targetType: .app)
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Path-level suggestions

    func testPathSplitProducesTwoSuggestions() {
        // github.com/orgA → Chrome+Default, github.com/personal → Chrome+Personal
        var history: [HistoryEntry] = []
        for i in 0 ..< 5 {
            history.append(makeEntry(url: "https://github.com/orgA/repo", browserID: chromeID, profileDir: "Default", daysAgo: Double(i)))
            history.append(makeEntry(url: "https://github.com/personal/dotfiles", browserID: chromeID, profileDir: "Profile 1", daysAgo: Double(i) + 0.5))
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertEqual(result.count, 2)
        let patterns = Set(result.map(\.pattern))
        XCTAssertTrue(result.allSatisfy { $0.matchType == .regex })
        XCTAssertTrue(patterns.contains { $0.contains("orgA") })
        XCTAssertTrue(patterns.contains { $0.contains("personal") })
    }

    // MARK: - Subdomain differentiation

    func testSubdomainsAreSuggestedSeparately() {
        // app.example.com → Chrome, www.example.com → Firefox
        var history: [HistoryEntry] = []
        for i in 0 ..< 5 {
            history.append(makeEntry(url: "https://app.example.com/", browserID: chromeID, profileDir: "Default", daysAgo: Double(i)))
            history.append(makeEntry(url: "https://www.example.com/", browserID: firefoxID, profileDir: nil, daysAgo: Double(i) + 0.5))
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertEqual(result.count, 2)
        let patterns = Set(result.map(\.pattern))
        XCTAssertEqual(patterns, ["app.example.com", "www.example.com"])
    }

    // MARK: - Specificity preference

    func testHostLevelPreferredOverPathWhenSameTarget() {
        // All github opens go to Chrome+Default → host-only suggestion is enough
        var history: [HistoryEntry] = []
        for i in 0 ..< 5 {
            history.append(makeEntry(url: "https://github.com/orgA/repo1", browserID: chromeID, profileDir: "Default", daysAgo: Double(i)))
            history.append(makeEntry(url: "https://github.com/orgB/repo2", browserID: chromeID, profileDir: "Default", daysAgo: Double(i) + 0.3))
            history.append(makeEntry(url: "https://github.com/orgC/repo3", browserID: chromeID, profileDir: "Default", daysAgo: Double(i) + 0.6))
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        // Should be exactly one suggestion at the host level
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].matchType, .host)
        XCTAssertEqual(result[0].pattern, "github.com")
    }

    // MARK: - Regex escaping

    func testRegexPatternEscapesDots() {
        let scope = SuggestionScope.hostPath(host: "test.example.com", pathPrefix: "v1.0/api")
        let pattern = SuggestionEngine.regexPattern(for: scope)
        // Make sure regex actually compiles
        XCTAssertNoThrow(try NSRegularExpression(pattern: pattern))
        // And matches the expected URLs
        let regex = try? NSRegularExpression(pattern: pattern)
        let testURL = "https://test.example.com/v1.0/api/users"
        let range = NSRange(testURL.startIndex..., in: testURL)
        XCTAssertNotNil(regex?.firstMatch(in: testURL, range: range))
        // And does NOT match a non-matching URL
        let nonMatchURL = "https://testxexamplexcom/v1x0/api/users"
        let nonMatchRange = NSRange(nonMatchURL.startIndex..., in: nonMatchURL)
        XCTAssertNil(regex?.firstMatch(in: nonMatchURL, range: nonMatchRange))
    }

    // MARK: - Registrable domain

    func testRegistrableDomainSimple() {
        XCTAssertEqual(SuggestionEngine.registrableDomain(of: "www.example.com"), "example.com")
        XCTAssertEqual(SuggestionEngine.registrableDomain(of: "example.com"), "example.com")
        XCTAssertNil(SuggestionEngine.registrableDomain(of: "localhost"))
    }

    func testRegistrableDomainTwoLabel() {
        XCTAssertEqual(SuggestionEngine.registrableDomain(of: "www.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(SuggestionEngine.registrableDomain(of: "shop.example.com.ua"), "example.com.ua")
    }

    // MARK: - Any Profile fallback

    func testAnyProfileFallback() {
        // example.com opened equally in two Chrome profiles, neither dominates alone but Chrome does
        var history: [HistoryEntry] = []
        for i in 0 ..< 4 {
            history.append(makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Default", daysAgo: Double(i)))
            history.append(makeEntry(url: "https://example.com/", browserID: chromeID, profileDir: "Profile 1", daysAgo: Double(i) + 0.4))
        }
        let result = SuggestionEngine.suggest(
            history: history,
            rules: [],
            matcher: URLRuleMatcher(),
            dismissedKeys: [],
            now: now
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].browserID, chromeID)
        XCTAssertNil(result[0].profileDirectoryName, "Should suggest 'Any Profile' (nil) when browser dominates but no single profile does")
    }
}
