import Foundation
import os

@MainActor
final class BrowserManager {
    private let browserDetector = BrowserDetector()
    private let profileDetector = ProfileDetector()
    private let configStorage: BrowserConfigStorage

    init(configStorage: BrowserConfigStorage = .shared) {
        self.configStorage = configStorage
    }

    func refreshBrowsers(into state: AppState) {
        let detected = browserDetector.detectBrowsers()
        let savedConfigs: [BrowserConfig]?
        let canPersist: Bool
        switch configStorage.load() {
        case .missing:
            savedConfigs = nil
            canPersist = true
        case let .loaded(configs):
            savedConfigs = configs
            canPersist = true
        case .failed:
            savedConfigs = nil
            canPersist = false
        }

        var browsers: [InstalledBrowser]
        if let savedConfigs {
            browsers = mergeDetectedWithSaved(
                detected: detected,
                saved: savedConfigs,
                configID: \.id,
                sortOrder: \.sortOrder
            ) { browser, config in
                browser.isVisible = config.isVisible
                browser.isIgnored = config.isIgnored
                browser.hotkey = config.hotkey?.first
                browser.hotkeyKeyCode = config.hotkeyKeyCode ?? config.hotkey?.first.flatMap { KeyCodeMap.keyCode(for: $0) }
                browser.sortOrder = config.sortOrder
                browser.displayName = config.displayName
            }
        } else {
            browsers = detected
        }

        // Detect profiles for each browser and restore saved hotkeys
        let savedConfigMap = savedConfigs.map {
            Dictionary($0.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        for i in browsers.indices {
            Self.applyProfiles(
                profileDetector.detectProfiles(for: browsers[i]),
                savedConfig: savedConfigMap?[browsers[i].id],
                to: &browsers[i]
            )
        }

        // Refreshes also run in the background; leave state and disk alone when nothing changed.
        guard browsers != state.browsers else { return }
        state.browsers = browsers
        if canPersist {
            save(browsers)
        }
    }

    /// Sets the browser's profiles from a detection result and restores their saved hotkeys and
    /// visibility. When macOS denied access, the last saved profile list stands in.
    static func applyProfiles(
        _ detection: ProfileDetection,
        savedConfig: BrowserConfig?,
        to browser: inout InstalledBrowser
    ) {
        browser.profilesAccessDenied = detection.accessDenied
        browser.profiles = detection.accessDenied ? (savedConfig?.profiles ?? []) : detection.profiles

        guard let savedConfig else { return }
        for j in browser.profiles.indices {
            let dirName = browser.profiles[j].directoryName
            if let key = savedConfig.profileHotkeys?[dirName] {
                browser.profiles[j].hotkey = key.first
                browser.profiles[j].hotkeyKeyCode =
                    savedConfig.profileHotkeyKeyCodes?[dirName] ?? key.first.flatMap { KeyCodeMap.keyCode(for: $0) }
            }
            if let visible = savedConfig.profileVisibility?[dirName] {
                browser.profiles[j].isVisible = visible
            }
        }
    }

    func save(_ browsers: [InstalledBrowser]) {
        configStorage.save(browsers)
    }
}
