#if DEBUG
    import AppKit
    import Foundation

    enum UITestRuntime {
        static var isEnabled: Bool {
            ProcessInfo.processInfo.environment["APPCAT_UI_TEST_SCENARIO"] != nil
        }
    }

    private enum UITestLaunchScenario: String {
        case servicePicker = "service-picker"
        case holdPicker = "hold-picker"
        case linkPicker = "link-picker"
        case mainWindow = "main-window"
    }

    extension AppDelegate {
        func configureUITestSessionIfRequested() -> Bool {
            guard let rawScenario = ProcessInfo.processInfo.environment["APPCAT_UI_TEST_SCENARIO"],
                  let scenario = UITestLaunchScenario(rawValue: rawScenario)
            else {
                return false
            }

            appState.appLanguage = .english
            appState.pickerScale = 1
            appState.selectWithNumberKeys = true

            switch scenario {
            case .servicePicker:
                configureServicePickerUITest()
            case .holdPicker:
                configureHoldPickerUITest()
            case .linkPicker:
                configureLinkPickerUITest()
            case .mainWindow:
                appState.mainWindowSection = .overview
                DispatchQueue.main.async { [weak self] in
                    self?.openMainWindow()
                }
            }

            return true
        }

        private func configureServicePickerUITest() {
            let apps = (0 ..< 12).map { index in
                makeUITestApp(
                    id: "ui.service.\(index)",
                    displayName: String(format: "UI App %02d", index + 1)
                )
            }
            let appIDs = Set(apps.map(\.id))

            appState.apps = apps
            appState.runningAppBundleIDs = appIDs
            appState.regularAppBundleIDs = appIDs
            appState.runningAppsByBundleID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
            appState.runningWindowsByAppID = [:]
            appState.appActivityUpdatedAt = Date()
            appState.appWindowActivityUpdatedAt = Date()
            appState.showWindowlessApps = true
            appState.showBackgroundApps = false
            appState.pickerInvocationSource = .serviceKey

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pickerCoordinator.showPicker(state: self.appState)
            }
        }

        private func configureHoldPickerUITest() {
            let apps = (0 ..< 12).map { index in
                makeUITestApp(
                    id: "ui.hold.\(index)",
                    displayName: String(format: "UI Hold App %02d", index + 1)
                )
            }
            let appIDs = Set(apps.map(\.id))

            appState.apps = apps
            appState.runningAppBundleIDs = appIDs
            appState.regularAppBundleIDs = appIDs
            appState.runningAppsByBundleID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
            appState.runningWindowsByAppID = [:]
            appState.appActivityUpdatedAt = Date()
            appState.appWindowActivityUpdatedAt = Date()
            appState.showWindowlessApps = true
            appState.showBackgroundApps = false
            appState.pickerInvocationSource = .holdOptionTab

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pickerCoordinator.showPicker(state: self.appState)
            }
        }

        private func configureLinkPickerUITest() {
            let apps = [
                makeUITestApp(id: "ui.link.0", displayName: "UI Link App 01", hostPatterns: ["ui-test.invalid"]),
                makeUITestApp(id: "ui.link.1", displayName: "UI Link App 02", hostPatterns: ["ui-test.invalid"]),
            ]
            let url = URL(string: "https://ui-test.invalid/example")!

            appState.apps = apps
            appState.pickerInvocationSource = .linkRouting
            appState.setPendingOpen(displayURLs: [url], launchURLs: [url])

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pickerCoordinator.showPicker(state: self.appState)
            }
        }

        private func makeUITestApp(
            id: String,
            displayName: String,
            hostPatterns: [String] = []
        ) -> InstalledApp {
            InstalledApp(
                id: id,
                displayName: displayName,
                appURL: URL(fileURLWithPath: "/Applications/\(displayName).app"),
                urlSchemes: [],
                hostPatterns: hostPatterns,
                isVisible: true,
                sortOrder: 0,
                hotkey: nil,
                hotkeyKeyCode: nil
            )
        }
    }
#endif
