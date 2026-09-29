import AppKit
import XCTest

/// Load the test bundle without starting AppCatApp or its shortcut listeners.
@main
enum AppCatHeadlessTestMain {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count == 2,
              let bundle = Bundle(path: CommandLine.arguments[1]), bundle.load()
        else {
            fputs("Cannot load AppCat unit-test bundle\n", stderr)
            exit(1)
        }
        let suite = XCTestSuite.default
        suite.run()
        exit(suite.testCaseCount > 0 && suite.testRun?.hasSucceeded == true ? 0 : 1)
    }
}
