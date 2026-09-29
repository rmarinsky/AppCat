#if DEBUG
#if canImport(AppCat)
@testable import AppCat
#endif
import Foundation
import XCTest

final class PickerDiagnosticsTests: XCTestCase {
    @objc func testStalledPresentationAndLostActivePanelAreReported() {
        var journal = PickerDiagnosticJournal()
        var state = PickerDiagnosticSnapshot()
        state.observedSession = UUID()
        state.activeSession = state.observedSession
        state.sessionActive = true
        state.pending = true
        XCTAssertNil(journal.anomaly(in: state, at: 0))
        XCTAssertEqual(journal.anomaly(in: state, at: 4), "presentation_stalled")
        state.pending = false
        state.stateVisible = true
        XCTAssertNil(journal.anomaly(in: state, at: 5))
        XCTAssertEqual(journal.anomaly(in: state, at: 7), "active_panel_hidden")
    }

    @objc func testTransientUnknownAndStaleSamplesDoNotReportGhosts() {
        var journal = PickerDiagnosticJournal()
        var state = PickerDiagnosticSnapshot()
        state.observedSession = UUID()
        state.serverVisible = true
        XCTAssertNil(journal.anomaly(in: state, at: 0))
        state.serverVisible = nil
        XCTAssertNil(journal.anomaly(in: state, at: 1))
        state.serverVisible = true
        XCTAssertNil(journal.anomaly(in: state, at: 2))
        state.activeSession = UUID()
        XCTAssertNil(journal.anomaly(in: state, at: 5))
        state.activeSession = state.observedSession
        state.sessionActive = true
        state.panelVisible = true
        state.stateVisible = true
        XCTAssertNil(journal.anomaly(in: state, at: 8))
    }

    @objc func testJournalRetainsBoundedOrderedEventsAndSessionAttribution() {
        var journal = PickerDiagnosticJournal(capacity: 2)
        let session = UUID()
        let gesture = UUID()
        journal.append("down", session: session, gesture: gesture, at: 1)
        journal.append("close", session: session, gesture: gesture, at: 2)
        journal.append("up", session: session, gesture: gesture, at: 3)
        XCTAssertEqual(journal.events.map(\.name), ["close", "up"])
        XCTAssertEqual(journal.events.map(\.sequence), [2, 3])
        XCTAssertTrue(journal.events.allSatisfy { $0.session == session && $0.gesture == gesture })
    }

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
