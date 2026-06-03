import XCTest
@testable import BrowserCat

final class URLRuleMatcherTests: XCTestCase {
    private func make(pattern: String, matchType: URLRule.MatchType) -> URLRule {
        URLRule(pattern: pattern, matchType: matchType, browserID: "test", isEnabled: true, sortOrder: 0)
    }

    func testHostExactMatch() {
        let m = URLRuleMatcher()
        let rule = make(pattern: "example.com", matchType: .host)
        XCTAssertNotNil(m.findMatchingRule(for: URL(string: "https://example.com/foo")!, rules: [rule]))
    }

    func testHostSubdomainMatch() {
        let m = URLRuleMatcher()
        let rule = make(pattern: "example.com", matchType: .host)
        XCTAssertNotNil(m.findMatchingRule(for: URL(string: "https://app.example.com/")!, rules: [rule]))
    }

    func testHostNoMatchOnDifferentDomain() {
        let m = URLRuleMatcher()
        let rule = make(pattern: "example.com", matchType: .host)
        XCTAssertNil(m.findMatchingRule(for: URL(string: "https://example.org/")!, rules: [rule]))
    }

    func testHostContainsMatch() {
        let m = URLRuleMatcher()
        let rule = make(pattern: "example", matchType: .hostContains)
        XCTAssertNotNil(m.findMatchingRule(for: URL(string: "https://my-example-app.io/")!, rules: [rule]))
    }

    func testURLContainsMatchesPath() {
        let m = URLRuleMatcher()
        let rule = make(pattern: "gitlab.com/travis-perkins", matchType: .urlContains)
        XCTAssertNotNil(m.findMatchingRule(for: URL(string: "https://gitlab.com/travis-perkins/repo")!, rules: [rule]))
        XCTAssertNotNil(m.findMatchingRule(for: URL(string: "https://gitlab.com/travis-perkins")!, rules: [rule]))
        XCTAssertNil(m.findMatchingRule(for: URL(string: "https://gitlab.com/other/repo")!, rules: [rule]))
    }

    func testURLContainsIsCaseInsensitive() {
        let m = URLRuleMatcher()
        let rule = make(pattern: "Travis-Perkins", matchType: .urlContains)
        XCTAssertNotNil(m.findMatchingRule(for: URL(string: "https://gitlab.com/travis-perkins/repo")!, rules: [rule]))
    }

    func testURLContainsEmptyPatternDoesNotMatch() {
        let m = URLRuleMatcher()
        let rule = make(pattern: "", matchType: .urlContains)
        XCTAssertNil(m.findMatchingRule(for: URL(string: "https://example.com/")!, rules: [rule]))
    }

    func testRegexMatch() {
        let m = URLRuleMatcher()
        let rule = make(pattern: "^https?://github\\.com/myorg/.*", matchType: .regex)
        XCTAssertNotNil(m.findMatchingRule(for: URL(string: "https://github.com/myorg/repo")!, rules: [rule]))
        XCTAssertNil(m.findMatchingRule(for: URL(string: "https://github.com/personal/repo")!, rules: [rule]))
    }

    func testInvalidRegexFailsGracefully() {
        let m = URLRuleMatcher()
        let rule = make(pattern: "[unclosed", matchType: .regex)
        XCTAssertNil(m.findMatchingRule(for: URL(string: "https://example.com/")!, rules: [rule]))
    }

    func testDisabledRuleNotMatched() {
        let m = URLRuleMatcher()
        var rule = make(pattern: "example.com", matchType: .host)
        rule.isEnabled = false
        XCTAssertNil(m.findMatchingRule(for: URL(string: "https://example.com/")!, rules: [rule]))
    }

    func testRulesEvaluatedInSortOrder() {
        let m = URLRuleMatcher()
        var firstRule = make(pattern: "example.com", matchType: .host)
        firstRule.sortOrder = 0
        let secondRule = URLRule(pattern: "example.com", matchType: .host, browserID: "second", isEnabled: true, sortOrder: 1)
        // Whichever has the lower sortOrder wins
        let match = m.findMatchingRule(for: URL(string: "https://example.com/")!, rules: [secondRule, firstRule])
        XCTAssertEqual(match?.browserID, "test")
    }
}
