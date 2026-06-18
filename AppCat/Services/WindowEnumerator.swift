import AppKit
import ApplicationServices

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
        guard !windows.isEmpty else { return false }

        let indexedWindow = windows.indices.contains(target.index) && title(of: windows[target.index]) == target.title
            ? windows[target.index]
            : nil
        let matchingWindow = indexedWindow ?? windows.first { title(of: $0) == target.title }
        guard let window = matchingWindow else { return false }

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
        axWindows(forPID: pid).enumerated().compactMap { index, window in
            guard let title = title(of: window) else { return nil }
            return AppWindowTarget(bundleID: bundleID, title: title, index: index)
        }
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
}
