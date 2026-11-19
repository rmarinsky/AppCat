import AppKit
import ApplicationServices

/// New Microsoft Teams keeps several signed-in accounts in one process but shows one of them in its
/// single main window. Its window titles end with the active account's email
/// ("Chat | Team Velocity | Once For All Limited | name@company.com"), and the app menu holds an
/// account submenu with every signed-in email (the active one checked). This reads both so the
/// switcher can show one tile per account and a separate tile for a call window.
enum TeamsAccounts {
    static let bundleID = "com.microsoft.teams2"

    struct Account: Equatable {
        let email: String
        let isActive: Bool
    }

    private static let titleSeparator = " | "

    /// Email of the account a Teams main window shows, or nil for any other window (a call).
    static func accountEmail(inWindowTitle title: String) -> String? {
        guard let last = title.components(separatedBy: titleSeparator).last,
              isEmail(last)
        else { return nil }
        return last.trimmingCharacters(in: .whitespaces)
    }

    /// First title segment: the Teams section ("Chat", "Calendar") or the call name.
    static func leadingSegment(ofWindowTitle title: String) -> String {
        let first = title.components(separatedBy: titleSeparator).first ?? title
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// "Roman.Marinskyi@onceforall.com" -> "onceforall".
    static func shortName(ofEmail email: String) -> String {
        guard let domain = email.split(separator: "@").last,
              let label = domain.split(separator: ".").first
        else { return email }
        return String(label)
    }

    /// Adds a tile target for every signed-in account the main window does not show. Its title is
    /// the email, so it stays unique and survives the ledger's title-based identity.
    static func addingAccountTargets(to windows: [AppWindowTarget], accounts: [Account]) -> [AppWindowTarget] {
        let shownEmails = Set(windows.compactMap { accountEmail(inWindowTitle: $0.title)?.lowercased() })
        guard !shownEmails.isEmpty else { return windows }
        let extra = accounts
            .filter { !shownEmails.contains($0.email.lowercased()) }
            .map { AppWindowTarget(bundleID: bundleID, title: $0.email, index: -1, teamsAccount: $0.email) }
        return windows + extra
    }

    // MARK: - Accessibility

    /// Signed-in accounts from the app menu. The submenu is found by its email items, not by its
    /// "Account" title, because Teams localizes that title.
    static func accounts(pid: pid_t) -> [Account] {
        accountMenuItems(pid: pid).map { item, title in
            Account(email: title, isActive: string(item, kAXMenuItemMarkCharAttribute as CFString)?.isEmpty == false)
        }
    }

    /// Presses the account's menu item. Teams then shows that account in its main window.
    static func switchAccount(to email: String, pid: pid_t) -> Bool {
        guard let item = accountMenuItems(pid: pid).first(where: { $0.title.caseInsensitiveCompare(email) == .orderedSame })?.item
        else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    private static func accountMenuItems(pid: pid_t) -> [(item: AXUIElement, title: String)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        // Menu bar item 0 is the Apple menu; item 1 is the app menu.
        guard let menuBar = element(app, kAXMenuBarAttribute as CFString),
              let appMenuBarItem = children(menuBar).dropFirst().first,
              let appMenu = children(appMenuBarItem).first
        else { return [] }
        for menuItem in children(appMenu) {
            guard let submenu = children(menuItem).first else { continue }
            let entries = children(submenu).compactMap { item -> (AXUIElement, String)? in
                guard let title = string(item, kAXTitleAttribute as CFString), isEmail(title) else { return nil }
                return (item, title)
            }
            if !entries.isEmpty { return entries.map { (item: $0.0, title: $0.1) } }
        }
        return []
    }

    private static func isEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), !trimmed.contains(" ") else { return false }
        return at > trimmed.startIndex && trimmed[at...].contains(".")
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func element(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
}
