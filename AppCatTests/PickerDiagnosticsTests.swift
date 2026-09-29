#if DEBUG
#if canImport(AppCat)
@testable import AppCat
#endif
import Foundation
import XCTest

final class PickerDiagnosticsTests: XCTestCase {
    @objc func testClosedSessionReturningOnscreenProducesOneIncidentAfterSettling() {
        var journal = PickerDiagnosticJournal()
        var state = PickerDiagnosticSnapshot()
        state.window = 6500
        state.observedSession = UUID()
        state.serverVisible = true
        // A single asynchronous WindowServer observation is not yet a persistent failure.
        XCTAssertNil(journal.anomaly(in: state, at: 10))
        XCTAssertNil(journal.anomaly(in: state, at: 10.1))
        XCTAssertEqual(journal.anomaly(in: state, at: 10.5), "closed_panel_visible")
        XCTAssertNil(journal.anomaly(in: state, at: 11))
    }
}
#endif
