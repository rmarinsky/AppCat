import KeyboardShortcuts

/// System-wide hotkeys. Defaults match the Figma Shortcuts screen:
/// ⌥⌘B opens the picker manually, ⌥⌘⇧B re-opens the last picker.
extension KeyboardShortcuts.Name {
    static let openPickerManually = Self(
        "openPickerManually",
        default: .init(.b, modifiers: [.option, .command])
    )
    static let reopenLastPicker = Self(
        "reopenLastPicker",
        default: .init(.b, modifiers: [.option, .command, .shift])
    )
}
