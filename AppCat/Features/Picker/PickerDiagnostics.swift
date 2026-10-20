#if DEV_BUILD
    import AppKit

    /// A passive DEV flight recorder. Never orders windows, activates apps, or consumes input.
    @MainActor
    final class PickerDiagnostics {
        private var journal = PickerDiagnosticJournal()
        private let queue: DispatchQueue
        private let store: PickerDiagnosticStore
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
        private var lastDownTimestamp: TimeInterval?
        private var identities: [String: Int] = [:]
        private var renderedItems: [Int] = []
        var context: PickerDiagnosticContext {
            journal.context
        }

        var snapshot: (() -> PickerDiagnosticSnapshot)?

        init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AppCat DEV/PickerDiagnostics", isDirectory: true),
             queue: DispatchQueue = DispatchQueue(label: "appcat.picker-diagnostics", qos: .utility))
        {
            store = PickerDiagnosticStore(directory: directory)
            self.queue = queue
        }

        func token(for identity: String) -> Int {
            if let token = identities[identity] { return token }
            guard identities.count < 4096 else { return 0 }
            let token = identities.count + 1
            identities[identity] = token
            return token
        }

        func begin(_ session: UUID) {
            journal.context = .init(session: session)
            generation = UUID()
            stopAt = nil
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

        func flush() {
            save(force: true)
        }

        func record(_ name: String, detail: String = "", context: PickerDiagnosticContext? = nil) {
            let now = ProcessInfo.processInfo.systemUptime
            // Attribution belongs to the request; state describes the panel at completion time.
            // Its observedSession can legitimately differ after another session replaces the request.
            journal.append(name, detail: detail, context: context, state: currentState(), at: now)
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
                    journal.context.gesture = UUID()
                    lastDownTimestamp = event.timestamp
                }
            }
            let number = event.type == .flagsChanged ? -1 : event.eventNumber
            var position = ""
            if event.type != .flagsChanged {
                let point = event.locationInWindow
                let screenPoint = event.window?.convertPoint(toScreen: point) ?? point
                position = " hasWindow=\(event.window != nil) x=\(point.x) y=\(point.y) screenX=\(screenPoint.x) screenY=\(screenPoint.y)"
            }
            record("input.\(origin)", detail: "type=\(event.type.rawValue) event=\(number) timestamp=\(event.timestamp) option=\(event.modifierFlags.contains(.option)) window=\(event.windowNumber)\(position)")
        }

        private func currentState() -> PickerDiagnosticSnapshot? {
            guard var state = snapshot?() else { return nil }
            state.observedSession = context.session
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
            let observedContext = context
            queue.async { [weak self] in
                // Query this window only; do not inspect other apps' titles or contents.
                let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(state.window)) as? [[String: Any]]
                let visible = rows.map { rows in
                    rows.contains { ($0[kCGWindowNumber as String] as? Int) == state.window
                        && ($0[kCGWindowIsOnscreen as String] as? Bool) == true
                    }
                }
                let queriedAt = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    sampleInFlight = false
                    guard observedGeneration == generation else { return }
                    var sample = state
                    sample.serverVisible = visible
                    let time = ProcessInfo.processInfo.systemUptime
                    if sample != lastState || time - lastHeartbeat >= 1 {
                        journal.append("window.sample",
                                       detail: "capturedAt=\(now) queriedAt=\(queriedAt) deliveredAt=\(time)",
                                       context: observedContext, state: sample, at: time)
                        lastState = sample
                        lastHeartbeat = time
                    }
                    guard let currentState = currentState() else { return }
                    if let reason = journal.sampledAnomaly(in: sample, currentState: currentState,
                                                           capturedAt: now, queriedAt: queriedAt, deliveredAt: time)
                    {
                        journal.append("anomaly.\(reason)", context: observedContext, state: sample, at: time)
                        Log.picker.error("[picker-diagnostics] Incident: \(reason, privacy: .public)")
                        save(force: true, reason: reason)
                    } else {
                        save()
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
