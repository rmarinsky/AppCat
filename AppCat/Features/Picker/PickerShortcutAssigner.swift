import Foundation

struct PickerShortcut: Equatable {
    enum Source: Equatable {
        case configured
        case positional
    }

    let key: Character
    let keyCode: UInt16
    let source: Source
}

enum PickerShortcutAssigner {
    private static let positionalKeyCharacters = Array("1234567890qwertyuiopasdfghjklzxcvbnm")

    static func assignments(
        for items: [PickerItem],
        positionalEnabled: Bool
    ) -> [String: PickerShortcut] {
        var assignments: [String: PickerShortcut] = [:]
        var usedKeyCodes = Set<UInt16>()
        var configuredOwnerIDs = Set<String>()

        for item in items {
            guard let ownerID = configuredShortcutOwnerID(for: item),
                  configuredOwnerIDs.insert(ownerID).inserted,
                  let shortcut = configuredShortcut(for: item),
                  usedKeyCodes.insert(shortcut.keyCode).inserted
            else { continue }
            assignments[item.id] = shortcut
        }

        guard positionalEnabled else { return assignments }

        var positionalIndex = 0
        for item in items where assignments[item.id] == nil {
            guard let shortcut = nextPositionalShortcut(
                startingAt: &positionalIndex,
                usedKeyCodes: &usedKeyCodes
            ) else { break }
            assignments[item.id] = shortcut
        }

        return assignments
    }

    static func item(
        forKeyCode keyCode: UInt16,
        in items: [PickerItem],
        positionalEnabled: Bool
    ) -> PickerItem? {
        let assigned = assignments(for: items, positionalEnabled: positionalEnabled)
        return items.first { item in
            assigned[item.id]?.keyCode == keyCode
        }
    }

    private static func nextPositionalShortcut(
        startingAt index: inout Int,
        usedKeyCodes: inout Set<UInt16>
    ) -> PickerShortcut? {
        while index < positionalKeyCharacters.count {
            let key = positionalKeyCharacters[index]
            index += 1
            guard let keyCode = KeyCodeMap.keyCode(for: key),
                  usedKeyCodes.insert(keyCode).inserted
            else { continue }
            return PickerShortcut(key: key, keyCode: keyCode, source: .positional)
        }
        return nil
    }

    private static func configuredShortcutOwnerID(for item: PickerItem) -> String? {
        if let profile = item.profile, let browser = item.browser {
            return "profile:\(browser.id):\(profile.directoryName)"
        }
        if let browser = item.browser {
            return "browser:\(browser.id)"
        }
        if let app = item.app {
            return "app:\(app.id)"
        }
        return nil
    }

    private static func configuredShortcut(for item: PickerItem) -> PickerShortcut? {
        if let profile = item.profile {
            return shortcut(key: profile.hotkey, keyCode: profile.hotkeyKeyCode)
        }
        if let browser = item.browser {
            return shortcut(key: browser.hotkey, keyCode: browser.hotkeyKeyCode)
        }
        if let app = item.app {
            return shortcut(key: app.hotkey, keyCode: app.hotkeyKeyCode)
        }
        return nil
    }

    private static func shortcut(key: Character?, keyCode: UInt16?) -> PickerShortcut? {
        guard let resolvedKeyCode = keyCode ?? key.flatMap(KeyCodeMap.keyCode(for:)) else {
            return nil
        }
        guard let label = key ?? KeyCodeMap.displayCharacter(for: resolvedKeyCode) else {
            return nil
        }
        return PickerShortcut(key: label, keyCode: resolvedKeyCode, source: .configured)
    }
}

enum PickerShortcutPolicy {
    static func assignments(
        for items: [PickerItem],
        activationMode: PickerActivationMode,
        isManualPickerPresentation: Bool,
        selectWithNumberKeys: Bool
    ) -> [String: PickerShortcut] {
        guard allowsDirectSelection(activationMode: activationMode, isManualPickerPresentation: isManualPickerPresentation) else {
            return [:]
        }
        return PickerShortcutAssigner.assignments(for: items, positionalEnabled: selectWithNumberKeys)
    }

    static func item(
        forKeyCode keyCode: UInt16,
        in items: [PickerItem],
        activationMode: PickerActivationMode,
        isManualPickerPresentation: Bool,
        selectWithNumberKeys: Bool
    ) -> PickerItem? {
        guard allowsDirectSelection(activationMode: activationMode, isManualPickerPresentation: isManualPickerPresentation) else {
            return nil
        }
        return PickerShortcutAssigner.item(
            forKeyCode: keyCode,
            in: items,
            positionalEnabled: selectWithNumberKeys
        )
    }

    private static func allowsDirectSelection(
        activationMode: PickerActivationMode,
        isManualPickerPresentation: Bool
    ) -> Bool {
        !isManualPickerPresentation || activationMode == .toggleShortcut
    }
}
