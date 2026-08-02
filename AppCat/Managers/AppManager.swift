import Foundation
import os

@MainActor
final class AppManager {
    private let configStorage: AppConfigStorage
    private let detectApps: @Sendable () -> [InstalledApp]
    private var backgroundRefreshGeneration = 0

    init(
        configStorage: AppConfigStorage = .shared,
        detectApps: @escaping @Sendable () -> [InstalledApp] = { AppDetector().detectAllApps() }
    ) {
        self.configStorage = configStorage
        self.detectApps = detectApps
    }

    func refreshApps(into state: AppState) {
        let browserIDs = Set(state.browsers.map(\.id))
        let detected = detectApps().filter { !browserIDs.contains($0.id) }
        applyDetected(detected, into: state)
    }

    /// Full installed-app rescan with the expensive detection (directory walk, Info.plist
    /// parsing, icon loads) off the main actor. Merge + publish + save hop back to main.
    /// Used by workspace-notification triggers so the switcher hotkey never pays for a rescan.
    @discardableResult
    func refreshAppsInBackground(into state: AppState) -> Task<Void, Never> {
        backgroundRefreshGeneration += 1
        let generation = backgroundRefreshGeneration
        let browserIDs = Set(state.browsers.map(\.id))
        let detectApps = detectApps
        return Task.detached(priority: .utility) { [weak self] in
            let detected = detectApps().filter { !browserIDs.contains($0.id) }
            await MainActor.run { [weak self] in
                guard let self, self.backgroundRefreshGeneration == generation else { return }
                self.applyDetected(detected, into: state)
            }
        }
    }

    private func applyDetected(_ detected: [InstalledApp], into state: AppState) {
        let savedConfigs: [AppConfig]?
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

        if let savedConfigs {
            state.apps = mergeDetectedWithSaved(
                detected: detected,
                saved: savedConfigs,
                configID: \.id,
                sortOrder: \.sortOrder
            ) { app, config in
                app.isVisible = config.isVisible
                app.hotkey = config.hotkey?.first
                app.hotkeyKeyCode = config.hotkeyKeyCode ?? config.hotkey?.first.flatMap { KeyCodeMap.keyCode(for: $0) }
                app.sortOrder = config.sortOrder
                app.displayName = config.displayName
                app.customFormats = config.customFormats
                app.handlesAllFiles = AppFileCapabilityPolicy.resolveHandlesAllFiles(
                    savedValue: config.handlesAllFiles,
                    registryDefault: AppDefinition.registryByID[app.id]?.handlesAllFiles == true
                )
            }
        } else {
            state.apps = detected
        }

        if canPersist {
            save(state.apps)
        }
    }

    func save(_ apps: [InstalledApp]) {
        configStorage.save(apps)
    }
}
