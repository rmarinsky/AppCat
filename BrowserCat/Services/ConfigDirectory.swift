import Foundation

enum ConfigDirectory {
    private static let fileManager = FileManager.default

    static var base: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BrowserCat")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var browsers: URL { base.appendingPathComponent("browsers.json") }
    static var rules: URL { base.appendingPathComponent("rules.json") }
    static var apps: URL { base.appendingPathComponent("apps.json") }
    static var history: URL { base.appendingPathComponent("history.json") }
    static var dismissedSuggestions: URL { base.appendingPathComponent("dismissed_suggestions.json") }
    static var suggestionState: URL { base.appendingPathComponent("suggestion_state.json") }
}
