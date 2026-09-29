#if DEV_BUILD
import AppKit

/// A passive DEV flight recorder. Never orders windows, activates apps, or consumes input.
@MainActor
final class PickerDiagnostics {
    private var journal = PickerDiagnosticJournal()
    private let queue = DispatchQueue(label: "appcat.picker-diagnostics", qos: .utility)
    private let store = PickerDiagnosticStore(directory: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AppCat DEV/PickerDiagnostics", isDirectory: true))
    private var timer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var generation = UUID()
    private var sampleInFlight = false
    private var stopAt: TimeInterval?
    private var lastSave: TimeInterval = 0
    private var lastState: PickerDiagnosticSnapshot?
    private var lastHeartbeat: TimeInterval = 0
    private var gesture: UUID?
    private var lastDownTimestamp: TimeInterval?
    private var identities: [String: Int] = [:]
    private var renderedItems: [Int] = []
    private(set) var session: UUID?
    var snapshot: (() -> PickerDiagnosticSnapshot)?

    func token(for identity: String) -> Int {
        if let token = identities[identity] { return token }
        guard identities.count < 4096 else { return 0 }
        let token = identities.count + 1
        identities[identity] = token
        return token
    }

    func begin(_ session: UUID) {
        self.session = session
        generation = UUID()
        stopAt = nil
        gesture = nil
        lastDownTimestamp = nil
        if timer == nil {
            installObservers()
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        record("session.begin")
    }

    func closed() {
        generation = UUID() // Discard samples captured before the close.
        stopAt = ProcessInfo.processInfo.systemUptime + 5
        record("session.closed")
        save(force: true)
    }

    func flush() { save(force: true) }

    func record(_ name: String, detail: String = "", session: UUID? = nil) {
        let now = ProcessInfo.processInfo.systemUptime
        journal.append(name, detail: detail, session: session ?? self.session,
                       gesture: gesture, state: currentState(), at: now)
        save()
    }

    func displayed(_ ids: [String]) {
        let tokens = ids.map { token(for: $0) }
        guard tokens != renderedItems else { return }
        renderedItems = tokens
        record("view.itemsChanged")
    }

    func input(_ event: NSEvent, origin: String) {
        guard timer != nil else { return }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if lastDownTimestamp != event.timestamp {
                gesture = UUID()
                lastDownTimestamp = event.timestamp
            }
        }
        let number = event.type == .flagsChanged ? -1 : event.eventNumber
        record("input.\(origin)", detail: "type=\(event.type.rawValue) event=\(number) timestamp=\(event.timestamp) option=\(event.modifierFlags.contains(.option)) window=\(event.windowNumber)")
    }

    private func currentState() -> PickerDiagnosticSnapshot? {
        guard var state = snapshot?() else { return nil }
        state.observedSession = session
        state.renderedItems = renderedItems
        return state
    }

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        if let stopAt, now >= stopAt {
            record("observation.end")
            save(force: true)
            stop()
            return
        }
        guard !sampleInFlight, let state = currentState(), state.window > 0 else { return }
        sampleInFlight = true
        let observedGeneration = generation
        queue.async { [weak self] in
            // Query this window only; do not inspect other apps' titles or contents.
            let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(state.window)) as? [[String: Any]]
            let visible = rows.map { rows in
                rows.contains { ($0[kCGWindowNumber as String] as? Int) == state.window
                    && ($0[kCGWindowIsOnscreen as String] as? Bool) == true }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sampleInFlight = false
                guard observedGeneration == self.generation else { return }
                var sample = state
                sample.serverVisible = visible
                let time = ProcessInfo.processInfo.systemUptime
                if sample != self.lastState || time - self.lastHeartbeat >= 1 {
                    self.journal.append("window.sample", session: sample.observedSession,
                                        gesture: self.gesture, state: sample, at: time)
                    self.lastState = sample
                    self.lastHeartbeat = time
                }
                if let reason = self.journal.anomaly(in: sample, at: time) {
                    self.journal.append("anomaly.\(reason)", session: sample.observedSession,
                                        gesture: self.gesture, state: sample, at: time)
                    Log.picker.error("[picker-diagnostics] Incident: \(reason, privacy: .public)")
                    self.save(force: true, reason: reason)
                } else {
                    self.save()
                }
            }
        }
    }

    private func save(force: Bool = false, reason: String? = nil) {
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastSave >= 1 else { return }
        lastSave = now
        let events = journal.events
        let store = store
        queue.async {
            do { try store.write(events, reason: reason) }
            catch {
                // Do not log error descriptions, which can contain filesystem/user names.
                Log.picker.error("[picker-diagnostics] File write failed code=\((error as NSError).code)")
            }
        }
    }

    private func installObservers() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .flagsChanged]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.input(event, origin: "local")
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.input(event, origin: "global")
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                let token = self.token(for: app.bundleIdentifier ?? "pid:\(app.processIdentifier)")
                self.record("workspace.activated", detail: "target=\(token) pid=\(app.processIdentifier)")
            }
        }
    }

    private func stop() {
        generation = UUID()
        timer?.invalidate()
        timer = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        localMonitor = nil
        globalMonitor = nil
        activationObserver = nil
    }
}
#endif
