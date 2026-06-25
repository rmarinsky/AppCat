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
    enum WindowSource {
        case ax
        case coreGraphics
        /// Titles read from the app's "Window" menu. The authoritative window list for
        /// Electron editors (VS Code/Cursor/Zed), which under-report through the AX windows
        /// attribute, and the same source `activate(_:)` presses to switch windows.
        case menu
    }

    struct WindowCandidate: Equatable {
        let bundleID: String
        let title: String
        let index: Int
        let source: WindowSource
        let role: String?
        let subrole: String?
        let isMinimized: Bool?
        let isModal: Bool?
        let ownerPID: pid_t?
        let layer: Int?
        let alpha: Double?
        let isOnscreen: Bool?
        let sharingState: Int?
        let bounds: CGSize?

        init(
            bundleID: String,
            title: String,
            index: Int,
            source: WindowSource,
            role: String? = nil,
            subrole: String? = nil,
            isMinimized: Bool? = nil,
            isModal: Bool? = nil,
            ownerPID: pid_t? = nil,
            layer: Int? = nil,
            alpha: Double? = nil,
            isOnscreen: Bool? = nil,
            sharingState: Int? = nil,
            bounds: CGSize? = nil
        ) {
            self.bundleID = bundleID
            self.title = title
            self.index = index
            self.source = source
            self.role = role
            self.subrole = subrole
            self.isMinimized = isMinimized
            self.isModal = isModal
            self.ownerPID = ownerPID
            self.layer = layer
            self.alpha = alpha
            self.isOnscreen = isOnscreen
            self.sharingState = sharingState
            self.bounds = bounds
        }
    }

    /// Per-app AX messaging timeout. A hung target app would otherwise block each
    /// `AXUIElementCopyAttributeValue` call for the ~6s system default.
    private static let messagingTimeout: Float = 0.25
    private static let minimumContentWindowWidth: Double = 160
    private static let minimumContentWindowHeight: Double = 120
    /// Frameworks whose presence in a bundle marks an app as drawing its UI in embedded web content
    /// (Electron, Chromium Embedded). Such apps under-report through `kAXWindowsAttribute`.
    private static let webContentFrameworkNames: Set<String> = [
        "Electron Framework.framework",
        "Chromium Embedded Framework.framework",
    ]
    private static let ignoredAXSubroles: Set<String> = [
        kAXDialogSubrole as String,
        kAXSystemDialogSubrole as String,
        kAXFloatingWindowSubrole as String,
        kAXSystemFloatingWindowSubrole as String,
    ]
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
        "show previous tab",
        "show next tab",
        "move tab to new window",
        "merge all windows",
        "close",
        "close all",
        "toggle full screen",
        "contacts",
        "add contact",
        "new group",
        "new channel",
        "show telegram",
        "go to next conversation",
        "go to previous conversation",
        "equalizer",
        "equaliser",
        "mini player",
        "miniplayer",
        "activity",
        "visualiser",
        "visualizer",
        "visualiser settings",
        "visualizer settings",
        "switch to mini player",
        "now playing",
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
        let axTargets = windowTargets(from: axWindowCandidates(forPID: pid, bundleID: bundleID))

        // Apps that draw their UI in embedded web content under-report through `kAXWindowsAttribute`:
        // background windows expose an empty AX title and windows on other Spaces are omitted, so the
        // AX list collapses — to 1 usable window even when several are open, or to 0 when the app is
        // entirely on another Space. This covers Electron editors (VS Code/Cursor/Zed/Windsurf…) and
        // WKWebView wrappers (cmux, Tauri apps) alike. There's no single static marker for the WebKit
        // ones, so detect the Electron/CEF *bundle type* deterministically and, for the rest, the
        // *symptom* of AX returning nothing. When either holds, merge the app's "Window" menu — the
        // authoritative, cross-Space window list — preferring its order. Apps that already report ≥1
        // window via AX are trusted verbatim: that avoids a phantom tile when the same window carries
        // a slightly different title in the menu than in AX (Chrome/Edge).
        let consultWindowMenu = shouldMergeWindowMenu(
            axWindowCount: axTargets.count,
            isWebContentApp: isWebContentApp(bundleID: bundleID)
        )
        guard consultWindowMenu else { return axTargets }

        let menuTargets = windowTargets(from: menuWindowCandidates(forPID: pid, bundleID: bundleID))
        let merged = mergeWindowTargets(menuTargets, axTargets)
        if !merged.isEmpty { return merged }

        // Last resort for an app with no usable Window menu whose windows are off-Space/empty-titled.
        return windowTargets(from: cgWindowCandidates(forPID: pid, bundleID: bundleID))
    }

    /// Union of two already-filtered target lists, deduped by normalized title, preserving the
    /// order of `primary` then appending titles only `secondary` provides.
    static func mergeWindowTargets(_ primary: [AppWindowTarget], _ secondary: [AppWindowTarget]) -> [AppWindowTarget] {
        var seen = Set<String>()
        var result: [AppWindowTarget] = []
        for target in primary + secondary {
            let key = target.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if seen.insert(key).inserted { result.append(target) }
        }
        return result
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

    private static func axWindowCandidates(forPID pid: pid_t, bundleID: String) -> [WindowCandidate] {
        axWindows(forPID: pid).enumerated().map { index, window in
            WindowCandidate(
                bundleID: bundleID,
                title: title(of: window) ?? "",
                index: index,
                source: .ax,
                role: stringAttribute(window, kAXRoleAttribute as CFString),
                subrole: stringAttribute(window, kAXSubroleAttribute as CFString),
                isMinimized: boolAttribute(window, kAXMinimizedAttribute as CFString),
                isModal: boolAttribute(window, kAXModalAttribute as CFString)
            )
        }
    }

    private static func title(of window: AXUIElement) -> String? {
        guard let title = stringAttribute(window, kAXTitleAttribute as CFString)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else { return nil }
        return title
    }

    /// Window titles read from the app's "Window" menu — the authoritative list of open windows,
    /// including ones on other Spaces and ones whose AX title comes back empty.
    private static func menuWindowCandidates(forPID pid: pid_t, bundleID: String) -> [WindowCandidate] {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, messagingTimeout)

        guard let menuBar = elementAttribute(axApp, kAXMenuBarAttribute),
              let windowMenuItem = windowMenu(in: menuBar)
        else { return [] }

        return windowMenuWindowTitles(in: windowMenuItem).enumerated().map { index, title in
            WindowCandidate(bundleID: bundleID, title: title, index: index, source: .menu)
        }
    }

    /// The window entries of a "Window" menu. A standard macOS Window menu places the open-window
    /// list as the trailing group, after the last separator that divides it from the window
    /// commands (Minimize, Zoom, …). Falling back to all non-separator items is safe because the
    /// command titles are rejected later by `nonWindowMenuTitles`.
    private static func windowMenuWindowTitles(in windowMenuItem: AXUIElement) -> [String] {
        // The menu bar item's single child is the AXMenu whose children are the menu items.
        guard let menu = children(of: windowMenuItem).first else { return [] }
        let titles = children(of: menu).map { item in
            title(ofMenuItem: item).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return windowListTitles(fromMenuItemTitles: titles)
    }

    /// The open-window entries within an ordered list of Window-menu item titles (separators are
    /// empty strings). The window list is the trailing group after the last separator; command
    /// titles that slip through are rejected later by `nonWindowMenuTitles`.
    static func windowListTitles(fromMenuItemTitles titles: [String]) -> [String] {
        let lastSeparatorIndex = titles.lastIndex(where: \.isEmpty) ?? -1
        return titles[(lastSeparatorIndex + 1)...].filter { !$0.isEmpty }
    }

    private static func cgWindowCandidates(forPID pid: pid_t, bundleID: String) -> [WindowCandidate] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        var candidates: [WindowCandidate] = []

        for info in windowInfo {
            guard ownerPID(from: info) == pid else { continue }
            candidates.append(WindowCandidate(
                bundleID: bundleID,
                title: cgWindowTitle(from: info) ?? "",
                index: candidates.count,
                source: .coreGraphics,
                ownerPID: ownerPID(from: info),
                layer: layer(from: info),
                alpha: alpha(from: info),
                isOnscreen: isOnscreen(from: info),
                sharingState: sharingState(from: info),
                bounds: cgWindowBounds(from: info)
            ))
        }

        return candidates
    }

    static func windowTargets(from candidates: [WindowCandidate]) -> [AppWindowTarget] {
        filteredWindowCandidates(candidates).map { candidate in
            AppWindowTarget(bundleID: candidate.bundleID, title: candidate.title.trimmedWindowTitle, index: candidate.index)
        }
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

    private static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success else { return nil }
        return ref as? Bool
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

    static func filteredWindowCandidates(_ candidates: [WindowCandidate]) -> [WindowCandidate] {
        var seenTitles = Set<String>()
        return candidates.filter(isValidWindowCandidate).filter { candidate in
            seenTitles.insert(candidate.dedupeKey).inserted
        }
    }

    static func isValidWindowCandidate(_ candidate: WindowCandidate) -> Bool {
        let title = candidate.title.trimmedWindowTitle
        guard !title.isEmpty,
              isLikelyWindowTitle(normalizedMenuTitle(title))
        else { return false }

        switch candidate.source {
        case .ax:
            guard candidate.role == kAXWindowRole as String,
                  candidate.isMinimized != true,
                  candidate.isModal != true
            else { return false }
            guard let subrole = candidate.subrole else { return true }
            return !ignoredAXSubroles.contains(subrole)

        case .menu:
            // The non-empty/non-command checks above already validate menu titles;
            // command items (Minimize, Zoom, …) are excluded via `nonWindowMenuTitles`.
            return true

        case .coreGraphics:
            guard candidate.ownerPID != nil,
                  candidate.layer == 0,
                  (candidate.alpha ?? 0) > 0,
                  candidate.isOnscreen == true,
                  candidate.sharingState != nil,
                  candidate.sharingState != 0,
                  let bounds = candidate.bounds,
                  bounds.width >= minimumContentWindowWidth,
                  bounds.height >= minimumContentWindowHeight
            else { return false }
            return true
        }
    }

    private static func isLikelyWindowTitle(_ normalizedTitle: String) -> Bool {
        !nonWindowMenuTitles.contains(normalizedTitle)
    }

    /// Whether to cross-check an app's "Window" menu against its AX window list. True when AX returns
    /// *nothing* (the app's windows are all off-Space or empty-titled — consult the menu, with no AX
    /// window to accidentally duplicate) or the app is a known Electron/CEF bundle (so a VS Code with
    /// 2 visible + 1 off-Space window still merges). When AX already reports ≥1 window for a normal
    /// app we trust it verbatim: merging the menu there risks a phantom tile, because the same window
    /// can carry a different title in the menu (e.g. Chrome appends " - Google Chrome") and so fails
    /// to dedupe. `isWebContentApp` is an autoclosure so the bundle probe is skipped on the AX==0 path.
    static func shouldMergeWindowMenu(axWindowCount: Int, isWebContentApp: @autoclosure () -> Bool) -> Bool {
        axWindowCount == 0 || isWebContentApp()
    }

    /// Whether a running app draws its UI in embedded web content (Electron/Chromium). Pure bundle
    /// inspection — no AX, no allowlist. WKWebView wrappers (e.g. cmux) share the system framework so
    /// they aren't caught here; they're handled by the ≤1-window symptom path instead.
    static func isWebContentApp(bundleID: String) -> Bool {
        guard let appURL = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        return bundleContainsWebContentFramework(in: appURL)
    }

    /// True if `Contents/Frameworks` holds an Electron or Chromium Embedded framework.
    static func bundleContainsWebContentFramework(in appURL: URL) -> Bool {
        let frameworks = appURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        return webContentFrameworkNames.contains { name in
            FileManager.default.fileExists(atPath: frameworks.appendingPathComponent(name).path)
        }
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

    private static func isOnscreen(from info: [String: Any]) -> Bool? {
        info[kCGWindowIsOnscreen as String] as? Bool
    }

    private static func sharingState(from info: [String: Any]) -> Int? {
        (info[kCGWindowSharingState as String] as? NSNumber)?.intValue
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

private extension WindowEnumerator.WindowCandidate {
    var dedupeKey: String {
        "\(bundleID)|\(title.trimmedWindowTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))"
    }
}

private extension String {
    var trimmedWindowTitle: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
