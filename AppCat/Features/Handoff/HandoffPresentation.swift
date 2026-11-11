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

/// How much of the handoff plays when a link or file opens. A user setting.
enum HandoffAnimationStyle: String, CaseIterable {
    /// The cat wakes up on its glass plate and flicks the icon to the app.
    case full
    /// No cat and no plate: the icon pops up at the cursor and flies to the app.
    case compact
}

/// Everything the Cat Pounce handoff overlay needs to render a single "AppCat is
/// taking you to <app>" moment. Built fresh per open and thrown away when the overlay closes.
struct HandoffPresentation {
    let icon: NSImage?
    let destinationName: String
    let reason: HandoffReason
    /// Bundle ID of the destination app, used to find where its window or Dock icon is.
    var bundleIdentifier: String?
}
