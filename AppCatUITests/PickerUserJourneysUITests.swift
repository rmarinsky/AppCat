import AppKit
import XCTest

final class PickerUserJourneysUITests: XCTestCase {
    private struct ReceiverConfiguration: Encodable {
        let statePath: String
        let routerAppPath: String
        let routedURLString: String
    }

    private struct ReceiverState: Decodable {
        let isReady: Bool
        let mouseDownCount: Int
        let openRequestCount: Int
        let activationCount: Int
    }

    private var app: XCUIApplication!
    private var receiverApplication: NSRunningApplication?
    private var receiverStateURL: URL?
    private var receiverConfigurationURL: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        terminateReceiverApplications()
        XCTAssertTrue(
            waitForReceiverApplicationsToTerminate(),
            "A stale receiver application remained alive before the test"
        )
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if app.state != .notRunning {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        }
        app = nil
        receiverApplication?.terminate()
        XCTAssertTrue(
            waitForReceiverApplicationsToTerminate(),
            "The receiver application did not terminate during cleanup"
        )
        receiverApplication = nil
        if let receiverStateURL {
            try? FileManager.default.removeItem(at: receiverStateURL)
        }
        receiverStateURL = nil
        if let receiverConfigurationURL {
            try? FileManager.default.removeItem(at: receiverConfigurationURL)
        }
        receiverConfigurationURL = nil
    }

    func testServiceKeyPickerOpensClickedApp() {
        launch(scenario: "service-picker")
        let firstApp = app.buttons["picker.item.app:ui.service.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawClick(at: firstApp.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)
        ).screenPoint)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testServiceKeyPickerOpensAppWithNumberKey() {
        launch(scenario: "service-picker")
        let firstApp = app.buttons["picker.item.app:ui.service.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertEqual(firstApp.value as? String, "1")
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawKey(keyCode: 18)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testHoldPickerIgnoresNumberKeyWithoutTakingFocus() {
        launch(scenario: "hold-picker")
        let firstApp = app.buttons["picker.item.app:ui.hold.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertEqual(firstApp.value as? String, "1")
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawKey(keyCode: 18)
        XCTAssertFalse(firstApp.waitForNonExistence(timeout: 1))
    }

    func testHoldPickerOpensClickedApp() {
        launch(scenario: "hold-picker")
        let firstApp = app.buttons["picker.item.app:ui.hold.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawClick(at: firstApp.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)
        ).screenPoint)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testLinkPickerOpensClickedApp() {
        launch(scenario: "link-picker")
        let firstApp = app.buttons["picker.item.app:ui.link.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        firstApp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testLinkPickerConsumesRawClickWithoutReopening() throws {
        let routedURL = try XCTUnwrap(URL(string: "https://ui-test.invalid/click-through"))
        try assertRoutingClickIsConsumed(routedURL: routedURL)
    }

    func testRepeatedSameURLStartsFreshRoutingSession() throws {
        let routedURL = try XCTUnwrap(URL(string: "https://ui-test.invalid/repeated-routing"))
        let setup = try launchRoutingReceiver(
            routedURL: routedURL,
            scenario: "repeated-routing-receiver",
            tileID: "picker.item.app:ui.receiver.edge"
        )
        let edgeTile = setup.receiverTile

        XCTAssertTrue(edgeTile.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawClick(at: edgeTile.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)
        ).screenPoint)
        XCTAssertTrue(edgeTile.waitForNonExistence(timeout: 2))
        XCTAssertTrue(waitForReceiverState(at: setup.stateURL) { $0.openRequestCount == 1 })

        try openWithAppCat(routedURL, appURL: setup.paths.appCat)

        let chromeTile = app.buttons["picker.item.app:ui.receiver.chrome"]
        XCTAssertTrue(chromeTile.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawClick(at: chromeTile.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)
        ).screenPoint)
        XCTAssertTrue(chromeTile.waitForNonExistence(timeout: 2))
        XCTAssertTrue(staysAbsent(chromeTile, duration: 1))
        XCTAssertTrue(waitForReceiverState(at: setup.stateURL) { $0.openRequestCount == 2 })

        let receiverState = try readReceiverState(at: setup.stateURL)
        XCTAssertEqual(receiverState.mouseDownCount, 0)
        XCTAssertEqual(receiverState.openRequestCount, 2)
    }

    func testIncomingURLCancelsPendingManualModifierCommit() throws {
        let routedURL = try XCTUnwrap(URL(string: "https://ui-test.invalid/manual-to-routing"))
        let setup = try launchRoutingReceiver(
            routedURL: routedURL,
            scenario: "pending-manual-routing-receiver"
        )
        let receiverTile = setup.receiverTile

        XCTAssertTrue(receiverTile.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        XCTAssertTrue(receiverTile.exists, "The old modifier watcher committed the new link picker")
        XCTAssertEqual(try readReceiverState(at: setup.stateURL).openRequestCount, 0)

        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawClick(at: receiverTile.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)
        ).screenPoint)
        XCTAssertTrue(receiverTile.waitForNonExistence(timeout: 2))
        XCTAssertTrue(staysAbsent(receiverTile, duration: 1))
        XCTAssertTrue(waitForReceiverState(at: setup.stateURL) { $0.openRequestCount == 1 })
    }

    func testManualPickerConsumesRawClickWithoutReopening() throws {
        let routedURL = try XCTUnwrap(URL(string: "https://ui-test.invalid/manual-click-through"))
        let paths = try testApplicationPaths()
        let receiverStateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appcat-ui-receiver-\(UUID().uuidString).json")
        self.receiverStateURL = receiverStateURL
        receiverApplication = try launchReceiver(
            at: paths.receiver,
            routerAppURL: paths.appCat,
            routedURL: routedURL,
            stateURL: receiverStateURL
        )
        XCTAssertTrue(waitForReceiverState(at: receiverStateURL) { $0.isReady })
        let activationCountBeforeSelection = try readReceiverState(at: receiverStateURL).activationCount

        app.launchEnvironment["APPCAT_UI_TEST_SCENARIO"] = "manual-receiver"
        app.launchEnvironment["APPCAT_UI_TEST_RECEIVER_PATH"] = paths.receiver.path
        app.launch()

        let receiverTile = app.buttons[
            "picker.item.app:ua.com.rmarinsky.appcat.uitest-receiver"
        ]
        XCTAssertTrue(receiverTile.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())

        postRawClick(at: receiverTile.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)
        ).screenPoint)

        XCTAssertTrue(receiverTile.waitForNonExistence(timeout: 2))
        XCTAssertTrue(staysAbsent(receiverTile, duration: 1))
        XCTAssertTrue(waitForReceiverState(at: receiverStateURL) {
            $0.activationCount == activationCountBeforeSelection + 1
        })
        let receiverState = try readReceiverState(at: receiverStateURL)
        XCTAssertEqual(receiverState.activationCount, activationCountBeforeSelection + 1)
        XCTAssertEqual(receiverState.mouseDownCount, 0, "Picker click leaked to the app underneath")
        XCTAssertEqual(receiverState.openRequestCount, 0, "Manual selection must not create a routing request")
    }

    func testFilePickerConsumesRawClickWithoutReopening() throws {
        let routedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appcat-ui-test-\(UUID().uuidString).romanuitest")
        try Data("AppCat UI test".utf8).write(to: routedURL)
        defer { try? FileManager.default.removeItem(at: routedURL) }

        try assertRoutingClickIsConsumed(routedURL: routedURL)
    }

    private func assertRoutingClickIsConsumed(routedURL: URL) throws {
        let setup = try launchRoutingReceiver(routedURL: routedURL, scenario: "routing-receiver")
        let receiverTile = setup.receiverTile

        XCTAssertTrue(receiverTile.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())

        postRawClick(at: receiverTile.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)
        ).screenPoint)

        XCTAssertTrue(receiverTile.waitForNonExistence(timeout: 2))
        XCTAssertTrue(staysAbsent(receiverTile, duration: 1))
        XCTAssertTrue(waitForReceiverState(at: setup.stateURL) { $0.openRequestCount >= 1 })
        let receiverState = try readReceiverState(at: setup.stateURL)
        XCTAssertEqual(receiverState.mouseDownCount, 0, "Picker click leaked to the app underneath")
        XCTAssertEqual(receiverState.openRequestCount, 1, "One picker selection must produce one open request")
    }

    private func launchRoutingReceiver(
        routedURL: URL,
        scenario: String,
        tileID: String = "picker.item.app:ua.com.rmarinsky.appcat.uitest-receiver"
    ) throws -> (paths: (appCat: URL, receiver: URL), stateURL: URL, receiverTile: XCUIElement) {
        let paths = try testApplicationPaths()
        let receiverStateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appcat-ui-receiver-\(UUID().uuidString).json")
        self.receiverStateURL = receiverStateURL
        receiverApplication = try launchReceiver(
            at: paths.receiver,
            routerAppURL: paths.appCat,
            routedURL: routedURL,
            stateURL: receiverStateURL
        )
        XCTAssertTrue(waitForReceiverState(at: receiverStateURL) { $0.isReady })

        app.launchEnvironment["APPCAT_UI_TEST_SCENARIO"] = scenario
        app.launchEnvironment["APPCAT_UI_TEST_RECEIVER_PATH"] = paths.receiver.path
        app.launchEnvironment["APPCAT_UI_TEST_ROUTED_URL"] = routedURL.absoluteString
        app.launch()

        let receiverTile = app.buttons[tileID]
        return (paths, receiverStateURL, receiverTile)
    }

    func testFilePickerOpensFromRawIconClickWhileAppStaysInactive() {
        launch(scenario: "file-picker")
        let firstApp = app.buttons["picker.item.app:ui.file.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())

        let iconPoint = firstApp.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)
        ).screenPoint
        postRawClick(at: iconPoint)

        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testLinkPickerOpensAppWithNumberKey() {
        launch(scenario: "link-picker")
        let firstApp = app.buttons["picker.item.app:ui.link.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertEqual(firstApp.value as? String, "1")
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawKey(keyCode: 18)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testPickerOpensFocusedAppWithReturn() {
        launch(scenario: "service-picker")
        let firstApp = app.buttons["picker.item.app:ui.service.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawKey(keyCode: 36)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testPickerOpensFocusedAppWithSpace() {
        launch(scenario: "service-picker")
        let firstApp = app.buttons["picker.item.app:ui.service.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawKey(keyCode: 49)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testLinkPickerOpensFocusedAppWithReturn() {
        launch(scenario: "link-picker")
        let firstApp = app.buttons["picker.item.app:ui.link.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawKey(keyCode: 36)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testFilePickerOpensFocusedAppWithSpace() {
        launch(scenario: "file-picker")
        let firstApp = app.buttons["picker.item.app:ui.file.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawKey(keyCode: 49)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testPickerDismissesWithEscape() {
        launch(scenario: "link-picker")
        let firstApp = app.buttons["picker.item.app:ui.link.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawKey(keyCode: 53)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testUserCanOpenEveryMainWindowSection() {
        launch(scenario: "main-window")
        let sections = [
            "overview",
            "history",
            "suggestions",
            "settingsGeneral",
            "settingsPicker",
            "settingsBrowsers",
            "settingsApps",
            "settingsRules",
            "settingsShortcuts",
            "settingsAccount",
        ]

        XCTAssertTrue(app.windows["AppCat"].waitForExistence(timeout: 5))
        for section in sections {
            let navigationItem = app.buttons["sidebar.\(section)"]
            XCTAssertTrue(navigationItem.waitForExistence(timeout: 2), section)
            navigationItem.click()
            XCTAssertTrue(app.descendants(matching: .any)["main.section.\(section)"].waitForExistence(timeout: 2), section)
        }
    }

    private func launch(scenario: String) {
        app.launchEnvironment["APPCAT_UI_TEST_SCENARIO"] = scenario
        app.launch()
    }

    private func testApplicationPaths() throws -> (appCat: URL, receiver: URL) {
        var productsDirectory = Bundle(for: Self.self).bundleURL
        for _ in 0 ..< 4 {
            productsDirectory.deleteLastPathComponent()
        }
        let appCat = productsDirectory.appendingPathComponent("AppCat DEV.app")
        let receiver = productsDirectory.appendingPathComponent("AppCat UI Test Receiver.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appCat.path), appCat.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiver.path), receiver.path)
        return (appCat, receiver)
    }

    private func launchReceiver(
        at receiverURL: URL,
        routerAppURL: URL,
        routedURL: URL,
        stateURL: URL
    ) throws -> NSRunningApplication {
        let receiverConfigurationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("appcat-ui-receiver-\(UUID().uuidString).json")
        let receiverConfiguration = ReceiverConfiguration(
            statePath: stateURL.path,
            routerAppPath: routerAppURL.path,
            routedURLString: routedURL.absoluteString
        )
        try JSONEncoder().encode(receiverConfiguration).write(to: receiverConfigurationURL)
        self.receiverConfigurationURL = receiverConfigurationURL

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        let launched = expectation(description: "receiver launched")
        var result: NSRunningApplication?
        var launchError: Error?
        NSWorkspace.shared.open(
            [receiverConfigurationURL],
            withApplicationAt: receiverURL,
            configuration: configuration
        ) { application, error in
            result = application
            launchError = error
            launched.fulfill()
        }
        wait(for: [launched], timeout: 5)
        if let launchError { throw launchError }
        return try XCTUnwrap(result)
    }

    private func openWithAppCat(_ url: URL, appURL: URL) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let opened = expectation(description: "URL delivered to AppCat")
        var openError: Error?
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration) { _, error in
            openError = error
            opened.fulfill()
        }
        wait(for: [opened], timeout: 5)
        if let openError { throw openError }
    }

    private func waitForReceiverState(
        at url: URL,
        timeout: TimeInterval = 5,
        predicate: @escaping (ReceiverState) -> Bool
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let state = try? self.readReceiverState(at: url) else { return false }
            return predicate(state)
        }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func readReceiverState(at url: URL) throws -> ReceiverState {
        try JSONDecoder().decode(ReceiverState.self, from: Data(contentsOf: url))
    }

    private func staysAbsent(_ element: XCUIElement, duration: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            if element.exists { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return true
    }

    private func waitForAppCatToDeactivate() -> Bool {
        let predicate = NSPredicate { _, _ in
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "ua.com.rmarinsky.appcat.dev"
            ).first?.isActive == false
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }

    private func postRawClick(at point: CGPoint) {
        CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
        CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    private func postRawKey(keyCode: CGKeyCode) {
        CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: true
        )?.post(tap: .cghidEventTap)
        CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: false
        )?.post(tap: .cghidEventTap)
    }

    private func terminateReceiverApplications() {
        for application in NSRunningApplication.runningApplications(
            withBundleIdentifier: "ua.com.rmarinsky.appcat.uitest-receiver"
        ) {
            application.terminate()
        }
    }

    private func waitForReceiverApplicationsToTerminate() -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            NSRunningApplication.runningApplications(
                withBundleIdentifier: "ua.com.rmarinsky.appcat.uitest-receiver"
            ).isEmpty
        }, object: nil)
        return XCTWaiter.wait(for: [expectation], timeout: 2) == .completed
    }
}
