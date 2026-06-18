import Foundation
import os

enum Log {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppCat", category: "app")
    static let browser = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppCat", category: "browser")
    static let picker = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppCat", category: "picker")
    static let settings = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppCat", category: "settings")
    static let profiles = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppCat", category: "profiles")
    static let rules = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppCat", category: "rules")
    static let apps = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppCat", category: "apps")
    static let history = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AppCat", category: "history")
}
