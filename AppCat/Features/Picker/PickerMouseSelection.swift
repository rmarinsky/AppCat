import Foundation

/// Owns a single local mouse gesture. Global observations can cancel it, never select.
struct PickerMouseSelection {
    enum Action: Equatable {
        case passThrough
        case consume
        case cancel
        case select(String)
    }

    private struct Press {
        let session: UUID
        let item: String
        let eventNumber: Int
    }

    private var press: Press?
    var isTracking: Bool {
        press != nil
    }

    var allowsModifierCommit: Bool {
        !isTracking
    }

    mutating func mouseDown(session: UUID?, item: String?, eventNumber: Int) -> Action {
        guard let session, let item else { return .passThrough }
        press = Press(session: session, item: item, eventNumber: eventNumber)
        return .consume
    }

    mutating func mouseUp(session: UUID?, item: String?, eventNumber: Int) -> Action {
        guard let press else { return .passThrough }
        // AppKit increments this counter for each mouse/tracking event. The matching release
        // therefore has a later number than the press; an older delayed release must not cancel
        // a newer gesture.
        guard eventNumber > press.eventNumber else { return .passThrough }
        self.press = nil
        guard session == press.session else { return .consume }
        guard item == press.item else { return .cancel }
        return .select(press.item)
    }

    mutating func cancel() {
        press = nil
    }
}
