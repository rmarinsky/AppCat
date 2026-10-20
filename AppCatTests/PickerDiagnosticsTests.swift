#if DEBUG
    #if canImport(AppCat)
        @testable import AppCat
    #endif
    import Foundation
    import XCTest

    final class PickerDiagnosticsTests: XCTestCase {
        @objc func testDelayedChangedAndSparseSamplesDoNotProvePersistence() {
            var sample = PickerDiagnosticSnapshot()
            sample.observedSession = UUID()
            sample.serverVisible = true
            var current = sample
            current.serverVisible = nil
            var journal = PickerDiagnosticJournal()
            XCTAssertNil(journal.sampledAnomaly(in: sample, currentState: current, capturedAt: 0, queriedAt: 0.01, deliveredAt: 0.02))
            XCTAssertNil(journal.sampledAnomaly(in: sample, currentState: current, capturedAt: 0.05, queriedAt: 0.06, deliveredAt: 0.5))
            journal = PickerDiagnosticJournal()
            XCTAssertNil(journal.sampledAnomaly(in: sample, currentState: current, capturedAt: 0, queriedAt: 0.01, deliveredAt: 0.02))
            XCTAssertNil(journal.sampledAnomaly(in: sample, currentState: current, capturedAt: 2, queriedAt: 2.01, deliveredAt: 2.02))
            journal = PickerDiagnosticJournal()
            sample.sessionActive = true
            sample.pending = true
            current = sample
            current.serverVisible = nil
            XCTAssertNil(journal.sampledAnomaly(in: sample, currentState: current, capturedAt: 0, queriedAt: 0.01, deliveredAt: 0.02))
            current.pending = false
            current.panelVisible = true
            XCTAssertNil(journal.sampledAnomaly(in: sample, currentState: current, capturedAt: 4, queriedAt: 4.01, deliveredAt: 4.02))
        }

        @objc func testFreshContinuousSamplesProduceAnIncident() {
            var sample = PickerDiagnosticSnapshot()
            sample.observedSession = UUID()
            sample.serverVisible = true
            var current = sample
            current.serverVisible = nil
            var journal = PickerDiagnosticJournal()
            for time in [0.0, 0.1, 0.2] {
                XCTAssertNil(journal.sampledAnomaly(in: sample, currentState: current, capturedAt: time, queriedAt: time + 0.01, deliveredAt: time + 0.02))
            }
            XCTAssertEqual(journal.sampledAnomaly(in: sample, currentState: current, capturedAt: 0.35, queriedAt: 0.36, deliveredAt: 0.37), "closed_panel_visible")
        }

        @objc func testDiagnosticFilesContainReplayableMetadataAndBoundedIncidentSlots() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = PickerDiagnosticStore(directory: directory)
            var journal = PickerDiagnosticJournal()
            journal.append("mouse.up", detail: "event=25 option=true", context: .init(session: UUID()), at: 12)
            try store.write(journal.events)
            for _ in 0 ..< 15 {
                try store.write(journal.events, reason: "closed_panel_visible")
            }
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertEqual(files.filter { $0.hasPrefix("incident-") }.count, 12)
            let data = try Data(contentsOf: directory.appendingPathComponent("latest.json"))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let events = try XCTUnwrap(payload["events"] as? [[String: Any]])
            XCTAssertEqual(events.first?["name"] as? String, "mouse.up")
            XCTAssertEqual(events.first?["uptime"] as? Double, 12)
            XCTAssertNotNil(payload["runID"])
        }

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
            journal.context = .init(session: session, gesture: gesture)
            journal.append("down", at: 1)
            journal.append("close", at: 2)
            journal.append("up", at: 3)
            XCTAssertEqual(journal.events.map(\.name), ["close", "up"])
            XCTAssertEqual(journal.events.map(\.sequence), [2, 3])
            XCTAssertTrue(journal.events.allSatisfy { $0.session == session && $0.gesture == gesture })
        }

        @objc func testDelayedCompletionKeepsItsOriginalSessionAndGestureIncludingNoSession() {
            var journal = PickerDiagnosticJournal()
            let original = PickerDiagnosticContext(session: UUID(), gesture: UUID())
            journal.context = .init(session: UUID(), gesture: UUID())
            journal.append("launch.openResult", context: original, at: 1)
            journal.append("launch.openResult", context: .init(), at: 2)
            XCTAssertEqual(journal.events[0].session, original.session)
            XCTAssertEqual(journal.events[0].gesture, original.gesture)
            XCTAssertNil(journal.events[1].session)
            XCTAssertNil(journal.events[1].gesture)
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
