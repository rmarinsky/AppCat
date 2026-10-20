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
        // An obsolete callback must not release another session's current gesture.
        guard session == press.session else { return .passThrough }
        // Physical down/up pairs can share an event number (observed on macOS 27).
        // Reject older releases, but do not leave an equal-numbered click pending.
        guard eventNumber >= press.eventNumber else { return .passThrough }
        self.press = nil
        guard item == press.item else { return .cancel }
        return .select(press.item)
    }

    mutating func cancel() {
        press = nil
    }
}
