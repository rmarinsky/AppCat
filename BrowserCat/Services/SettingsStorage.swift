import Foundation
import os

enum AppLanguage: String, CaseIterable, Identifiable {
    case ukrainian = "uk"
    case english = "en"

    static let `default`: AppLanguage = .ukrainian

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var displayNameKey: String {
        switch self {
        case .ukrainian:
            "Ukrainian"
        case .english:
            "English"
        }
    }
}

final class SettingsStorage {
    static let shared = SettingsStorage()

    private let defaults = UserDefaults.standard
    private let appLanguageKey = "appLanguage"

    // MARK: - Simple values

    var lastURL: String? {
        get { defaults.string(forKey: "lastURL") }
        set { defaults.set(newValue, forKey: "lastURL") }
    }

    var recentLinksCount: Int {
        get {
            let value = defaults.integer(forKey: "recentLinksCount")
            return value == 0 ? 3 : value
        }
        set { defaults.set(newValue, forKey: "recentLinksCount") }
    }

    var selectWithNumberKeys: Bool {
        get { defaults.object(forKey: "selectWithNumberKeys") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "selectWithNumberKeys") }
    }

    var compactPickerView: Bool {
        get { defaults.bool(forKey: "compactPickerView") }
        set { defaults.set(newValue, forKey: "compactPickerView") }
    }

    var appLanguage: AppLanguage {
        get {
            guard let storedValue = defaults.string(forKey: appLanguageKey),
                  let language = AppLanguage(rawValue: storedValue)
            else {
                return .default
            }
            return language
        }
        set { defaults.set(newValue.rawValue, forKey: appLanguageKey) }
    }

    func applyLanguagePreference() {
        let language = appLanguage
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
}
