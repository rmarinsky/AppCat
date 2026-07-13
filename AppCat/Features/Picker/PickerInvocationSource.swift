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

    var activatesPanel: Bool {
        !isHoldToSwitch
    }

    var refreshesLiveSnapshot: Bool {
        isManualPresentation && !isHoldToSwitch
    }

    func opensFocusedItemOnOptionRelease(isPickerVisible: Bool) -> Bool {
        isPickerVisible && isHoldToSwitch
    }
}
