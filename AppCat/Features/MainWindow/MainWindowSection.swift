import Foundation

enum MainWindowSection: String, Hashable {
    case overview
    case history
    case suggestions
    case settingsGeneral
    case settingsBrowsers
    case settingsApps
    case settingsRules
    case settingsShortcuts
    case settingsAccount

    var label: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .history: String(localized: "History")
        case .suggestions: String(localized: "Suggestions")
        case .settingsGeneral: String(localized: "General")
        case .settingsBrowsers: String(localized: "Browsers")
        case .settingsApps: String(localized: "Apps")
        case .settingsRules: String(localized: "Rules")
        case .settingsShortcuts: String(localized: "Shortcuts")
        case .settingsAccount: String(localized: "Account")
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .history: "clock"
        case .suggestions: "lightbulb"
        case .settingsGeneral: "gear"
        case .settingsBrowsers: "globe"
        case .settingsApps: "square.grid.2x2"
        case .settingsRules: "arrow.triangle.branch"
        case .settingsShortcuts: "keyboard"
        case .settingsAccount: "person.circle"
        }
    }

    var isSettings: Bool {
        switch self {
        case .settingsGeneral, .settingsBrowsers, .settingsApps, .settingsRules,
             .settingsShortcuts, .settingsAccount:
            return true
        default:
            return false
        }
    }
}
