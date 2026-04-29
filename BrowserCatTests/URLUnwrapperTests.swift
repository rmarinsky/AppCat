import XCTest
@testable import BrowserCat

final class URLUnwrapperTests: XCTestCase {
    private func unwrap(_ s: String) -> String {
        URLUnwrapper.unwrap(URL(string: s)!).absoluteString
    }

    // MARK: - Plain URLs are pass-through

    func testPlainURLUnchanged() {
        XCTAssertEqual(unwrap("https://github.com/orgA/repo"), "https://github.com/orgA/repo")
    }

    func testNoQueryParamsUnchanged() {
        XCTAssertEqual(unwrap("https://example.com/path"), "https://example.com/path")
    }

    // MARK: - Slack

    func testSlackRedirector() {
        let wrapped = "https://slack-redir.net/link?url=https%3A%2F%2Fgithub.com%2Forg%2Frepo&v=3"
        XCTAssertEqual(unwrap(wrapped), "https://github.com/org/repo")
    }

    // MARK: - Outlook Safe Links

    func testOutlookSafeLinks() {
        let wrapped = "https://nam11.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2Fteam%2Fissue%2F123&data=05%7C..."
        XCTAssertEqual(unwrap(wrapped), "https://github.com/team/issue/123")
    }

    // MARK: - Instagram

    func testInstagramRedirector() {
        let wrapped = "https://l.instagram.com/?u=https%3A%2F%2Fgithub.com%2Ffoo&e=ABCDE"
        XCTAssertEqual(unwrap(wrapped), "https://github.com/foo")
    }

    // MARK: - Facebook

    func testFacebookRedirector() {
        let wrapped = "https://l.facebook.com/l.php?u=https%3A%2F%2Fgithub.com%2Fbar&h=AT00000"
        XCTAssertEqual(unwrap(wrapped), "https://github.com/bar")
    }

    // MARK: - Google search

    func testGoogleSearchRedirector() {
        let wrapped = "https://www.google.com/url?sa=t&url=https%3A%2F%2Fgithub.com%2Fbaz&usg=ABCDEF"
        XCTAssertEqual(unwrap(wrapped), "https://github.com/baz")
    }

    func testGoogleNonRedirectPathUnchanged() {
        // /search should not be unwrapped
        let plain = "https://www.google.com/search?q=hello"
        XCTAssertEqual(unwrap(plain), plain)
    }

    // MARK: - YouTube

    func testYouTubeRedirector() {
        let wrapped = "https://www.youtube.com/redirect?q=https%3A%2F%2Fgithub.com%2Fqux&v=ABCD"
        XCTAssertEqual(unwrap(wrapped), "https://github.com/qux")
    }

    func testYouTubeWatchPathUnchanged() {
        let plain = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        XCTAssertEqual(unwrap(plain), plain)
    }

    // MARK: - LinkedIn

    func testLinkedInRedirector() {
        let wrapped = "https://www.linkedin.com/redir/redirect?url=https%3A%2F%2Fgithub.com%2Flink"
        XCTAssertEqual(unwrap(wrapped), "https://github.com/link")
    }

    // MARK: - Reddit

    func testRedditOutbound() {
        let wrapped = "https://out.reddit.com/?url=https%3A%2F%2Fgithub.com%2Frrr"
        XCTAssertEqual(unwrap(wrapped), "https://github.com/rrr")
    }

    // MARK: - Idempotence + recursion

    func testUnwrapIsIdempotent() {
        let plain = "https://github.com/foo"
        XCTAssertEqual(unwrap(plain), unwrap(unwrap(plain)))
    }

    func testNestedRedirectorsUnwrappedRecursively() {
        // Slack → Outlook Safe Links → final
        let inner = "https://nam11.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2Ffinal"
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+/:"))
        let encodedInner = inner.addingPercentEncoding(withAllowedCharacters: allowed)!
        let outer = "https://slack-redir.net/link?url=\(encodedInner)"
        XCTAssertEqual(unwrap(outer), "https://github.com/final")
    }

    // MARK: - Malformed inputs

    func testMissingQueryParamReturnsOriginal() {
        let wrapped = "https://l.instagram.com/?nope=1"
        XCTAssertEqual(unwrap(wrapped), wrapped)
    }

    func testEmptyQueryParamReturnsOriginal() {
        let wrapped = "https://l.instagram.com/?u="
        XCTAssertEqual(unwrap(wrapped), wrapped)
    }

    func testInvalidTargetReturnsOriginal() {
        let wrapped = "https://l.instagram.com/?u=not-a-url"
        XCTAssertEqual(unwrap(wrapped), wrapped)
    }
}
