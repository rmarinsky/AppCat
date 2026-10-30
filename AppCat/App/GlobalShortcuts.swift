import CoreGraphics
import Foundation
import KeyboardShortcuts

extension Notification.Name {
    /// Posted by the KeyboardShortcuts package when a stored shortcut changes. The package
    /// declares these names internally, so they are re-declared here by raw value.
    static let keyboardShortcutByNameDidChange = Self("KeyboardShortcuts_shortcutByNameDidChange")
    /// Posted with `userInfo["isActive"]` while a `Recorder` starts or stops capturing keys.
    static let keyboardShortcutRecorderActiveStatusDidChange =
        Self("KeyboardShortcuts_recorderActiveStatusDidChange")
}

extension PickerToggleShortcut {
    /// Resolves a stored shortcut into the raw key code and modifier bits an event tap observes.
    init?(_ shortcut: KeyboardShortcuts.Shortcut?) {
        guard let shortcut,
              let key = shortcut.key,
              let keyCode = UInt16(exactly: key.rawValue)
        else {
            return nil
        }

        var flags: CGEventFlags = []
        if shortcut.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if shortcut.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if shortcut.modifiers.contains(.control) { flags.insert(.maskControl) }
        if shortcut.modifiers.contains(.shift) { flags.insert(.maskShift) }

        self.init(keyCode: keyCode, modifiers: flags)
    }
}

enum GlobalShortcuts {
    static let openPickerManuallyDefault = KeyboardShortcuts.Shortcut(.tab, modifiers: [.option])
    static let openPickerManuallyLegacyDefault = KeyboardShortcuts.Shortcut(.b, modifiers: [.option, .command])
    static let reopenLastPickerDefault = KeyboardShortcuts.Shortcut(.b, modifiers: [.option, .command, .shift])

    static func migrateLegacyDefaultsIfNeeded() {
        guard KeyboardShortcuts.getShortcut(for: .openPickerManually) == openPickerManuallyLegacyDefault else {
            return
        }

        KeyboardShortcuts.setShortcut(openPickerManuallyDefault, for: .openPickerManually)
    }
}

/// System-wide hotkeys.
extension KeyboardShortcuts.Name {
    static let openPickerManually = Self(
        "openPickerManually",
        default: GlobalShortcuts.openPickerManuallyDefault
    )
    static let reopenLastPicker = Self(
        "reopenLastPicker",
        default: GlobalShortcuts.reopenLastPickerDefault
    )
}
