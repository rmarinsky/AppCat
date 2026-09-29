#if DEV_BUILD
import Foundation

/// Allow-listed metadata only. Never add URLs, titles, bundle IDs, or keyboard text.
struct PickerDiagnosticSnapshot: Codable, Equatable {
    var window = 0
    var observedSession: UUID?
    var activeSession: UUID?
    var sessionActive = false
    var stateVisible = false
    var pending = false
    var closing = false
    var panelVisible = false
    var serverVisible: Bool?
    var panelKey = false
    var onActiveSpace = false
    var occlusionVisible = false
    var appActive = false
    var activationPolicy = 1
    var source = "none"
    var hasURL = false
    var itemCount = 0
    var focusedIndex = 0
    var renderedItems: [Int] = []
    var optionDown = false
}

struct PickerDiagnosticEvent: Codable {
    let sequence: Int
    let uptime: TimeInterval
    let date: Date
    let session: UUID?
    let gesture: UUID?
    let name: String
    let detail: String
    let state: PickerDiagnosticSnapshot?
}

struct PickerDiagnosticJournal {
    private(set) var events: [PickerDiagnosticEvent] = []
    private var sequence = 0
    private var scope = ""
    private var candidate: String?
    private var candidateSince: TimeInterval = 0
    private var reported: Set<String> = []
    let capacity: Int

    init(capacity: Int = 256) {
        self.capacity = max(1, min(capacity, 1024))
    }

    mutating func append(_ name: String, detail: String = "", session: UUID? = nil,
                         gesture: UUID? = nil, state: PickerDiagnosticSnapshot? = nil,
                         at uptime: TimeInterval, date: Date = Date()) {
        sequence += 1
        events.append(.init(sequence: sequence, uptime: uptime, date: date, session: session,
                            gesture: gesture, name: name, detail: String(detail.prefix(512)), state: state))
        if events.count > capacity { events.removeFirst(events.count - capacity) }
    }

    mutating func anomaly(in state: PickerDiagnosticSnapshot, at uptime: TimeInterval) -> String? {
        let newScope = "\(state.window):\(state.observedSession?.uuidString ?? "none")"
        if scope != newScope {
            scope = newScope
            candidate = nil
            reported = []
        }
        // A sample dispatched before replacement must not diagnose the replacement session.
        guard state.activeSession == nil || state.activeSession == state.observedSession else {
            candidate = nil
            return nil
        }
        let reason: String?
        let settling: TimeInterval
        if !state.sessionActive && (state.panelVisible || state.serverVisible == true) {
            reason = "closed_panel_visible"
            settling = 0.3
        } else if state.pending {
            reason = "presentation_stalled"
            settling = 3
        } else if state.sessionActive && state.stateVisible && !state.panelVisible {
            reason = "active_panel_hidden"
            settling = 1
        } else {
            reason = nil
            settling = 0.3
        }
        guard let reason else { candidate = nil; return nil }
        if candidate != reason { candidate = reason; candidateSince = uptime }
        guard uptime - candidateSince >= settling, reported.insert(reason).inserted else { return nil }
        return reason
    }
}

/// Used only from the diagnostic I/O queue. Fixed slots bound storage across app launches.
final class PickerDiagnosticStore {
    let directory: URL
    private let runID = UUID()
    private var incidentIndex = 0
    init(directory: URL) { self.directory = directory }

    func write(_ events: [PickerDiagnosticEvent], reason: String? = nil) throws {
        struct Envelope: Encodable {
            let formatVersion = 1
            let runID: UUID
            let pid: Int32
            let osVersion: String
            let reason: String?
            let events: [PickerDiagnosticEvent]
        }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Envelope(runID: runID, pid: ProcessInfo.processInfo.processIdentifier,
                                               osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                               reason: reason, events: Array(events.suffix(1024))))
        var names = ["latest.json"]
        if reason != nil {
            names.append(String(format: "incident-%02d.json", incidentIndex % 12))
            incidentIndex += 1
        }
        for name in names {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}
#endif
