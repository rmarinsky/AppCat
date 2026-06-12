import AppKit
import ApplicationServices

/// Reads the open window titles of other running apps via the Accessibility API.
/// For multi-window apps (e.g. several Cursor/VS Code windows) the title is usually the
/// project/folder, which lets the user see and filter which project each window holds.
/// Requires Accessibility permission (the app already requests it).
@MainActor
enum WindowEnumerator {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Open window titles for every running regular app, keyed by bundle id.
    static func runningWindowTitles() -> [String: [String]] {
        guard AXIsProcessTrusted() else { return [:] }
        var result: [String: [String]] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
            let titles = titles(forPID: app.processIdentifier)
            if !titles.isEmpty { result[id] = titles }
        }
        return result
    }

    static func titles(forBundleID bundleID: String) -> [String] {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return [] }
        return titles(forPID: app.processIdentifier)
    }

    private static func titles(forPID pid: pid_t) -> [String] {
        let axApp = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return [] }

        var titles: [String] = []
        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty
            else { continue }
            titles.append(title)
        }
        return titles
    }
}
