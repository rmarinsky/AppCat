import Foundation

/// How often an app has been used as an open target, for frequency-based sorting.
struct AppUsage: Codable, Equatable {
    var count: Int
    var lastUsed: Date
}
