import Foundation
import os

@MainActor
final class AppManager {
    private let appDetector = AppDetector()

    func refreshApps(into state: AppState) {
        let browserIDs = Set(state.browsers.map(\.id))
        let detected = appDetector.detectAllApps().filter { !browserIDs.contains($0.id) }
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
