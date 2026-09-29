import XCTest

@main
enum PickerDiagnosticsTestMain {
    static func main() {
        let suite = XCTestSuite(name: "Picker headless regressions")
        suite.addTest(PickerDiagnosticsTests.defaultTestSuite)
        suite.addTest(PickerMouseSelectionTests.defaultTestSuite)
        suite.run()
        exit(suite.testRun?.hasSucceeded == true && suite.testCaseCount > 0 ? 0 : 1)
    }
}
