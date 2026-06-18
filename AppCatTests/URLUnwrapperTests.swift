@testable import AppCat
import XCTest

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

    // MARK: - Slack OIDC desktop redirect (JWT login_hint)

    private func makeSlackOIDCJWT(targetURI: String) -> String {
        let header = ["alg": "RS256", "typ": "JWT"]
        let payload: [String: Any] = [
            "iss": "https://slack.com",
            "sub": "user@example.com",
            "aud": "1234567890.0987654321",
            "exp": 1_777_460_323,
            "iat": 1_777_460_316,
            "https://slack.com/target_uri": targetURI,
        ]
        return [header, payload]
            .map { try! JSONSerialization.data(withJSONObject: $0) }
            .map { $0.base64EncodedString() }
            .map { $0.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
            .joined(separator: ".")
            + ".fake-signature"
    }

    func testSlackOIDCJWTRedirect() {
        let target = "https://travisperkins.atlassian.net/wiki/spaces/QA/pages/123/Test"
        let jwt = makeSlackOIDCJWT(targetURI: target)
        let wrapped = "https://slack.com/openid/connect/login_initiate_redirect?login_hint=\(jwt)"
        XCTAssertEqual(unwrap(wrapped), target)
    }

    func testSlackOIDCNonRedirectPathUnchanged() {
        // No JWT in query → no unwrap, regardless of path
        let plain = "https://slack.com/messages/general"
        XCTAssertEqual(unwrap(plain), plain)
    }

    func testJWTHeuristicSurvivesHostOrPathChange() {
        // If Slack changes the host/path, we still unwrap as long as the JWT carries the claim
        let target = "https://github.com/foo"
        let jwt = makeSlackOIDCJWT(targetURI: target)
        XCTAssertEqual(unwrap("https://app.slack.com/some/new/path?login_hint=\(jwt)"), target)
        XCTAssertEqual(unwrap("https://workspace.slack.com/openid/v2/redirect?token=\(jwt)"), target)
    }

    func testGenericRedirectURIClaim() {
        // OIDC standard `redirect_uri` claim should also work
        let header = ["alg": "RS256", "typ": "JWT"]
        let payload: [String: Any] = ["redirect_uri": "https://example.org/dest"]
        let jwt = [header, payload]
            .map { try! JSONSerialization.data(withJSONObject: $0) }
            .map { $0.base64EncodedString().replacingOccurrences(of: "=", with: "") }
            .joined(separator: ".") + ".sig"
        XCTAssertEqual(unwrap("https://anything.example.com/x?login_hint=\(jwt)"), "https://example.org/dest")
    }

    func testJWTWithIssClaimDoesNotFalsePositive() {
        // A JWT with an `iss` claim (issuer URL) should NOT be treated as a redirect
        let header = ["alg": "RS256", "typ": "JWT"]
        let payload: [String: Any] = ["iss": "https://login.example.com", "sub": "user"]
        let jwt = [header, payload]
            .map { try! JSONSerialization.data(withJSONObject: $0) }
            .map { $0.base64EncodedString().replacingOccurrences(of: "=", with: "") }
            .joined(separator: ".") + ".sig"
        let plain = "https://example.com/auth?id_token=\(jwt)"
        XCTAssertEqual(unwrap(plain), plain)
    }

    func testSlackOIDCMissingTargetClaimReturnsOriginal() {
        let header = ["alg": "RS256", "typ": "JWT"]
        let payload: [String: Any] = ["iss": "https://slack.com", "sub": "no-target"]
        let jwt = [header, payload]
            .map { try! JSONSerialization.data(withJSONObject: $0) }
            .map { $0.base64EncodedString().replacingOccurrences(of: "=", with: "") }
            .joined(separator: ".") + ".sig"
        let wrapped = "https://slack.com/openid/connect/login_initiate_redirect?login_hint=\(jwt)"
        XCTAssertEqual(unwrap(wrapped), wrapped)
    }

    func testSlackOIDCMalformedJWTReturnsOriginal() {
        let wrapped = "https://slack.com/openid/connect/login_initiate_redirect?login_hint=not-a-jwt"
        XCTAssertEqual(unwrap(wrapped), wrapped)
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

    func testNestedRedirectorsUnwrappedRecursively() throws {
        // Slack → Outlook Safe Links → final
        let inner = "https://nam11.safelinks.protection.outlook.com/?url=https%3A%2F%2Fgithub.com%2Ffinal"
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?+/:"))
        let encodedInner = try XCTUnwrap(inner.addingPercentEncoding(withAllowedCharacters: allowed))
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
