import AppKit
import ApplicationServices

/// Namespaced identities for the switcher's most-recently-used order.
///
/// Window keys fold exactly like `PickerItem.switcherDedupeKey` so a ledger entry and a rendered
/// tile agree on identity. `AppWindowTarget.index` is a per-enumeration-pass position, not a
/// stable identity, so it deliberately plays no part in a key.
enum WindowActivationKey {
    static func app(_ bundleID: String) -> String {
        "app|\(bundleID)"
    }

    static func window(bundleID: String, title: String) -> String {
        "window-title|\(bundleID)|\(folded(title))"
    }

    static func folded(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    /// The app a key belongs to, whichever namespace it is in. Bundle identifiers cannot contain
    /// `|`, so splitting on it is unambiguous.
    static func bundleID(from key: String) -> String? {
        let parts = key.split(separator: "|", omittingEmptySubsequences: false)
        switch parts.first {
        case "app" where parts.count >= 2:
            return String(parts[1])
        case "window-title" where parts.count >= 3:
            return String(parts[1])
        default:
            return nil
        }
    }
}

/// Where a switcher tile sits in the most-recently-used order. Two components so a tile whose
/// window title was actually resolved outranks its siblings, which only inherit the app-level tick.
struct WindowActivationRank: Comparable, Equatable {
    let tick: Int
    let isExactWindow: Bool

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
        return !lhs.isExactWindow && rhs.isExactWindow
    }
}

/// Flat, window-level most-recently-used order for the app switcher.
///
/// Recency is a monotonic tick rather than a `Date`: deterministic under test, immune to clock
/// changes, and cheap to compare. A higher tick means more recently frontmost.
///
/// Ranks never *create* switcher candidates — candidates come from live enumeration only — so a
/// key left behind by a closed window is inert, exactly like a stale `manualPickerTargetCounts`
/// entry.
struct WindowActivationLedger: Equatable {
    private(set) var ticksByKey: [String: Int] = [:]
    private(set) var nextTick: Int = 0
    let capacity: Int
    private let trimTarget: Int

    init(capacity: Int = 250, trimTarget: Int = 200) {
        self.capacity = max(1, capacity)
        self.trimTarget = min(max(1, trimTarget), max(1, capacity))
    }

    /// Records that `bundleID` became frontmost and returns the tick it was given, so an
    /// asynchronously resolved window title can attach to *this* activation rather than jumping
    /// ahead of activations that happened while the resolution was in flight.
    @discardableResult
    mutating func recordActivation(bundleID: String) -> Int {
        let tick = nextTick
        nextTick += 1
        ticksByKey[WindowActivationKey.app(bundleID)] = tick
        trimIfNeeded()
        return tick
    }

    /// Attaches the window that was focused during the activation which was given `tick`.
    /// Never lowers an existing rank: a late resolution for an older activation must not demote a
    /// window the user has since returned to.
    mutating func attachFocusedWindow(bundleID: String, title: String, tick: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = WindowActivationKey.window(bundleID: bundleID, title: trimmed)
        guard tick > (ticksByKey[key] ?? Int.min) else { return }
        ticksByKey[key] = tick
        trimIfNeeded()
    }

    /// Seeds the order at launch from a front-to-back window list, before any activation has been
    /// observed. Seeds occupy negative ticks (frontmost closest to zero) and leave `nextTick`
    /// alone, so the first real activation outranks the entire seed. Existing keys are never
    /// overwritten, which makes seeding idempotent and safe to land late.
    mutating func seed(frontToBack targets: [AppWindowTarget]) {
        guard !targets.isEmpty else { return }
        for (offset, target) in targets.enumerated() {
            // Frontmost closest to zero, so front-to-back input becomes highest-to-lowest rank.
            let tick = -(offset + 1)
            let appKey = WindowActivationKey.app(target.bundleID)
            if ticksByKey[appKey] == nil { ticksByKey[appKey] = tick }
            let trimmed = target.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let windowKey = WindowActivationKey.window(bundleID: target.bundleID, title: trimmed)
            if ticksByKey[windowKey] == nil { ticksByKey[windowKey] = tick }
        }
        trimIfNeeded()
    }

    /// Drops every key belonging to a terminated app, window keys included.
    mutating func forget(bundleID: String) {
        let appKey = WindowActivationKey.app(bundleID)
        let windowPrefix = "window-title|\(bundleID)|"
        ticksByKey = ticksByKey.filter { key, _ in
            key != appKey && !key.hasPrefix(windowPrefix)
        }
    }

    /// Recency of one tile, taking the *newer* of its window and app ticks.
    ///
    /// Preferring the window tick unconditionally would invert the order whenever a title
    /// resolution failed: the app tick would move on while the resolved window stayed behind, and
    /// its unresolved siblings — which inherit the app tick — would sort ahead of it. Taking the
    /// max instead degrades that case to an honest "somewhere in this app", where every window of
    /// the app ties and construction order decides.
    func rank(windowKey: String?, appKey: String?) -> WindowActivationRank? {
        let windowTick = windowKey.flatMap { ticksByKey[$0] }
        let appTick = appKey.flatMap { ticksByKey[$0] }
        switch (windowTick, appTick) {
        case let (window?, app?):
            return window >= app
                ? WindowActivationRank(tick: window, isExactWindow: true)
                : WindowActivationRank(tick: app, isExactWindow: false)
        case let (window?, nil):
            return WindowActivationRank(tick: window, isExactWindow: true)
        case let (nil, app?):
            return WindowActivationRank(tick: app, isExactWindow: false)
        case (nil, nil):
            return nil
        }
    }

    func tick(forApp bundleID: String) -> Int? {
        ticksByKey[WindowActivationKey.app(bundleID)]
    }

    /// The most recently frontmost identity. A resolved window wins over the app key it shares a
    /// tick with, so the picker can tell "this exact window" from "somewhere in this app".
    var frontmostKey: String? {
        var best: (key: String, rank: WindowActivationRank)?
        for (key, tick) in ticksByKey {
            let rank = WindowActivationRank(tick: tick, isExactWindow: !key.hasPrefix("app|"))
            guard let current = best else {
                best = (key, rank)
                continue
            }
            if rank > current.rank { best = (key, rank) }
        }
        return best?.key
    }

    var snapshot: [String: Int] {
        ticksByKey
    }

    private mutating func trimIfNeeded() {
        guard ticksByKey.count > capacity else { return }
        let survivors = ticksByKey.sorted { $0.value > $1.value }.prefix(trimTarget)
        ticksByKey = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
    }
}

/// Maintains the switcher's most-recently-used order from workspace activations.
///
/// The ledger lives here rather than on `AppState` on purpose: activations fire constantly, and
/// nothing observes the order between picker sessions (`PickerCoordinator` freezes a snapshot when
/// a session opens), so putting it in observable state would churn the view graph for no reader.
@MainActor
final class WindowActivationTracker {
    struct Dependencies {
        /// Title of the app's currently focused window. Cross-process Accessibility IPC, so it is
        /// `@Sendable` and always called off the main actor — the same reasoning that keeps
        /// `WindowEnumerator` off `@MainActor`.
        var focusedWindowTitle: @Sendable (pid_t) -> String?
        var frontToBackWindows: @Sendable () -> [AppWindowTarget]

        static let live = Dependencies(
            focusedWindowTitle: { WindowEnumerator.focusedWindowTitle(forPID: $0) },
            frontToBackWindows: { WindowEnumerator.frontToBackWindows() }
        )
    }

    private var ledger: WindowActivationLedger
    private let dependencies: Dependencies
    /// One in-flight title resolution per app; a newer activation cancels the older read.
    private var titleResolutionTasks: [String: Task<Void, Never>] = [:]
    private var seedTask: Task<Void, Never>?
    private(set) var isSeeded = false

    init(dependencies: Dependencies = .live, capacity: Int = 250) {
        self.dependencies = dependencies
        ledger = WindowActivationLedger(capacity: capacity)
    }

    /// Fills the order from the current window stacking before any activation is observed, so the
    /// first ⌥Tab after launch is already useful.
    func seedFromCurrentWindowOrder() {
        guard !isSeeded, seedTask == nil else { return }
        let frontToBackWindows = dependencies.frontToBackWindows
        seedTask = Task { @MainActor [weak self] in
            let targets = await Task.detached(priority: .utility) { frontToBackWindows() }.value
            guard let self, !Task.isCancelled else { return }
            self.ledger.seed(frontToBack: targets)
            self.isSeeded = true
            self.seedTask = nil
        }
    }

    func recordActivation(bundleID: String, processIdentifier: pid_t?) {
        guard bundleID != Bundle.main.bundleIdentifier else { return }
        let tick = ledger.recordActivation(bundleID: bundleID)
        resolveFocusedWindow(bundleID: bundleID, processIdentifier: processIdentifier, tick: tick)
    }

    /// Backstop for window switches *inside* one app (⌘`, clicking a sibling window), which emit no
    /// workspace notification. Driven by the running-app refresh, including the just-in-time pass
    /// every toggle session performs before presenting, so index 0's identity is fresh when the
    /// picker opens.
    ///
    /// This spends a fresh tick even when the frontmost app is unchanged: promoting the newly
    /// focused window above its siblings is the whole point, and that needs a rank they don't
    /// share. Re-ranking the app it already tops is harmless.
    func recordFrontmostRefresh(bundleID: String?, processIdentifier: pid_t?) {
        // `NSWorkspace.frontmostApplication` is AppCat itself while the picker is key. Ranking it
        // would put AppCat in its own switcher — the same reason `AppActivityMonitor` drops
        // AppCat's activation notifications.
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier else { return }
        let tick = ledger.recordActivation(bundleID: bundleID)
        resolveFocusedWindow(bundleID: bundleID, processIdentifier: processIdentifier, tick: tick)
    }

    func forget(bundleID: String) {
        titleResolutionTasks.removeValue(forKey: bundleID)?.cancel()
        ledger.forget(bundleID: bundleID)
    }

    /// Frozen ordering inputs for one picker session. See `PickerCoordinator.showPicker`.
    func sessionSnapshot() -> (ranks: [String: Int], frontmostKey: String?) {
        (ledger.snapshot, ledger.frontmostKey)
    }

    private func resolveFocusedWindow(bundleID: String, processIdentifier: pid_t?, tick: Int) {
        guard let processIdentifier else { return }
        titleResolutionTasks.removeValue(forKey: bundleID)?.cancel()
        let focusedWindowTitle = dependencies.focusedWindowTitle
        titleResolutionTasks[bundleID] = Task { @MainActor [weak self] in
            let title = await Task.detached(priority: .userInitiated) {
                focusedWindowTitle(processIdentifier)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.titleResolutionTasks[bundleID] = nil
            guard let title else { return }
            self.ledger.attachFocusedWindow(bundleID: bundleID, title: title, tick: tick)
        }
    }
}
