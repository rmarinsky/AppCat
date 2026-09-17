#if DEBUG
    import AppKit
    import Foundation

    enum UITestRuntime {
        static var skipsExternalLaunch: Bool {
            guard let scenario = ProcessInfo.processInfo.environment["APPCAT_UI_TEST_SCENARIO"] else {
                return false
            }
            switch scenario {
            case "routing-receiver", "manual-receiver":
                return false
            default:
                return true
            }
        }
    }

    private enum UITestLaunchScenario: String {
        case servicePicker = "service-picker"
        case holdPicker = "hold-picker"
        case linkPicker = "link-picker"
        case filePicker = "file-picker"
        case routingReceiver = "routing-receiver"
        case manualReceiver = "manual-receiver"
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
            case .filePicker:
                configureFilePickerUITest()
            case .routingReceiver:
                configureRoutingReceiverUITest()
            case .manualReceiver:
                configureManualReceiverUITest()
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

        private func configureFilePickerUITest() {
            var app = makeUITestApp(id: "ui.file.0", displayName: "UI File App 01")
            app.customFormats = ["romanuitest"]
            let url = URL(fileURLWithPath: "/tmp/example.romanuitest")

            appState.apps = [app]
            appState.pickerInvocationSource = .linkRouting
            appState.setPendingOpen(displayURLs: [url], launchURLs: [url])

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pickerCoordinator.showPicker(state: self.appState)
            }
        }

        private func configureRoutingReceiverUITest() {
            guard var receiver = makeUITestReceiver(),
                  let routedURLString = ProcessInfo.processInfo.environment["APPCAT_UI_TEST_ROUTED_URL"],
                  let routedURL = URL(string: routedURLString)
            else { return }
            receiver.customFormats = ["romanuitest"]
            appState.apps = [receiver]
            appState.pickerInvocationSource = .linkRouting
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.async { [weak self] in
                self?.completeLaunchConfigurationForUITest(routing: [routedURL])
                NSApp.deactivate()
            }
        }

        private func configureManualReceiverUITest() {
            guard let receiver = makeUITestReceiver() else { return }

            appState.apps = [receiver]
            appState.runningAppBundleIDs = [receiver.id]
            appState.regularAppBundleIDs = [receiver.id]
            appState.runningAppsByBundleID = [receiver.id: receiver]
            appState.runningWindowsByAppID = [:]
            appState.appActivityUpdatedAt = Date()
            appState.appWindowActivityUpdatedAt = Date()
            appState.showWindowlessApps = true
            appState.showBackgroundApps = false
            appState.pickerInvocationSource = .serviceKey
            completeLaunchConfigurationForUITest()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pickerCoordinator.showPicker(state: self.appState)
            }
        }

        private func makeUITestReceiver() -> InstalledApp? {
            guard let receiverPath = ProcessInfo.processInfo.environment["APPCAT_UI_TEST_RECEIVER_PATH"]
            else { return nil }

            return makeUITestApp(
                id: "ua.com.rmarinsky.appcat.uitest-receiver",
                displayName: "AppCat UI Test Receiver",
                appURL: URL(fileURLWithPath: receiverPath),
                hostPatterns: ["ui-test.invalid"]
            )
        }

        private func makeUITestApp(
            id: String,
            displayName: String,
            appURL: URL? = nil,
            hostPatterns: [String] = []
        ) -> InstalledApp {
            InstalledApp(
                id: id,
                displayName: displayName,
                appURL: appURL ?? URL(fileURLWithPath: "/Applications/\(displayName).app"),
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
