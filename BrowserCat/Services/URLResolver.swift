import Foundation
import os

/// Follows server-side redirects (301/302/303/307/308) for a URL and returns
/// the final destination — so history reflects the actual page the user lands on,
/// not a CDN/redirector intermediary (e.g. office.com → microsoft.com).
///
/// Uses a HEAD request to avoid downloading page bodies, falls back to GET on 405.
final class URLResolver: NSObject, Sendable {
    private let session: URLSession

    override init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        config.httpAdditionalHeaders = ["User-Agent": "BrowserCat/1.0"]
        // We want URLSession to follow redirects up to its default limit (~16) — using
        // its built-in delegate handling rather than a custom non-following delegate so
        // the chain resolves in a single dataTask without manual recursion.
        session = URLSession(configuration: config)
        super.init()
    }

    /// Resolves the final URL after server redirects. Returns nil if the request
    /// failed, timed out, or the URL is not http(s).
    func resolveFinalURL(for url: URL) async -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }

        if let head = await fetch(method: "HEAD", url: url) { return head }
        return await fetch(method: "GET", url: url)
    }

    private func fetch(method: String, url: URL) async -> URL? {
        var req = URLRequest(url: url)
        req.httpMethod = method
        do {
            let (_, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            // Some servers return 405 to HEAD — let the caller retry with GET.
            if method == "HEAD", http.statusCode == 405 { return nil }
            return http.url
        } catch {
            Log.app.debug("URLResolver \(method) failed for \(url.absoluteString): \(error.localizedDescription)")
            return nil
        }
    }
}
