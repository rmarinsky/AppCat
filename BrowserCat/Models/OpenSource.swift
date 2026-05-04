import Foundation

/// How a URL ended up being opened — used by StatsManager to weight time-saved.
enum OpenSource: Equatable {
    /// A URL rule matched in AppDelegate before the picker was shown.
    case autoRoute(ruleID: UUID)
    /// User pressed a hotkey character/keyCode in the picker.
    case pickerHotkey
    /// User clicked an item (or hit Return on focused item) in the picker.
    case pickerClick

    var ruleID: UUID? {
        if case let .autoRoute(id) = self { return id }
        return nil
    }

    var secondsSaved: TimeInterval {
        switch self {
        case .autoRoute: TimeSavedConstants.autoRoute
        case .pickerHotkey: TimeSavedConstants.pickerHotkey
        case .pickerClick: TimeSavedConstants.pickerClick
        }
    }
}

enum TimeSavedConstants {
    /// Auto-route via a rule — picker fully skipped, no decision needed.
    static let autoRoute: TimeInterval = 7
    /// Picker shown, user hit a hotkey to choose — fast keyboard-first flow.
    static let pickerHotkey: TimeInterval = 3
    /// Picker shown, user clicked or pressed Return on focused item.
    static let pickerClick: TimeInterval = 2
}
