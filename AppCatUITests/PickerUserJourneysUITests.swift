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
        firstApp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testServiceKeyPickerOpensAppWithNumberKey() {
        launch(scenario: "service-picker")
        let firstApp = app.buttons["picker.item.app:ui.service.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertEqual(firstApp.value as? String, "1")
        app.typeKey("1", modifierFlags: [])
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testHoldPickerOpensAppWithNumberKey() {
        launch(scenario: "hold-picker")
        let firstApp = app.buttons["picker.item.app:ui.hold.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertEqual(firstApp.value as? String, "1")
        app.typeKey("1", modifierFlags: [])
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

    func testLinkPickerOpensAppWithNumberKey() {
        launch(scenario: "link-picker")
        let firstApp = app.buttons["picker.item.app:ui.link.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        XCTAssertEqual(firstApp.value as? String, "1")
        app.typeKey("1", modifierFlags: [])
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testPickerOpensFocusedAppWithReturn() {
        launch(scenario: "service-picker")
        let firstApp = app.buttons["picker.item.app:ui.service.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testPickerOpensFocusedAppWithSpace() {
        launch(scenario: "service-picker")
        let firstApp = app.buttons["picker.item.app:ui.service.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(firstApp.waitForNonExistence(timeout: 2))
    }

    func testPickerDismissesWithEscape() {
        launch(scenario: "link-picker")
        let firstApp = app.buttons["picker.item.app:ui.link.0"]

        XCTAssertTrue(firstApp.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
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
}
