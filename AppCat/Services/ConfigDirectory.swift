import Foundation

enum ConfigDirectory {
    private static let fileManager = FileManager.default

    /// Resolved once. Previously a computed `var` that ran `createDirectory` on every storage read
    /// and write; now the directory is created a single time and every path property below is a
    /// pure string append with no syscall.
    static let base: URL = {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("AppCat")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var browsers: URL {
        base.appendingPathComponent("browsers.json")
    }

    static var rules: URL {
        base.appendingPathComponent("rules.json")
    }

    static var apps: URL {
        base.appendingPathComponent("apps.json")
    }

    static var history: URL {
        base.appendingPathComponent("history.json")
    }

    static var stats: URL {
        base.appendingPathComponent("stats.json")
    }

    static var appUsage: URL {
        base.appendingPathComponent("app_usage.json")
    }

    static var appActivations: URL {
        base.appendingPathComponent("app_activations.json")
    }

    static var dismissedSuggestions: URL {
        base.appendingPathComponent("dismissed_suggestions.json")
    }

    static var suggestionState: URL {
        base.appendingPathComponent("suggestion_state.json")
    }
}
