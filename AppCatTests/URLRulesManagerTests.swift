@testable import AppCat
import XCTest

@MainActor
final class URLRulesManagerTests: XCTestCase {
    private func chrome(profiles: [BrowserProfile] = []) -> InstalledBrowser {
        InstalledBrowser(
            id: "com.google.Chrome",
            displayName: "Chrome",
            appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            isVisible: true,
            sortOrder: 0,
            supportsPrivateMode: true,
            profileType: .chromium,
            profiles: profiles
        )
    }

    func testFindMatchResolvesBrowserOnly() throws {
        let m = URLRulesManager()
        let rule = URLRule(
            pattern: "example.com",
            matchType: .host,
            browserID: "com.google.Chrome",
            targetType: .browser
        )
        let browsers = [chrome()]
        let match = try m.findMatch(
            for: XCTUnwrap(URL(string: "https://example.com/")),
            browsers: browsers,
            apps: [],
            rules: [rule]
        )
        guard case let .browser(b, profile, _)? = match else {
            return XCTFail("Expected .browser match")
        }
        XCTAssertEqual(b.id, "com.google.Chrome")
        XCTAssertNil(profile)
    }

    func testFindMatchResolvesProfile() throws {
        let m = URLRulesManager()
        let workProfile = BrowserProfile(directoryName: "Default", displayName: "Work", email: "work@x.com")
        let personalProfile = BrowserProfile(directoryName: "Profile 1", displayName: "Personal", email: nil)
        let rule = URLRule(
            pattern: "example.com",
            matchType: .host,
            browserID: "com.google.Chrome",
            profileDirectoryName: "Profile 1",
            targetType: .browser
        )
        let match = try m.findMatch(
            for: XCTUnwrap(URL(string: "https://example.com/")),
            browsers: [chrome(profiles: [workProfile, personalProfile])],
            apps: [],
            rules: [rule]
        )
        guard case let .browser(_, profile, _)? = match else {
            return XCTFail("Expected .browser match")
        }
        XCTAssertEqual(profile?.directoryName, "Profile 1")
    }

    func testFindMatchResolvesHostRuleWithTrailingSlash() throws {
        let m = URLRulesManager()
        let workProfile = BrowserProfile(directoryName: "Default", displayName: "Work", email: "work@x.com")
        let rule = URLRule(
            pattern: "constructionline.atlassian.net/",
            matchType: .host,
            browserID: "com.google.Chrome",
            profileDirectoryName: "Default",
            targetType: .browser
        )
        let match = try m.findMatch(
            for: XCTUnwrap(URL(string: "https://constructionline.atlassian.net/browse/VEL-135")),
            browsers: [chrome(profiles: [workProfile])],
            apps: [],
            rules: [rule]
        )
        guard case let .browser(browser, profile, ruleID)? = match else {
            return XCTFail("Expected .browser match")
        }
        XCTAssertEqual(browser.id, "com.google.Chrome")
        XCTAssertEqual(profile?.directoryName, "Default")
        XCTAssertEqual(ruleID, rule.id)
    }

    func testFindMatchReturnsNilWhenBrowserUninstalled() throws {
        let m = URLRulesManager()
        let rule = URLRule(
            pattern: "example.com",
            matchType: .host,
            browserID: "com.unknown.Browser",
            targetType: .browser
        )
        let match = try m.findMatch(
            for: XCTUnwrap(URL(string: "https://example.com/")),
            browsers: [chrome()],
            apps: [],
            rules: [rule]
        )
        XCTAssertNil(match)
    }

    func testFindMatchReturnsNilWhenNoRuleMatches() throws {
        let m = URLRulesManager()
        let rule = URLRule(
            pattern: "example.com",
            matchType: .host,
            browserID: "com.google.Chrome",
            targetType: .browser
        )
        let match = try m.findMatch(
            for: XCTUnwrap(URL(string: "https://different.org/")),
            browsers: [chrome()],
            apps: [],
            rules: [rule]
        )
        XCTAssertNil(match)
    }
}
