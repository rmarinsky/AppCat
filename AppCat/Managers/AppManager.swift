import Foundation
import os

@MainActor
final class AppManager {
    private let appDetector = AppDetector()

    func refreshApps(into state: AppState) {
        let browserIDs = Set(state.browsers.map(\.id))
        let detected = appDetector.detectAllApps().filter { !browserIDs.contains($0.id) }
        applyDetected(detected, into: state)
    }

    /// Full installed-app rescan with the expensive detection (directory walk, Info.plist
    /// parsing, icon loads) off the main actor. Merge + publish + save hop back to main.
    /// Used by workspace-notification triggers so the switcher hotkey never pays for a rescan.
    func refreshAppsInBackground(into state: AppState) {
        let browserIDs = Set(state.browsers.map(\.id))
        let detector = appDetector
        Task.detached(priority: .utility) { [weak self] in
            let detected = detector.detectAllApps().filter { !browserIDs.contains($0.id) }
            await MainActor.run { [weak self] in
                self?.applyDetected(detected, into: state)
            }
        }
    }

    private func applyDetected(_ detected: [InstalledApp], into state: AppState) {
        let savedConfigs = AppConfigStorage.shared.load()

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
                app.opensUnknownTypes = config.opensUnknownTypes ?? false
            }
        } else {
            state.apps = detected
        }

        save(state.apps)
    }

    func save(_ apps: [InstalledApp]) {
        AppConfigStorage.shared.save(apps)
    }
}
