import Foundation

struct LinkMetadata {
    let title: String?
    let finalHost: String?
}

actor LinkMetadataManager {
    static let shared = LinkMetadataManager()

    private static let cacheLimit = 500
    private var cache: [String: LinkMetadata] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: [String: Task<LinkMetadata, Never>] = [:]

    func metadata(for url: URL) async -> LinkMetadata {
        let key = url.absoluteString

        if let cached = cache[key] {
            return cached
        }

        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<LinkMetadata, Never> {
            await self.fetchMetadata(for: url)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        storeInCache(result, forKey: key)
        return result
    }

    private func storeInCache(_ metadata: LinkMetadata, forKey key: String) {
        cache[key] = metadata
        cacheOrder.append(key)
        if cacheOrder.count > Self.cacheLimit {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private func fetchMetadata(for url: URL) async -> LinkMetadata {
        guard url.scheme?.lowercased() == "https" else {
            return LinkMetadata(title: nil, finalHost: url.host?.lowercased())
        }

        var request = URLRequest(url: url, timeoutInterval: 5)
        request.httpMethod = "GET"
        request.setValue("bytes=0-16384", forHTTPHeaderField: "Range")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let finalURL = response.url ?? url
            let finalHost = finalURL.host?.lowercased()

            guard let html = String(data: data, encoding: .utf8) else {
                return LinkMetadata(title: nil, finalHost: finalHost)
            }

            let title = parseTitle(from: html)
            return LinkMetadata(title: title, finalHost: finalHost)
        } catch {
            return LinkMetadata(title: nil, finalHost: url.host?.lowercased())
        }
    }

    private func parseTitle(from html: String) -> String? {
        guard let startRange = html.range(of: "<title", options: .caseInsensitive),
              let closeTag = html[startRange.upperBound...].range(of: ">"),
              let endRange = html[closeTag.upperBound...].range(of: "</title>", options: .caseInsensitive)
        else {
            return nil
        }

        let title = String(html[closeTag.upperBound ..< endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? nil : title
    }
}
