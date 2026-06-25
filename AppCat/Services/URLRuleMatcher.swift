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
        let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }

        switch rule.matchType {
        case .host:
            return matchesHost(url: url, pattern: pattern)
        case .hostContains:
            return matchesHostContains(url: url, pattern: pattern)
        case .urlContains:
            return matchesURLContains(url: url, pattern: pattern)
        case .regex:
            return matchesRegex(url: url, pattern: pattern)
        }
    }

    private func matchesURLContains(url: URL, pattern: String) -> Bool {
        return url.absoluteString.lowercased().contains(pattern.lowercased())
    }

    private func matchesHost(url: URL, pattern: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let p = normalizedHostPattern(pattern)
        guard !p.isEmpty else { return false }
        // Exact match or subdomain match
        return host == p || host.hasSuffix(".\(p)")
    }

    private func matchesHostContains(url: URL, pattern: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let p = normalizedHostPattern(pattern)
        guard !p.isEmpty else { return false }
        return host.contains(p)
    }

    private func normalizedHostPattern(_ pattern: String) -> String {
        let trimmed = pattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !trimmed.isEmpty else { return trimmed }

        if let host = URL(string: trimmed)?.host {
            return host.lowercased()
        }

        if let host = URL(string: "https://\(trimmed)")?.host {
            return host.lowercased()
        }

        return trimmed
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
