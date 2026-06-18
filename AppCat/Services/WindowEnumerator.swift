import AppKit
import ApplicationServices
import CoreGraphics

struct AppWindowTarget: Hashable, Identifiable {
    let bundleID: String
    let title: String
    let index: Int

    var id: String {
        "\(bundleID):\(index):\(title)"
    }
}

/// Reads the open window titles of other running apps via the Accessibility API.
/// For multi-window apps (e.g. several Cursor/VS Code windows) the title is usually the
/// project/folder, which lets the user see and filter which project each window holds.
/// Requires Accessibility permission (the app already requests it).
///
/// NOTE: deliberately NOT `@MainActor`. The `AXUIElement*` C APIs are thread-safe, and the
/// enumeration is pure cross-process IPC (no UI). Keeping it off the main actor lets callers run
/// `runningWindows()` on a background executor so a slow/unresponsive target app cannot stall the
/// main thread (and the picker) for up to the AX messaging timeout.
enum WindowEnumerator {
    /// Per-app AX messaging timeout. A hung target app would otherwise block each
    /// `AXUIElementCopyAttributeValue` call for the ~6s system default.
    private static let messagingTimeout: Float = 0.25
    private static let minimumContentWindowWidth: Double = 160
    private static let minimumContentWindowHeight: Double = 120
    private static let nonWindowMenuTitles: Set<String> = [
        "minimize",
        "minimise",
        "minimize all",
        "minimise all",
        "zoom",
        "zoom all",
        "fill",
        "center",
        "centre",
        "move & resize",
        "full-screen tile",
        "remove window from set",
        "name window...",
        "name window…",
        "downloads",
        "task manager",
        "switch window...",
        "switch window…",
        "bring all to front",
        "arrange in front",
    ]

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Open window titles for every running regular app, keyed by bundle id.
    static func runningWindowTitles() -> [String: [String]] {
        runningWindows().mapValues { windows in
            windows.map(\.title)
        }
    }

    /// Open windows for every running regular app, keyed by bundle id.
    static func runningWindows() -> [String: [AppWindowTarget]] {
        guard AXIsProcessTrusted() else { return [:] }
        var result: [String: [AppWindowTarget]] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
            let windows = windows(forPID: app.processIdentifier, bundleID: id)
            if !windows.isEmpty { result[id] = windows }
        }
        return result
    }

    static func titles(forBundleID bundleID: String) -> [String] {
        windows(forBundleID: bundleID).map(\.title)
    }

    static func windows(forBundleID bundleID: String) -> [AppWindowTarget] {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return [] }
        return windows(forPID: app.processIdentifier, bundleID: bundleID)
    }

    static func hasOpenWindows(bundleID: String) -> Bool? {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return nil }

        return !axWindows(forPID: app.processIdentifier).isEmpty
    }

    @discardableResult
    static func activate(_ target: AppWindowTarget) -> Bool {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first
        else { return false }

        let windows = axWindows(forPID: app.processIdentifier)
        guard !windows.isEmpty else {
            return activateFromWindowMenu(target, app: app)
        }

        let indexedWindow = windows.indices.contains(target.index) && title(of: windows[target.index]) == target.title
            ? windows[target.index]
            : nil
        let matchingWindow = indexedWindow ?? windows.first { title(of: $0) == target.title }
        guard let window = matchingWindow else {
            return activateFromWindowMenu(target, app: app)
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        forceActivate(app)
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        forceActivate(app)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            forceActivate(app)
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        return true
    }

    private static func forceActivate(_ app: NSRunningApplication) {
        app.unhide()
        app.activate(options: strongActivationOptions)
    }

    private static var strongActivationOptions: NSApplication.ActivationOptions {
        var options: NSApplication.ActivationOptions = [.activateAllWindows]
        if #unavailable(macOS 14.0) {
            options.insert(.activateIgnoringOtherApps)
        }
        return options
    }

    private static func windows(forPID pid: pid_t, bundleID: String) -> [AppWindowTarget] {
        let axTargets: [AppWindowTarget] = axWindows(forPID: pid).enumerated().compactMap { index, window in
            guard let title = title(of: window) else { return nil }
            return AppWindowTarget(bundleID: bundleID, title: title, index: index)
        }
        let cgTargets = cgWindows(forPID: pid, bundleID: bundleID)
        let menuTargets = windowMenuWindows(forPID: pid, bundleID: bundleID)

        // Some Electron/ToDesktop apps (Cursor is the practical example) expose zero AX windows
        // while CoreGraphics or the app's Window menu still list their real titled document windows.
        // Prefer the source with more content windows so the switcher does not collapse multi-window
        // apps to one item.
        return [axTargets, cgTargets, menuTargets].max { $0.count < $1.count } ?? axTargets
    }

    private static func axWindows(forPID pid: pid_t) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(pid)
        // Cap how long a hung target app can block this IPC round-trip.
        AXUIElementSetMessagingTimeout(axApp, messagingTimeout)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement]
        else { return [] }

        return windows
    }

    private static func title(of window: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        return title
    }

    private static func cgWindows(forPID pid: pid_t, bundleID: String) -> [AppWindowTarget] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        var targets: [AppWindowTarget] = []
        var seenTitles: Set<String> = []

        for info in windowInfo {
            guard ownerPID(from: info) == pid,
                  layer(from: info) == 0,
                  alpha(from: info) > 0,
                  let title = cgWindowTitle(from: info),
                  let bounds = cgWindowBounds(from: info),
                  bounds.width >= minimumContentWindowWidth,
                  bounds.height >= minimumContentWindowHeight
            else { continue }

            let normalizedTitle = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seenTitles.insert(normalizedTitle).inserted else { continue }

            targets.append(AppWindowTarget(bundleID: bundleID, title: title, index: targets.count))
        }

        return targets
    }

    private static func windowMenuWindows(forPID pid: pid_t, bundleID: String) -> [AppWindowTarget] {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, messagingTimeout)

        guard let menuBar = elementAttribute(axApp, kAXMenuBarAttribute),
              let windowMenu = windowMenu(in: menuBar)
        else { return [] }

        var targets: [AppWindowTarget] = []
        var seenTitles: Set<String> = []

        for title in windowMenuTitles(in: windowMenu) {
            let normalizedTitle = normalizedMenuTitle(title)
            guard isLikelyWindowTitle(normalizedTitle),
                  seenTitles.insert(normalizedTitle).inserted
            else { continue }

            targets.append(AppWindowTarget(bundleID: bundleID, title: title, index: targets.count))
        }

        return targets
    }

    private static func activateFromWindowMenu(_ target: AppWindowTarget, app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, messagingTimeout)

        forceActivate(app)

        guard let menuBar = elementAttribute(axApp, kAXMenuBarAttribute),
              let menuItem = findWindowMenuItem(in: menuBar, matching: target.title),
              AXUIElementPerformAction(menuItem, kAXPressAction as CFString) == .success
        else { return false }

        forceActivate(app)
        return true
    }

    private static func findWindowMenuItem(in menuBar: AXUIElement, matching targetTitle: String) -> AXUIElement? {
        let searchRoot = windowMenu(in: menuBar) ?? menuBar
        return findMenuItem(in: searchRoot, matching: targetTitle)
    }

    private static func windowMenu(in menuBar: AXUIElement) -> AXUIElement? {
        children(of: menuBar).first { menuBarItem in
            let menuTitle = normalizedMenuTitle(title(ofMenuItem: menuBarItem))
            return menuTitle == "window" || menuTitle == "вікно"
        }
    }

    private static func windowMenuTitles(in windowMenu: AXUIElement) -> [String] {
        children(of: windowMenu)
            .flatMap(children)
            .map(title(ofMenuItem:))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func findMenuItem(in element: AXUIElement, matching targetTitle: String) -> AXUIElement? {
        let wantedTitle = normalizedMenuTitle(targetTitle)

        for child in children(of: element) {
            if normalizedMenuTitle(title(ofMenuItem: child)) == wantedTitle {
                return child
            }
            if let match = findMenuItem(in: child, matching: targetTitle) {
                return match
            }
        }

        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
        else { return nil }
        return ref as! AXUIElement?
    }

    private static func title(ofMenuItem element: AXUIElement) -> String {
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success
        else { return "" }
        return titleRef as? String ?? ""
    }

    private static func normalizedMenuTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func isLikelyWindowTitle(_ normalizedTitle: String) -> Bool {
        !nonWindowMenuTitles.contains(normalizedTitle)
    }

    private static func ownerPID(from info: [String: Any]) -> pid_t? {
        (info[kCGWindowOwnerPID as String] as? NSNumber).map { pid_t($0.int32Value) }
    }

    private static func layer(from info: [String: Any]) -> Int {
        (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? Int.max
    }

    private static func alpha(from info: [String: Any]) -> Double {
        (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
    }

    private static func cgWindowTitle(from info: [String: Any]) -> String? {
        guard let title = (info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        return title
    }

    private static func cgWindowBounds(from info: [String: Any]) -> CGSize? {
        guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let width = (bounds["Width"] as? NSNumber)?.doubleValue,
              let height = (bounds["Height"] as? NSNumber)?.doubleValue
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
