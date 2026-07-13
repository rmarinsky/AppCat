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

    var allowsDirectSelection: Bool {
        !isHoldToSwitch
    }

    var requiresKeyboardFocus: Bool {
        !isHoldToSwitch
    }

    var refreshesLiveSnapshot: Bool {
        isManualPresentation && !isHoldToSwitch
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
}
