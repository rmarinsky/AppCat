import Foundation

/// Strips wrapper-redirector hosts (Slack, Teams Safe Links, Instagram, Facebook,
/// Google search redirects, LinkedIn, Reddit, YouTube redirect) and pulls out
/// the real destination URL.
///
/// Two unwrapping strategies, applied in order:
///   1. Host/path-specific redirectors with a known query-param shape (precise).
///   2. Generic JWT heuristic: if any query-param value is a JWT whose payload
///      has a `*target_uri` / `*redirect_uri` claim pointing at an http(s) URL,
///      use that. This survives wrappers changing their host or path (Slack
///      desktop's OIDC redirect is the motivating example).
///
/// Idempotent and recursive (up to `maxRecursion`) so chained wrappers
/// (e.g. Slack → Outlook Safe Links → real URL) collapse to the final target.
enum URLUnwrapper {
    private static let maxRecursion = 5

    private struct Redirector {
        let hostMatches: (String) -> Bool
        let pathMatches: (String) -> Bool
        let extract: (URL) -> String?
    }

    private static let redirectors: [Redirector] = [
        // Slack legacy outbound link wrapper
        .init(
            hostMatches: { $0 == "slack-redir.net" || $0.hasSuffix(".slack-redir.net") },
            pathMatches: { _ in true },
            extract: queryParamExtractor(["url"])
        ),
        // Microsoft Teams / Outlook Safe Links
        .init(
            hostMatches: { $0.hasSuffix(".safelinks.protection.outlook.com") || $0 == "safelinks.protection.outlook.com" },
            pathMatches: { _ in true },
            extract: queryParamExtractor(["url"])
        ),
        // Instagram
        .init(
            hostMatches: { $0 == "l.instagram.com" },
            pathMatches: { _ in true },
            extract: queryParamExtractor(["u"])
        ),
        // Facebook
        .init(
            hostMatches: { $0 == "l.facebook.com" || $0 == "lm.facebook.com" || $0 == "m.facebook.com" },
            pathMatches: { _ in true },
            extract: queryParamExtractor(["u"])
        ),
        // Google search redirect: only on /url path
        .init(
            hostMatches: { $0 == "www.google.com" || $0 == "google.com" },
            pathMatches: { $0 == "/url" },
            extract: queryParamExtractor(["q", "url"])
        ),
        // LinkedIn redirect
        .init(
            hostMatches: { $0 == "www.linkedin.com" || $0 == "linkedin.com" },
            pathMatches: { $0 == "/redir/redirect" || $0 == "/redir/general-malware-page" },
            extract: queryParamExtractor(["url"])
        ),
        // Reddit out-bound
        .init(
            hostMatches: { $0 == "out.reddit.com" || $0 == "click.reddit.com" },
            pathMatches: { _ in true },
            extract: queryParamExtractor(["url"])
        ),
        // YouTube redirect
        .init(
            hostMatches: { $0 == "www.youtube.com" || $0 == "youtube.com" },
            pathMatches: { $0 == "/redirect" },
            extract: queryParamExtractor(["q"])
        ),
    ]

    static func unwrap(_ url: URL) -> URL {
        unwrap(url, depth: 0)
    }

    private static func unwrap(_ url: URL, depth: Int) -> URL {
        guard depth < maxRecursion else { return url }
        guard let host = url.host?.lowercased() else { return url }

        // 1. Host/path-specific redirectors
        for redirector in redirectors {
            guard redirector.hostMatches(host),
                  redirector.pathMatches(url.path) else { continue }

            guard let raw = redirector.extract(url), !raw.isEmpty else { return url }
            let decoded = decodeOnce(raw)
            if let parsed = URL(string: decoded), parsed.scheme != nil, parsed.host != nil {
                return unwrap(parsed, depth: depth + 1)
            }
            return url
        }

        // 2. Generic JWT heuristic — survives Slack changing host/path
        if let extracted = targetURIFromAnyJWTQueryParam(url) {
            return unwrap(extracted, depth: depth + 1)
        }

        return url
    }

    // MARK: - Generic query-param extractor

    private static func queryParamExtractor(_ params: [String]) -> (URL) -> String? {
        return { url in
            guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = comps.queryItems else { return nil }
            for name in params {
                if let v = items.first(where: { $0.name == name })?.value, !v.isEmpty {
                    return v
                }
            }
            return nil
        }
    }

    // MARK: - JWT heuristic

    /// Claim-key suffixes that signal "this claim holds the URL we should redirect to".
    /// Slack uses a namespaced key `https://slack.com/target_uri`; OAuth/OIDC also uses
    /// `redirect_uri`. Suffix-matching keeps us flexible to other providers.
    private static let targetClaimKeySuffixes: [String] = [
        "target_uri",
        "redirect_uri",
        "target_url",
        "redirect_url",
    ]

    private static func targetURIFromAnyJWTQueryParam(_ url: URL) -> URL? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return nil }
        for item in items {
            guard let value = item.value, value.count >= 20 else { continue } // JWTs are longer
            if let target = targetURI(fromJWT: value),
               let parsed = URL(string: target),
               (parsed.scheme?.lowercased().hasPrefix("http") ?? false),
               parsed.host != nil {
                return parsed
            }
        }
        return nil
    }

    /// Returns the value of the first claim whose key ends with one of `targetClaimKeySuffixes`,
    /// when that value parses as an http(s) URL.
    static func targetURI(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let payloadData = base64URLDecode(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { return nil }

        for (key, value) in json {
            guard targetClaimKeySuffixes.contains(where: { key.hasSuffix($0) }),
                  let str = value as? String,
                  let parsed = URL(string: str),
                  (parsed.scheme?.lowercased().hasPrefix("http") ?? false),
                  parsed.host != nil
            else { continue }
            return str
        }
        return nil
    }

    private static func base64URLDecode(_ s: String) -> Data? {
        var b64 = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        return Data(base64Encoded: b64)
    }

    // MARK: - Helpers

    /// Some wrappers (Outlook Safe Links) hand us a value that is still percent-encoded once.
    /// Try one decode pass; fall back to the original on miss.
    private static func decodeOnce(_ s: String) -> String {
        guard s.contains("%"), let decoded = s.removingPercentEncoding else { return s }
        return decoded
    }
}
