import AppKit
import XCTest

final class PickerUserJourneysUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if app.state != .notRunning {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        }
        app = nil
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

    func testHoldPickerOpensAppWithNumberKey() {
        launch(scenario: "hold-picker")
        let firstApp = app.buttons["picker.item.app:ui.hold.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertEqual(firstApp.value as? String, "1")
        XCTAssertTrue(waitForAppCatToDeactivate())
        postRawKey(keyCode: 18)
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testHoldPickerOpensClickedApp() {
        launch(scenario: "hold-picker")
        let firstApp = app.buttons["picker.item.app:ui.hold.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        firstApp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testLinkPickerOpensClickedApp() {
        launch(scenario: "link-picker")
        let firstApp = app.buttons["picker.item.app:ui.link.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        firstApp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testLinkPickerOpensFromRawIconClickWhileAppStaysInactive() {
        launch(scenario: "link-picker")
        let firstApp = app.buttons["picker.item.app:ui.link.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForAppCatToDeactivate())

        let iconPoint = firstApp.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)
        ).screenPoint
        postRawClick(at: iconPoint)

        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
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
}
