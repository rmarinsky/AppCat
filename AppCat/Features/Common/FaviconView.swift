import SwiftUI

struct FaviconView: View {
    let urlString: String?
    let domain: String
    var size: CGFloat = 16

    @State private var image: NSImage?

    init(domain: String, size: CGFloat = 16) {
        urlString = nil
        self.domain = domain
        self.size = size
    }

    init(urlString: String, fallbackDomain: String? = nil, size: CGFloat = 16) {
        self.urlString = urlString
        domain = fallbackDomain ?? URL(string: urlString)?.host ?? urlString
        self.size = size
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.75))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: cacheKey) {
            if let urlString {
                image = await FaviconManager.shared.favicon(forURLString: urlString, fallbackDomain: domain)
            } else {
                image = await FaviconManager.shared.favicon(for: domain)
            }
        }
    }

    private var cacheKey: String {
        if let urlString {
            return "url:\(urlString)"
        }
        return "domain:\(domain)"
    }
}
