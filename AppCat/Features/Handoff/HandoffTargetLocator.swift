import AppKit
import ApplicationServices

/// Finds the point on screen where the destination app "is", for the handoff icon to fly to:
/// its frontmost on-screen window, else its Dock icon, else the middle of the screen.
/// Returns AppKit screen coordinates (origin bottom-left of the primary screen).
@MainActor
enum HandoffTargetLocator {
    static func targetPoint(bundleIdentifier: String?, fallbackScreen: NSScreen) -> CGPoint {
        if let bundleIdentifier {
            if let window = frontWindowFrame(bundleIdentifier: bundleIdentifier) {
                return CGPoint(x: window.midX, y: window.midY)
            }
            if let dockIcon = dockIconFrame(bundleIdentifier: bundleIdentifier) {
                return CGPoint(x: dockIcon.midX, y: dockIcon.midY)
            }
        }
        let visible = fallbackScreen.visibleFrame
        return CGPoint(x: visible.midX, y: visible.midY)
    }

    /// Quartz window and AX frames have a top-left origin on the primary screen.
    private static func appKitRect(fromTopLeft rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func frontWindowFrame(bundleIdentifier: String) -> CGRect? {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map(\.processIdentifier))
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
              as? [[CFString: Any]]
        else { return nil }

        // The list is ordered front to back, so the first match is the app's frontmost window.
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID] as? pid_t, pids.contains(pid),
                  (window[kCGWindowLayer] as? Int) == 0,
                  (window[kCGWindowAlpha] as? Double ?? 1) > 0,
                  let boundsDictionary = window[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 120, bounds.height >= 120
            else { continue }
            return appKitRect(fromTopLeft: bounds)
        }
        return nil
    }

    private static func dockIconFrame(bundleIdentifier: String) -> CGRect? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockElement, 0.1)

        for list in children(of: dockElement) {
            for item in children(of: list) {
                guard let url = attribute(kAXURLAttribute, of: item) as? URL,
                      Bundle(url: url)?.bundleIdentifier == bundleIdentifier,
                      let positionValue = attribute(kAXPositionAttribute, of: item),
                      let sizeValue = attribute(kAXSizeAttribute, of: item)
                else { continue }
                var position = CGPoint.zero
                var size = CGSize.zero
                // swiftlint:disable force_cast
                guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
                      AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                else { continue }
                // swiftlint:enable force_cast
                return appKitRect(fromTopLeft: CGRect(origin: position, size: size))
            }
        }
        return nil
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }
}
