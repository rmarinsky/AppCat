import Carbon.HIToolbox
import CoreGraphics
import Foundation

extension Notification.Name {
    static let pickerActivationSettingsChanged = Self("pickerActivationSettingsChanged")
}

final class PickerActivationListener {
    var onHoldStep: ((Int) -> Void)?
    var onHoldRelease: (() -> Void)?
    var onServiceKeyTrigger: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var serviceTapCounter = TapSequenceCounter()
    private var holdSessionActive = false

    deinit {
        stop()
    }

    func refresh() {
        if needsEventTap {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard eventTap == nil else { return }
        guard PickerActivationPermission.hasInputMonitoring else {
            Log.app.warning("Advanced picker activation needs Input Monitoring permission")
            return
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: pickerActivationCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.app.error("Failed to create picker activation event tap")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.app.info("Picker activation event tap started")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        holdSessionActive = false
        serviceTapCounter.reset()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            if handleHoldTab(keyCode: keyCode, flags: event.flags) {
                return nil
            }
            if handleServiceKeyDown(keyCode: keyCode, event: event) {
                return nil
            }
        case .keyUp:
            if holdSessionActive, keyCode == UInt16(kVK_Tab) {
                return nil
            }
        case .flagsChanged:
            handleHoldFlagsChanged(event.flags)
            if handleServiceFlagsChanged(keyCode: keyCode, event: event) {
                return nil
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private var needsEventTap: Bool {
        SettingsStorage.shared.pickerActivationMode == .holdOptionTab ||
            SettingsStorage.shared.pickerServiceKey != .off
    }

    private func handleHoldTab(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard SettingsStorage.shared.pickerActivationMode == .holdOptionTab else { return false }
        guard keyCode == UInt16(kVK_Tab), flags.contains(.maskAlternate) else { return false }
        guard flags.intersection([.maskCommand, .maskControl]).isEmpty else { return false }

        holdSessionActive = true
        let delta = flags.contains(.maskShift) ? -1 : 1
        DispatchQueue.main.async { [onHoldStep] in
            onHoldStep?(delta)
        }
        return true
    }

    private func handleHoldFlagsChanged(_ flags: CGEventFlags) {
        guard holdSessionActive, !flags.contains(.maskAlternate) else { return }
        holdSessionActive = false
        DispatchQueue.main.async { [onHoldRelease] in
            onHoldRelease?()
        }
    }

    private func handleServiceKeyDown(keyCode: UInt16, event: CGEvent) -> Bool {
        guard SettingsStorage.shared.pickerServiceKey == .escape, keyCode == UInt16(kVK_Escape) else {
            return false
        }
        return registerServiceTap(event: event)
    }

    private func handleServiceFlagsChanged(keyCode: UInt16, event: CGEvent) -> Bool {
        guard SettingsStorage.shared.pickerServiceKey == .capsLock, keyCode == UInt16(kVK_CapsLock) else {
            return false
        }
        return registerServiceTap(event: event)
    }

    private func registerServiceTap(event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }

        let didComplete = serviceTapCounter.registerTap(
            at: ProcessInfo.processInfo.systemUptime,
            requiredCount: SettingsStorage.shared.pickerServiceTapCount.rawValue,
            interval: SettingsStorage.shared.pickerServiceTapInterval
        )
        if didComplete {
            DispatchQueue.main.async { [onServiceKeyTrigger] in
                onServiceKeyTrigger?()
            }
        }
        return true
    }
}

private func pickerActivationCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let listener = Unmanaged<PickerActivationListener>.fromOpaque(userInfo).takeUnretainedValue()
    return listener.handle(type: type, event: event)
}

