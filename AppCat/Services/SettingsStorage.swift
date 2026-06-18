import Foundation
import os

enum AppLanguage: String, CaseIterable, Identifiable {
    case ukrainian = "uk"
    case english = "en"

    static let `default`: AppLanguage = .ukrainian

    var id: String {
        rawValue
    }

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

    var localizedDisplayName: String {
        switch self {
        case .ukrainian:
            String(localized: "Ukrainian")
        case .english:
            String(localized: "English")
        }
    }
}

enum PickerLayout: String, CaseIterable, Identifiable {
    case vertical
    case horizontal

    var id: String {
        rawValue
    }

    var localizedDisplayName: String {
        switch self {
        case .vertical:
            String(localized: "Vertical")
        case .horizontal:
            String(localized: "Horizontal")
        }
    }
}

final class SettingsStorage {
    static let shared = SettingsStorage()

    private let defaults = UserDefaults.standard
    private let appLanguageKey = "appLanguage"
    private let pickerLayoutKey = "pickerLayout"

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

    var pickerLayout: PickerLayout {
        get {
            if let storedValue = defaults.string(forKey: pickerLayoutKey),
               let layout = PickerLayout(rawValue: storedValue)
            {
                return layout
            }

            return defaults.bool(forKey: "compactPickerView") ? .horizontal : .vertical
        }
        set {
            defaults.set(newValue.rawValue, forKey: pickerLayoutKey)
            defaults.set(newValue == .horizontal, forKey: "compactPickerView")
        }
    }

    var compactPickerView: Bool {
        get { pickerLayout == .horizontal }
        set { pickerLayout = newValue ? .horizontal : .vertical }
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
