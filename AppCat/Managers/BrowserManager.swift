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
                current: state.browsers.first { $0.id == browsers[i].id },
                to: &browsers[i]
            )
        }

        // Refreshes also run in the background; leave state and disk alone when nothing changed.
        // The two are compared separately so a write that failed earlier is retried.
        if browsers != state.browsers {
            state.browsers = browsers
        }
        if canPersist, savedConfigs != browsers.map(BrowserConfig.init(from:)) {
            save(browsers)
        }
    }

    /// Sets the browser's profiles from a detection result and restores their saved hotkeys and
    /// visibility. When the list cannot be read, the last known one stands in: the saved snapshot,
    /// or the one on screen when the config itself could not be loaded.
    static func applyProfiles(
        _ detection: ProfileDetection,
        savedConfig: BrowserConfig?,
        current: InstalledBrowser? = nil,
        to browser: inout InstalledBrowser
    ) {
        browser.profilesReadFailure = detection.failure
        guard detection.failure != nil else {
            browser.profiles = detection.profiles
            restoreProfileSettings(from: savedConfig, to: &browser)
            return
        }
        guard let savedConfig else {
            browser.profiles = current?.profiles ?? []
            browser.pendingProfileSettings = current?.pendingProfileSettings
            return
        }
        browser.profiles = savedConfig.profiles ?? []
        if browser.profiles.isEmpty {
            browser.pendingProfileSettings = PendingProfileSettings(savedConfig)
        }
        restoreProfileSettings(from: savedConfig, to: &browser)
    }

    private static func restoreProfileSettings(from savedConfig: BrowserConfig?, to browser: inout InstalledBrowser) {
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
