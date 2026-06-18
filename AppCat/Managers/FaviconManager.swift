import AppKit
import os

actor FaviconManager {
    static let shared = FaviconManager()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    /// Resolved + created once instead of running `createDirectory` on every property access.
    private let cacheDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AppCat/favicons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheDir = dir
        // Favicons are uniform 32×32 and disk-backed, so a small count cap is plenty to keep
        // resident memory bounded (NSCache also evicts under memory pressure).
        memoryCache.countLimit = 256
    }

    func favicon(for domain: String) async -> NSImage? {
        let normalizedDomain = domain.lowercased()
        let key = normalizedDomain as NSString

        // 1. Memory cache
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }

        // 2. Disk cache
        let diskURL = cacheDir.appendingPathComponent("\(key).png")
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: key)
            return image
        }

        // 3. Deduplicate in-flight requests
        if let existing = inFlight[normalizedDomain] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            await self.fetchAndCache(domain: normalizedDomain, key: key, diskURL: diskURL)
        }
        inFlight[normalizedDomain] = task
        let result = await task.value
        inFlight[normalizedDomain] = nil
        return result
    }

    func favicon(forURLString urlString: String, fallbackDomain: String? = nil) async -> NSImage? {
        let resolvedDomain: String?
        if let url = URL(string: urlString) {
            if url.scheme?.lowercased() == "https" {
                let metadata = await LinkMetadataManager.shared.metadata(for: url)
                resolvedDomain = metadata.finalHost
            } else {
                resolvedDomain = url.host?.lowercased()
            }
        } else {
            resolvedDomain = nil
        }

        let domain = (resolvedDomain ?? fallbackDomain)?.lowercased()
        guard let domain, !domain.isEmpty else { return nil }
        return await favicon(for: domain)
    }

    private func fetchAndCache(domain: String, key: NSString, diskURL: URL) async -> NSImage? {
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=32") else {
            return nil
        }

        do {
            let request = URLRequest(url: url, timeoutInterval: 5)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = NSImage(data: data)
            else { return nil }

            if let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            {
                try? png.write(to: diskURL, options: .atomic)
            }

            memoryCache.setObject(image, forKey: key)
            return image
        } catch {
            Log.app.debug("Favicon fetch failed for \(domain): \(error.localizedDescription)")
            return nil
        }
    }
}
