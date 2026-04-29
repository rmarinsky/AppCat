import Foundation
import os

final class URLRuleMatcher {
    private var regexCache: [String: NSRegularExpression] = [:]

    func findMatchingRule(for url: URL, rules: [URLRule]) -> URLRule? {
        let enabledRules = rules
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }

        for rule in enabledRules {
            if matches(url: url, rule: rule) {
                Log.rules.debug("URL \(url) matched rule: \(rule.pattern) (\(rule.matchType.rawValue))")
                return rule
            }
        }
        return nil
    }

    private func matches(url: URL, rule: URLRule) -> Bool {
        switch rule.matchType {
        case .host:
            return matchesHost(url: url, pattern: rule.pattern)
        case .hostContains:
            return matchesHostContains(url: url, pattern: rule.pattern)
        case .urlContains:
            return matchesURLContains(url: url, pattern: rule.pattern)
        case .regex:
            return matchesRegex(url: url, pattern: rule.pattern)
        }
    }

    private func matchesURLContains(url: URL, pattern: String) -> Bool {
        guard !pattern.isEmpty else { return false }
        return url.absoluteString.lowercased().contains(pattern.lowercased())
    }

    private func matchesHost(url: URL, pattern: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let p = pattern.lowercased()
        // Exact match or subdomain match
        return host == p || host.hasSuffix(".\(p)")
    }

    private func matchesHostContains(url: URL, pattern: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains(pattern.lowercased())
    }

    private func matchesRegex(url: URL, pattern: String) -> Bool {
        let urlString = url.absoluteString
        let regex: NSRegularExpression
        if let cached = regexCache[pattern] {
            regex = cached
        } else {
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                Log.rules.error("Invalid regex pattern: \(pattern)")
                return false
            }
            regexCache[pattern] = compiled
            regex = compiled
        }
        let range = NSRange(urlString.startIndex..., in: urlString)
        return regex.firstMatch(in: urlString, range: range) != nil
    }
}
