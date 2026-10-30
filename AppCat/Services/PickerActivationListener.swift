import Carbon.HIToolbox
import CoreGraphics
import Foundation

extension Notification.Name {
    static let pickerActivationSettingsChanged = Self("pickerActivationSettingsChanged")
}

/// The toggle shortcut resolved to the raw key code and modifier bits the event tap sees.
///
/// Carbon's `RegisterEventHotKey` — what the KeyboardShortcuts package registers under the
/// hood — grants no priority over other apps: two processes can claim the same combination
/// and both get `noErr`, with no way to learn who else holds it. Matching the shortcut in
/// our session event tap instead lets us swallow the key before anyone else is dispatched.
struct PickerToggleShortcut: Equatable {
    /// Modifier bits worth comparing. Caps Lock, Fn, the device-side left/right variants and
    /// `.maskNonCoalesced` ride along on real events and must not break an otherwise exact match.
    private static let comparedModifiers: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift
    ]

    let keyCode: UInt16
    let modifiers: CGEventFlags

    init(keyCode: UInt16, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.comparedModifiers)
    }

    func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(Self.comparedModifiers) == modifiers
    }
}

final class PickerActivationListener {
    var onHoldStep: ((Int) -> Void)?
    var onHoldRelease: (() -> Void)?
    var onServiceKeyTrigger: (() -> Void)?
    var onToggleShortcut: (() -> Void)?
    /// Whether Option is physically down right now. Injectable so tests don't read the real keyboard.
    var isOptionKeyDown: () -> Bool = {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var serviceTapCounter = TapSequenceCounter()
    private var holdSessionActive = false
    /// The Option release can be lost: when the main thread stalls (e.g. activating the app a
    /// link was just opened in) macOS disables the tap and lets events pass unseen. A hold session
    /// that missed its release would stay on screen until the next ⌥Tab, so poll the real state too.
    private var holdReleaseWatchdog: Timer?
    private var toggleArmed = false
    /// A `KeyboardShortcuts.Recorder` is capturing keys. Stop claiming the toggle shortcut while
    /// it is, otherwise swallowing the combination makes it impossible to ever record over it.
    private var isRecordingShortcut = false
    private var settings: PickerActivationSettings = .defaultValue
    /// When true, hold/service callbacks run inline (unit tests). Production taps stay async.
    private var deliversCallbacksSynchronouslyForTesting = false

    deinit {
        stop()
    }

    func refresh(settings: PickerActivationSettings) {
        self.settings = settings
        deliversCallbacksSynchronouslyForTesting = false
        if settings.needsEventTap {
            start()
        } else {
            stop()
        }
    }

    /// Unit tests drive `handle` directly without installing a session event tap.
    func configureForDirectHandleTesting(settings: PickerActivationSettings) {
        stop()
        self.settings = settings
        deliversCallbacksSynchronouslyForTesting = true
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
        holdReleaseWatchdog?.invalidate()
        holdReleaseWatchdog = nil
        toggleArmed = false
        serviceTapCounter.reset()
    }

    /// Suspends toggle-shortcut capture while a shortcut recorder is on screen.
    func setRecordingShortcut(_ isRecording: Bool) {
        isRecordingShortcut = isRecording
        if isRecording {
            toggleArmed = false
        }
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            reconcileHoldWithPhysicalModifiers()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            if handleToggleShortcutDown(
                keyCode: keyCode,
                flags: event.flags,
                isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            ) {
                return nil
            }
            if handleHoldTab(keyCode: keyCode, flags: event.flags) {
                return nil
            }
            if handleServiceKeyDown(keyCode: keyCode, event: event) {
                return nil
            }
        case .keyUp:
            if handleToggleShortcutUp(keyCode: keyCode) {
                return nil
            }
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

    /// The shortcut we are currently entitled to claim, or `nil` when another mode owns
    /// activation or a recorder is capturing keys.
    private var activeToggleShortcut: PickerToggleShortcut? {
        guard !isRecordingShortcut, settings.mode == .toggleShortcut else { return nil }
        return settings.toggleShortcut
    }

    /// Fires on key down to match the Carbon `onKeyDown` fallback, so a repeated press steps
    /// immediately. Autorepeat is swallowed without firing, so holding the shortcut acts once and
    /// a held press reaches neither the focused app nor anyone else's hotkey.
    private func handleToggleShortcutDown(keyCode: UInt16, flags: CGEventFlags, isAutorepeat: Bool) -> Bool {
        guard let shortcut = activeToggleShortcut,
              shortcut.matches(keyCode: keyCode, flags: flags)
        else {
            return false
        }

        toggleArmed = true
        if !isAutorepeat {
            emitCallback { [onToggleShortcut] in
                onToggleShortcut?()
            }
        }
        return true
    }

    /// Swallows the key up of a claimed press. Only the key code is checked here — the modifier
    /// may already be released by the time the key up lands.
    private func handleToggleShortcutUp(keyCode: UInt16) -> Bool {
        guard toggleArmed, let shortcut = settings.toggleShortcut, keyCode == shortcut.keyCode else {
            return false
        }

        toggleArmed = false
        return true
    }

    private func handleHoldTab(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard settings.mode == .holdOptionTab else { return false }
        guard keyCode == UInt16(kVK_Tab), flags.contains(.maskAlternate) else { return false }
        guard flags.intersection([.maskCommand, .maskControl]).isEmpty else { return false }

        holdSessionActive = true
        startHoldReleaseWatchdog()
        let delta = flags.contains(.maskShift) ? -1 : 1
        emitCallback { [onHoldStep] in
            onHoldStep?(delta)
        }
        return true
    }

    private func handleHoldFlagsChanged(_ flags: CGEventFlags) {
        guard holdSessionActive, !flags.contains(.maskAlternate) else { return }
        endHoldSession()
    }

    /// Ends a hold session whose Option release was never delivered to the tap.
    func reconcileHoldWithPhysicalModifiers() {
        guard holdSessionActive, !isOptionKeyDown() else { return }
        endHoldSession()
    }

    private func startHoldReleaseWatchdog() {
        guard holdReleaseWatchdog == nil, !deliversCallbacksSynchronouslyForTesting else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.reconcileHoldWithPhysicalModifiers()
        }
        RunLoop.main.add(timer, forMode: .common)
        holdReleaseWatchdog = timer
    }

    private func endHoldSession() {
        holdSessionActive = false
        holdReleaseWatchdog?.invalidate()
        holdReleaseWatchdog = nil
        emitCallback { [onHoldRelease] in
            onHoldRelease?()
        }
    }

    private func emitCallback(_ body: @escaping () -> Void) {
        if deliversCallbacksSynchronouslyForTesting {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    private func handleServiceKeyDown(keyCode: UInt16, event: CGEvent) -> Bool {
        guard settings.serviceKey == .escape, keyCode == UInt16(kVK_Escape) else {
            return false
        }
        return registerServiceTap(event: event)
    }

    private func handleServiceFlagsChanged(keyCode: UInt16, event: CGEvent) -> Bool {
        guard settings.serviceKey == .capsLock, keyCode == UInt16(kVK_CapsLock) else {
            return false
        }
        return registerServiceTap(event: event)
    }

    private func registerServiceTap(event: CGEvent) -> Bool {
        // Pass autorepeat through so holding Escape/Caps Lock is not stolen while idle.
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }

        let now = ProcessInfo.processInfo.systemUptime
        let interval = settings.serviceTapInterval
        let inProgress = serviceTapCounter.isSequenceInProgress(at: now, interval: interval)

        let didComplete = serviceTapCounter.registerTap(
            at: now,
            requiredCount: settings.serviceTapCount.rawValue,
            interval: interval
        )
        if didComplete {
            emitCallback { [onServiceKeyTrigger] in
                onServiceKeyTrigger?()
            }
            return true
        }
        // Cold first tap of a multi-tap sequence: count it but pass the key through.
        // Follow-ups within the interval (and any tap during an active hold) are swallowed.
        return inProgress || holdSessionActive
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
