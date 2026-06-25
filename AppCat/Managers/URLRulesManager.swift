import Foundation
import os

@MainActor
final class URLRulesManager {
    private let urlRuleMatcher = URLRuleMatcher()

    func load(into state: AppState) {
        state.urlRules = RulesStorage.shared.load()
    }

    func save(_ rules: [URLRule]) {
        RulesStorage.shared.save(rules)
    }

    func findMatch(for url: URL, browsers: [InstalledBrowser], apps: [InstalledApp], rules: [URLRule]) -> URLRuleMatch? {
        guard let rule = urlRuleMatcher.findMatchingRule(for: url, rules: rules) else {
            return nil
        }

        switch rule.targetType {
        case .browser:
            if let browser = browsers.first(where: { $0.id == rule.browserID }) {
                let profile = rule.profileDirectoryName.flatMap { dirName in
                    browser.profiles.first { $0.directoryName == dirName }
                }
                return .browser(browser, profile: profile, ruleID: rule.id)
            }
            Log.rules.warning("Rule \(rule.id.uuidString) matched \(url.absoluteString) but browser target \(rule.browserID) was unavailable")
        case .app:
            if let app = apps.first(where: { $0.id == rule.browserID }) {
                return .app(app, ruleID: rule.id)
            }
            Log.rules.warning("Rule \(rule.id.uuidString) matched \(url.absoluteString) but app target \(rule.browserID) was unavailable")
        }

        return nil
    }
}

enum URLRuleMatch {
    case browser(InstalledBrowser, profile: BrowserProfile?, ruleID: UUID)
    case app(InstalledApp, ruleID: UUID)

    var ruleID: UUID {
        switch self {
        case let .browser(_, _, ruleID): ruleID
        case let .app(_, ruleID): ruleID
        }
    }
}
