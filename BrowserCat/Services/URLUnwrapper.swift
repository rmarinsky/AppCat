import Foundation

/// Strips wrapper-redirector hosts (Slack, Teams Safe Links, Instagram, Facebook,
/// Google search redirects, LinkedIn, Reddit, YouTube redirect) and pulls out the
/// real destination URL.
///
/// Idempotent and recursive (up to a sensible depth) so chained redirectors
/// (e.g. Slack → Outlook Safe Links → real URL) get fully unwrapped.
enum URLUnwrapper {
    private static let maxRecursion = 5

    private struct Redirector {
        let hostMatches: (String) -> Bool
        let pathMatches: (String) -> Bool
        let queryParams: [String]
    }

    private static let redirectors: [Redirector] = [
        // Slack
        .init(
            hostMatches: { $0 == "slack-redir.net" || $0.hasSuffix(".slack-redir.net") },
            pathMatches: { _ in true },
            queryParams: ["url"]
        ),
        // Microsoft Teams / Outlook Safe Links
        .init(
            hostMatches: { $0.hasSuffix(".safelinks.protection.outlook.com") || $0 == "safelinks.protection.outlook.com" },
            pathMatches: { _ in true },
            queryParams: ["url"]
        ),
        // Instagram
        .init(
            hostMatches: { $0 == "l.instagram.com" },
            pathMatches: { _ in true },
            queryParams: ["u"]
        ),
        // Facebook
        .init(
            hostMatches: { $0 == "l.facebook.com" || $0 == "lm.facebook.com" || $0 == "m.facebook.com" },
            pathMatches: { _ in true },
            queryParams: ["u"]
        ),
        // Google search redirect: only on /url path
        .init(
            hostMatches: { $0 == "www.google.com" || $0 == "google.com" },
            pathMatches: { $0 == "/url" },
            queryParams: ["q", "url"]
        ),
        // LinkedIn redirect
        .init(
            hostMatches: { $0 == "www.linkedin.com" || $0 == "linkedin.com" },
            pathMatches: { $0 == "/redir/redirect" || $0 == "/redir/general-malware-page" },
            queryParams: ["url"]
        ),
        // Reddit out-bound
        .init(
            hostMatches: { $0 == "out.reddit.com" || $0 == "click.reddit.com" },
            pathMatches: { _ in true },
            queryParams: ["url"]
        ),
        // YouTube redirect
        .init(
            hostMatches: { $0 == "www.youtube.com" || $0 == "youtube.com" },
            pathMatches: { $0 == "/redirect" },
            queryParams: ["q"]
        ),
        // X/Twitter t.co — query-less HTTP shortener; can't be resolved without
        // a network call, so we skip it. Documented here for future reference.
    ]

    static func unwrap(_ url: URL) -> URL {
        unwrap(url, depth: 0)
    }

    private static func unwrap(_ url: URL, depth: Int) -> URL {
        guard depth < maxRecursion else { return url }
        guard let host = url.host?.lowercased() else { return url }

        for redirector in redirectors {
            guard redirector.hostMatches(host),
                  redirector.pathMatches(url.path) else { continue }

            guard let target = extractTarget(from: url, params: redirector.queryParams) else { return url }
            return unwrap(target, depth: depth + 1)
        }
        return url
    }

    private static func extractTarget(from url: URL, params: [String]) -> URL? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems else { return nil }

        for paramName in params {
            guard let raw = items.first(where: { $0.name == paramName })?.value,
                  !raw.isEmpty else { continue }

            // queryItems values are already percent-decoded by URLComponents.
            // Some wrappers (Outlook Safe Links) double-encode — try one more decode pass
            // if the value still looks percent-encoded.
            let candidate: String = {
                if raw.contains("%") , let again = raw.removingPercentEncoding {
                    return again
                }
                return raw
            }()

            if let parsed = URL(string: candidate), parsed.scheme != nil, parsed.host != nil {
                return parsed
            }
        }
        return nil
    }
}
