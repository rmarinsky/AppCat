import KeyboardShortcuts

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
