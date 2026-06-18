import AppKit

/// Why the handoff overlay is showing. Drives the caption so the user can tell
/// whether *they* chose the destination or whether AppCat's rule did.
enum HandoffReason {
    /// The user picked the destination in the picker (click / Return / hotkey / number key).
    case userPicked
    /// A URL rule matched in AppDelegate and routed automatically — no picker was shown.
    case ruleMatched

    init(source: OpenSource) {
        if case .autoRoute = source {
            self = .ruleMatched
        } else {
            self = .userPicked
        }
    }
}

/// Everything the Cat Pounce handoff overlay needs to render a single "AppCat is
/// taking you to <app>" moment. Built fresh per open and thrown away when the overlay closes.
struct HandoffPresentation {
    let icon: NSImage?
    let destinationName: String
    let reason: HandoffReason
}
