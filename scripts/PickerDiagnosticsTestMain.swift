import XCTest

@main
enum PickerDiagnosticsTestMain {
    static func main() {
        let suite = PickerDiagnosticsTests.defaultTestSuite
        suite.run()
        exit(suite.testRun?.hasSucceeded == true && suite.testCaseCount > 0 ? 0 : 1)
    }
}
