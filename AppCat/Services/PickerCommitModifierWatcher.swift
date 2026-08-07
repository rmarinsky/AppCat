import AppKit
import KeyboardShortcuts

enum PickerCommitModifierPolicy {
    /// Modifiers that can plausibly be *held* across a ⌘Tab-style gesture. Caps Lock and the
    /// function key are excluded: they are toggles or chorded taps, not held during a switch.
    static let holdable: NSEvent.ModifierFlags = [.option, .command, .control, .shift]

    /// The modifiers whose release should commit the session, or nil when the shortcut has none to
    /// wait for (rebound to F13, or a bare key). In that case the picker stays a plain modal
    /// picker, committed with Return, a click, or a positional shortcut.
    static func watchedModifiers(for shortcut: KeyboardShortcuts.Shortcut?) -> NSEvent.ModifierFlags? {
        guard let shortcut else { return nil }
        let watched = shortcut.modifiers.intersection(holdable)
        return watched.isEmpty ? nil : watched
    }

    /// Commit as soon as *any* watched modifier is no longer held — letting go of ⌥ in ⌥⇧Tab ends
    /// the gesture just as it does for ⌘Tab.
    static func shouldCommit(watched: NSEvent.ModifierFlags, current: NSEvent.ModifierFlags) -> Bool {
        !watched.isEmpty && !watched.isSubset(of: current.intersection(holdable))
    }
}

/// Commits a manual switcher session when the activation chord's modifiers come back up — the
/// ⌘Tab gesture, where you hold ⌥, tap Tab to step, and release to switch.
///
/// This reads the live modifier state rather than observing key events. `NSEvent.modifierFlags` is
/// an ungated window-server query, so it behaves identically whether or not the user granted
/// Accessibility or Input Monitoring: a `CGEvent` tap would require Input Monitoring, and a global
/// `NSEvent` monitor would require Accessibility and would fail *silently* if it were revoked,
/// leaving the picker stuck open with no diagnostic.
@MainActor
final class PickerCommitModifierWatcher {
    struct Dependencies {
        var currentModifiers: @MainActor () -> NSEvent.ModifierFlags
        var sleep: @Sendable (UInt64) async -> Void

        static let live = Dependencies(
            currentModifiers: { NSEvent.modifierFlags },
            sleep: { try? await Task.sleep(nanoseconds: $0) }
        )
    }

    /// Fires once, on the main actor, when the watched modifiers are released.
    var onCommit: (@MainActor () -> Void)?
    /// Polled each tick; a false answer disarms. This covers every dismissal path — Escape,
    /// click-away, resign-key, a positional selection — without threading a hook through each.
    var isSessionAlive: (@MainActor () -> Bool)?

    private let dependencies: Dependencies
    private let pollInterval: UInt64
    private let maximumDuration: UInt64
    private var pollTask: Task<Void, Never>?

    init(
        dependencies: Dependencies = .live,
        pollInterval: UInt64 = 25_000_000,
        maximumDuration: UInt64 = 30_000_000_000
    ) {
        self.dependencies = dependencies
        self.pollInterval = max(1, pollInterval)
        self.maximumDuration = maximumDuration
    }

    var isArmed: Bool { pollTask != nil }

    /// Starts watching. Called at the *hotkey* frame rather than when the panel appears: a toggle
    /// session waits on an off-main window enumeration first, and the user can easily release ⌥
    /// before that lands. Arming early means the release is still observed, and the session commits
    /// as soon as it exists.
    func arm(watching modifiers: NSEvent.ModifierFlags) {
        disarm()
        guard !modifiers.isEmpty else { return }
        let dependencies = self.dependencies
        let pollInterval = self.pollInterval
        let maximumTicks = max(1, Int(maximumDuration / self.pollInterval))
        pollTask = Task { @MainActor [weak self] in
            for _ in 0 ..< maximumTicks {
                await dependencies.sleep(pollInterval)
                guard let self, !Task.isCancelled else { return }
                if let isSessionAlive = self.isSessionAlive, !isSessionAlive() {
                    self.pollTask = nil
                    return
                }
                guard PickerCommitModifierPolicy.shouldCommit(
                    watched: modifiers,
                    current: dependencies.currentModifiers()
                ) else { continue }
                self.pollTask = nil
                self.onCommit?()
                return
            }
            self?.pollTask = nil
        }
    }

    func disarm() {
        pollTask?.cancel()
        pollTask = nil
    }
}
