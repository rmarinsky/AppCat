enum PickerInvocationSource: Equatable {
    case linkRouting
    case toggleShortcut
    case serviceKey
    case holdOptionTab

    var isManualPresentation: Bool {
        self != .linkRouting
    }

    var isHoldToSwitch: Bool {
        self == .holdOptionTab
    }

    var refreshesLiveSnapshot: Bool {
        isManualPresentation && !isHoldToSwitch
    }

    var requiresKeyboardFocus: Bool {
        !isHoldToSwitch
    }

    /// Toggle/service sessions must not paint an old per-window cache and visibly replace it
    /// later. Hold-to-switch deliberately keeps the cached list so its first frame stays instant
    /// and stable while Option remains down.
    var requiresFreshSnapshotBeforePresentation: Bool {
        self == .toggleShortcut || self == .serviceKey
    }

    func opensFocusedItemOnOptionRelease(isPickerVisible: Bool) -> Bool {
        isPickerVisible && isHoldToSwitch
    }

    /// ⌘Tab semantics: a manual switcher opens focused on the window you were in *before* this one.
    ///
    /// Link routing is excluded because it has no "previous" — its list is destinations for a URL,
    /// not a history. Hold-⌥Tab is excluded because it already reaches index 1 by presenting at 0
    /// and immediately stepping +1; including it here would double-advance to 2.
    var startsOnPreviousItem: Bool {
        self == .toggleShortcut || self == .serviceKey
    }

    /// Whether repeating the activation shortcut steps through the list instead of confirming.
    var advancesFocusOnRepeatedInvocation: Bool {
        self == .toggleShortcut || self == .serviceKey
    }
}

enum PickerInitialFocusPolicy {
    /// Index 0 is the most recently used *visible* tile, which is the window you are in now only
    /// when that target survived the picker's own filters. If the user hid it, or windowless apps
    /// are switched off and it has none, index 0 is already the previous window — so focus it.
    static func initialIndex(
        items: [PickerItem],
        frontmostRankKey: String?,
        invocationSource: PickerInvocationSource
    ) -> Int {
        guard invocationSource.startsOnPreviousItem,
              items.count >= 2,
              let frontmostRankKey,
              items[0].matchesActivationRankKey(frontmostRankKey)
        else { return 0 }
        return 1
    }
}

enum PickerManualActivationAction: Equatable {
    case presentPicker
    case advanceFocus(delta: Int)
    case confirmFocusedItem
    case cancelPendingPresentation
}

enum PickerManualActivationPolicy {
    static func action(
        isPickerVisible: Bool,
        isPresentationPending: Bool,
        advancesOnRepeat: Bool
    ) -> PickerManualActivationAction {
        if isPickerVisible {
            return advancesOnRepeat ? .advanceFocus(delta: 1) : .confirmFocusedItem
        }
        if isPresentationPending {
            // A second press during the window-enumeration wait is the ⌘Tab "two back" gesture,
            // not a cancel: nothing is on screen yet to cancel, and Escape already covers that
            // once the panel is key.
            return advancesOnRepeat ? .advanceFocus(delta: 1) : .cancelPendingPresentation
        }
        return .presentPicker
    }
}
