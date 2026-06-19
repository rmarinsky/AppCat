@testable import AppCat
import XCTest

final class URLRuleMatcherTests: XCTestCase {
    private func make(pattern: String, matchType: URLRule.MatchType) -> URLRule {
        URLRule(pattern: pattern, matchType: matchType, browserID: "test", isEnabled: true, sortOrder: 0)
    }

    func testHostExactMatch() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "example.com", matchType: .host)
        XCTAssertNotNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://example.com/foo")), rules: [rule]))
    }

    func testHostExactMatchSupportsLocalhostWithPort() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "localhost", matchType: .host)
        XCTAssertNotNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "http://localhost:3000/")), rules: [rule]))
    }

    func testHostSubdomainMatch() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "example.com", matchType: .host)
        XCTAssertNotNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://app.example.com/")), rules: [rule]))
    }

    func testHostNoMatchOnDifferentDomain() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "example.com", matchType: .host)
        XCTAssertNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://example.org/")), rules: [rule]))
    }

    func testHostContainsMatch() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "example", matchType: .hostContains)
        XCTAssertNotNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://my-example-app.io/")), rules: [rule]))
    }

    func testURLContainsMatchesPath() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "gitlab.com/travis-perkins", matchType: .urlContains)
        XCTAssertNotNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://gitlab.com/travis-perkins/repo")), rules: [rule]))
        XCTAssertNotNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://gitlab.com/travis-perkins")), rules: [rule]))
        XCTAssertNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://gitlab.com/other/repo")), rules: [rule]))
    }

    func testURLContainsIsCaseInsensitive() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "Travis-Perkins", matchType: .urlContains)
        XCTAssertNotNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://gitlab.com/travis-perkins/repo")), rules: [rule]))
    }

    func testURLContainsEmptyPatternDoesNotMatch() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "", matchType: .urlContains)
        XCTAssertNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://example.com/")), rules: [rule]))
    }

    func testEmptyPatternsDoNotMatchAnyRuleType() throws {
        let m = URLRuleMatcher()
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))
        for matchType in URLRule.MatchType.allCases {
            let rule = make(pattern: "   ", matchType: matchType)
            XCTAssertNil(m.findMatchingRule(for: url, rules: [rule]), "\(matchType) should ignore blank patterns")
        }
    }

    func testHostPatternsThatNormalizeToEmptyDoNotMatch() throws {
        let m = URLRuleMatcher()
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))
        XCTAssertNil(m.findMatchingRule(for: url, rules: [make(pattern: "/", matchType: .host)]))
        XCTAssertNil(m.findMatchingRule(for: url, rules: [make(pattern: "/", matchType: .hostContains)]))
    }

    func testHostPatternTrimsWhitespace() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: " example.com ", matchType: .host)
        XCTAssertNotNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://app.example.com/")), rules: [rule]))
    }

    func testHostPatternAcceptsTrailingSlash() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "constructionline.atlassian.net/", matchType: .host)
        XCTAssertNotNil(try m.findMatchingRule(
            for: XCTUnwrap(URL(string: "https://constructionline.atlassian.net/browse/VEL-135")),
            rules: [rule]
        ))
    }

    func testHostPatternAcceptsFullURLWithPath() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "https://constructionline.atlassian.net/browse/VEL-135", matchType: .host)
        XCTAssertNotNil(try m.findMatchingRule(
            for: XCTUnwrap(URL(string: "https://constructionline.atlassian.net/browse/VEL-136")),
            rules: [rule]
        ))
    }

    func testHostContainsPatternAcceptsFullURL() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "https://constructionline.atlassian.net/browse/VEL-135", matchType: .hostContains)
        XCTAssertNotNil(try m.findMatchingRule(
            for: XCTUnwrap(URL(string: "https://constructionline.atlassian.net/browse/VEL-136")),
            rules: [rule]
        ))
    }

    func testRegexMatch() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "^https?://github\\.com/myorg/.*", matchType: .regex)
        XCTAssertNotNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://github.com/myorg/repo")), rules: [rule]))
        XCTAssertNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://github.com/personal/repo")), rules: [rule]))
    }

    func testInvalidRegexFailsGracefully() throws {
        let m = URLRuleMatcher()
        let rule = make(pattern: "[unclosed", matchType: .regex)
        XCTAssertNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://example.com/")), rules: [rule]))
    }

    func testDisabledRuleNotMatched() throws {
        let m = URLRuleMatcher()
        var rule = make(pattern: "example.com", matchType: .host)
        rule.isEnabled = false
        XCTAssertNil(try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://example.com/")), rules: [rule]))
    }

    func testRulesEvaluatedInSortOrder() throws {
        let m = URLRuleMatcher()
        var firstRule = make(pattern: "example.com", matchType: .host)
        firstRule.sortOrder = 0
        let secondRule = URLRule(pattern: "example.com", matchType: .host, browserID: "second", isEnabled: true, sortOrder: 1)
        // Whichever has the lower sortOrder wins
        let match = try m.findMatchingRule(for: XCTUnwrap(URL(string: "https://example.com/")), rules: [secondRule, firstRule])
        XCTAssertEqual(match?.browserID, "test")
    }
}
