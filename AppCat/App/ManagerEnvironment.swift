import SwiftUI

// MARK: - Environment Keys

private struct BrowserManagerKey: EnvironmentKey {
    static let defaultValue: BrowserManager? = nil
}

private struct AppManagerKey: EnvironmentKey {
    static let defaultValue: AppManager? = nil
}

private struct URLRulesManagerKey: EnvironmentKey {
    static let defaultValue: URLRulesManager? = nil
}

private struct DefaultBrowserManagerKey: EnvironmentKey {
    static let defaultValue: DefaultBrowserManager? = nil
}

private struct PickerCoordinatorKey: EnvironmentKey {
    static let defaultValue: PickerCoordinator? = nil
}

private struct HistoryManagerKey: EnvironmentKey {
    static let defaultValue: HistoryManager? = nil
}

private struct SuggestionsManagerKey: EnvironmentKey {
    static let defaultValue: SuggestionsManager? = nil
}

private struct StatsManagerKey: EnvironmentKey {
    static let defaultValue: StatsManager? = nil
}

private struct UpdaterManagerKey: EnvironmentKey {
    static let defaultValue: UpdaterManager? = nil
}

// MARK: - Environment Values

extension EnvironmentValues {
    var browserManager: BrowserManager? {
        get { self[BrowserManagerKey.self] }
        set { self[BrowserManagerKey.self] = newValue }
    }

    var appManager: AppManager? {
        get { self[AppManagerKey.self] }
        set { self[AppManagerKey.self] = newValue }
    }

    var urlRulesManager: URLRulesManager? {
        get { self[URLRulesManagerKey.self] }
        set { self[URLRulesManagerKey.self] = newValue }
    }

    var defaultBrowserManager: DefaultBrowserManager? {
        get { self[DefaultBrowserManagerKey.self] }
        set { self[DefaultBrowserManagerKey.self] = newValue }
    }

    var pickerCoordinator: PickerCoordinator? {
        get { self[PickerCoordinatorKey.self] }
        set { self[PickerCoordinatorKey.self] = newValue }
    }

    var historyManager: HistoryManager? {
        get { self[HistoryManagerKey.self] }
        set { self[HistoryManagerKey.self] = newValue }
    }

    var suggestionsManager: SuggestionsManager? {
        get { self[SuggestionsManagerKey.self] }
        set { self[SuggestionsManagerKey.self] = newValue }
    }

    var statsManager: StatsManager? {
        get { self[StatsManagerKey.self] }
        set { self[StatsManagerKey.self] = newValue }
    }

    var updaterManager: UpdaterManager? {
        get { self[UpdaterManagerKey.self] }
        set { self[UpdaterManagerKey.self] = newValue }
    }
}
