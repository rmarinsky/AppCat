import Foundation
import os

/// Persists how often / how recently each app has been *activated* on the system (frontmost),
/// observed via `NSWorkspace.didActivateApplicationNotification`. This is the real usage signal
/// the app switcher sorts by — independent of whether the app was ever opened through AppCat
/// (which `AppUsageStorage` tracks separately for file routing).
final class AppActivationStore {
    static let shared = AppActivationStore()
    private let fileManager = FileManager.default
    // Serial, off-main; preserves write order. `stats` is a value-type snapshot.
    private let ioQueue = DispatchQueue(label: "ua.com.rmarinsky.appcat.appactivations-io", qos: .utility)

    func save(_ stats: [String: AppUsage]) {
        ioQueue.async {
            do {
                let data = try JSONEncoder().encode(stats)
                try data.write(to: ConfigDirectory.appActivations, options: .atomic)
            } catch {
                Log.app.error("Failed to save app activations: \(error.localizedDescription)")
            }
        }
    }

    func load() -> [String: AppUsage] {
        guard fileManager.fileExists(atPath: ConfigDirectory.appActivations.path) else { return [:] }
        do {
            let data = try Data(contentsOf: ConfigDirectory.appActivations)
            return try JSONDecoder().decode([String: AppUsage].self, from: data)
        } catch {
            Log.app.error("Failed to load app activations: \(error.localizedDescription)")
            return [:]
        }
    }
}
