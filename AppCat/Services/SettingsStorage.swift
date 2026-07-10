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

enum PickerActivationMode: String, CaseIterable, Identifiable {
    case toggleShortcut
    case holdOptionTab

    var id: String { rawValue }

    var localizedDisplayName: String {
        switch self {
        case .toggleShortcut:
            String(localized: "Toggle")
        case .holdOptionTab:
            String(localized: "Hold ⌥Tab")
        }
    }
}

enum PickerServiceKey: String, CaseIterable, Identifiable {
    case off
    case capsLock
    case escape

    var id: String { rawValue }

    var localizedDisplayName: String {
        switch self {
        case .off:
            String(localized: "Off")
        case .capsLock:
            String(localized: "Caps Lock")
        case .escape:
            String(localized: "Escape")
        }
    }
}

enum PickerServiceTapCount: Int, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3

    var id: Int { rawValue }

    var localizedDisplayName: String {
        switch self {
        case .one:
            String(localized: "1 tap")
        case .two:
            String(localized: "2 taps")
        case .three:
            String(localized: "3 taps")
        }
    }
}

struct PickerActivationSettings: Equatable {
    let mode: PickerActivationMode
    let serviceKey: PickerServiceKey
    let serviceTapCount: PickerServiceTapCount
    let serviceTapInterval: TimeInterval

    static let defaultValue = PickerActivationSettings(
        mode: .toggleShortcut,
        serviceKey: .off,
        serviceTapCount: .two,
        serviceTapInterval: 0.45
    )

    var needsEventTap: Bool {
        mode == .holdOptionTab || serviceKey != .off
    }
}

enum PickerScale {
    static let minimum = 0.5
    static let defaultValue = 1.0
    static let maximum = 2.0

    static func clamped(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }
}

enum PickerBackgroundStyle: String, CaseIterable, Identifiable {
    case liquidGlass
    case frosted
    case dimmed

    static let defaultValue: PickerBackgroundStyle = .liquidGlass

    var id: String { rawValue }

    var localizedDisplayName: String {
        switch self {
        case .liquidGlass:
            String(localized: "Liquid Glass")
        case .frosted:
            String(localized: "Frosted")
        case .dimmed:
            String(localized: "Dimmed")
        }
    }
}

final class SettingsStorage {
    static let shared = SettingsStorage()

    private let defaults = UserDefaults.standard
    private let appLanguageKey = "appLanguage"
    private let pickerLayoutKey = "pickerLayout"
    private let pickerActivationModeKey = "pickerActivationMode"
    private let pickerServiceKeyKey = "pickerServiceKey"
    private let pickerServiceTapCountKey = "pickerServiceTapCount"
    private let pickerScaleKey = "pickerScale"
    private let pickerBackgroundStyleKey = "pickerBackgroundStyle"
    private let hiddenPickerAppIDsKey = "hiddenPickerAppIDs"
    let pickerServiceTapInterval: TimeInterval = 0.45

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

    var hiddenPickerAppIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: hiddenPickerAppIDsKey) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: hiddenPickerAppIDsKey) }
    }

    var pickerScale: Double {
        get {
            guard let value = defaults.object(forKey: pickerScaleKey) as? Double else {
                return PickerScale.defaultValue
            }
            return PickerScale.clamped(value)
        }
        set { defaults.set(PickerScale.clamped(newValue), forKey: pickerScaleKey) }
    }

    var pickerBackgroundStyle: PickerBackgroundStyle {
        get {
            guard let value = defaults.string(forKey: pickerBackgroundStyleKey),
                  let style = PickerBackgroundStyle(rawValue: value)
            else {
                return .defaultValue
            }
            return style
        }
        set { defaults.set(newValue.rawValue, forKey: pickerBackgroundStyleKey) }
    }

    var pickerActivationMode: PickerActivationMode {
        get {
            guard let value = defaults.string(forKey: pickerActivationModeKey),
                  let mode = PickerActivationMode(rawValue: value)
            else {
                return .toggleShortcut
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: pickerActivationModeKey) }
    }

    var pickerServiceKey: PickerServiceKey {
        get {
            guard let value = defaults.string(forKey: pickerServiceKeyKey),
                  let key = PickerServiceKey(rawValue: value)
            else {
                return .off
            }
            return key
        }
        set { defaults.set(newValue.rawValue, forKey: pickerServiceKeyKey) }
    }

    var pickerServiceTapCount: PickerServiceTapCount {
        get {
            let value = defaults.integer(forKey: pickerServiceTapCountKey)
            return PickerServiceTapCount(rawValue: value) ?? .two
        }
        set { defaults.set(newValue.rawValue, forKey: pickerServiceTapCountKey) }
    }

    /// Show running apps that have no open windows in the switcher (dimmed, after the divider).
    /// Default on — they stay reachable, just visibly secondary.
    var showWindowlessApps: Bool {
        get { defaults.object(forKey: "showWindowlessApps") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showWindowlessApps") }
    }

    /// Include menu-bar / background apps (activation policy `.accessory` / `.prohibited`) in the
    /// switcher. Default off — utilities like brightness controllers are noise in a window switcher.
    var showBackgroundApps: Bool {
        get { defaults.object(forKey: "showBackgroundApps") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "showBackgroundApps") }
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
