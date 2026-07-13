import AppKit

@MainActor
final class AppActivityMonitor {
    private weak var appState: AppState?
    private var observers: [NSObjectProtocol] = []
    private var windowRefreshTask: Task<Void, Never>?
    private var windowEnumerationTask: Task<Void, Never>?
    private var windowSnapshotRequestID = 0
    private var windowPollingTask: Task<Void, Never>?
    private var appListRefreshTask: Task<Void, Never>?
    private let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    private let windowRefreshDebounce: TimeInterval = 0.25
    // Backstop poll; real changes arrive via workspace notifications, so this can be coarse.
    private let windowPollInterval: UInt64 = 5_000_000_000
    /// Coalesces installed-app rescans triggered by app launch/termination bursts.
    private let appListRefreshDebounce: UInt64 = 2_000_000_000
    /// Fired (debounced) when a running app launches or terminates — the installed-app list
    /// may be stale (e.g. a freshly installed app was just started for the first time).
    var onAppListChanged: (@MainActor () -> Void)?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        guard observers.isEmpty else { return }

        refreshRunningApplications()
        scheduleWindowRefresh(after: 0.15)
        observeWorkspaceChanges()
        startWindowPolling()
    }

    func stop() {
        for observer in observers {
            workspaceNotificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        windowEnumerationTask?.cancel()
        windowEnumerationTask = nil
        windowPollingTask?.cancel()
        windowPollingTask = nil
        appListRefreshTask?.cancel()
        appListRefreshTask = nil
    }

    func refreshRunningApplications() {
        guard let appState else { return }

        let runningApplications = NSWorkspace.shared.runningApplications
        appState.runningAppBundleIDs = Set(runningApplications.compactMap(\.bundleIdentifier))
        let mainBundleID = Bundle.main.bundleIdentifier
        appState.runningAppsByBundleID = Dictionary(
            runningApplications.compactMap { application -> (String, InstalledApp)? in
                guard let bundleID = application.bundleIdentifier,
                      bundleID != mainBundleID,
                      let appURL = application.bundleURL
                else { return nil }

                let fallbackName = appURL.deletingPathExtension().lastPathComponent
                let icon = application.icon ?? NSWorkspace.shared.icon(forFile: appURL.path)
                return (
                    bundleID,
                    InstalledApp(
                        id: bundleID,
                        displayName: application.localizedName ?? fallbackName,
                        appURL: appURL,
                        urlSchemes: [],
                        hostPatterns: [],
                        isVisible: true,
                        sortOrder: 0,
                        isSystemApp: bundleID.hasPrefix("com.apple.") || appURL.path.hasPrefix("/System/"),
                        icon: icon
                    )
                )
            },
            uniquingKeysWith: { current, _ in current }
        )
        // `.regular` apps own a Dock tile + menu bar; `.accessory`/`.prohibited` are menu-bar and
        // background utilities the switcher hides unless the user opts in.
        appState.regularAppBundleIDs = Set(
            runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier)
        )
        appState.frontmostAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        appState.appActivityUpdatedAt = Date()
    }

    func refreshWindowSnapshotForPicker() {
        guard let appState else { return }

        windowSnapshotRequestID += 1
        windowEnumerationTask?.cancel()
        windowEnumerationTask = nil
        appState.runningWindowsByAppID = WindowEnumerator.isTrusted ? WindowEnumerator.runningWindows() : [:]
        appState.appWindowActivityUpdatedAt = Date()
    }

    /// Fetch the authoritative window list off the main actor before showing a toggle/service
    /// picker. This avoids painting an old cache first and adding newly opened windows later.
    func refreshWindowsForPickerPresentation(completion: @escaping @MainActor () -> Void) {
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        requestWindowSnapshot(priority: .userInitiated, completion: completion)
    }

    private func observeWorkspaceChanges() {
        observe(NSWorkspace.didLaunchApplicationNotification)
        observe(NSWorkspace.didTerminateApplicationNotification)
        observe(NSWorkspace.didActivateApplicationNotification)
        observe(NSWorkspace.didHideApplicationNotification)
        observe(NSWorkspace.didUnhideApplicationNotification)
        observe(NSWorkspace.activeSpaceDidChangeNotification)
    }

    private func observe(_ notificationName: Notification.Name) {
        let observer = workspaceNotificationCenter.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let activatedBundleID = activatedApp?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.handleWorkspaceChange(notificationName, activatedBundleID: activatedBundleID)
            }
        }
        observers.append(observer)
    }

    private func handleWorkspaceChange(_ notificationName: Notification.Name, activatedBundleID: String?) {
        // Ignore AppCat's own activation (e.g. when it activates to show the picker). Otherwise
        // every picker presentation would kick off an AX enumeration on the present frame — and
        // AppCat shouldn't rank itself in its own switcher.
        if activatedBundleID == Bundle.main.bundleIdentifier {
            return
        }
        // Tally real usage: count an app each time it becomes frontmost. This is the switcher's
        // frequency + recency signal.
        if notificationName == NSWorkspace.didActivateApplicationNotification, let activatedBundleID {
            appState?.recordAppActivation(activatedBundleID)
        }
        if notificationName == NSWorkspace.didLaunchApplicationNotification
            || notificationName == NSWorkspace.didTerminateApplicationNotification
        {
            scheduleAppListRefresh()
        }
        refreshRunningApplications()
        scheduleWindowRefresh(after: windowRefreshDebounce)
    }

    private func scheduleAppListRefresh() {
        appListRefreshTask?.cancel()
        let debounce = appListRefreshDebounce
        appListRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled else { return }
            self?.onAppListChanged?()
            self?.appListRefreshTask = nil
        }
    }

    private func startWindowPolling() {
        windowPollingTask?.cancel()
        let pollInterval = windowPollInterval
        windowPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pollInterval)
                self?.refreshRunningApplications()
                self?.scheduleWindowRefresh(after: 0)
            }
        }
    }

    private func scheduleWindowRefresh(after delay: TimeInterval) {
        // The picker renders from a snapshot seeded at show time, not from live
        // `runningWindowsByAppID`, so there is no consumer for a refresh while it is visible —
        // skip it to avoid churn during picker interaction.
        if appState?.isPickerVisible == true { return }

        windowRefreshTask?.cancel()
        windowRefreshTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            self?.refreshWindowSnapshot()
        }
    }

    private func refreshWindowSnapshot() {
        requestWindowSnapshot(priority: .utility)
    }

    private func requestWindowSnapshot(
        priority: TaskPriority,
        completion: (@MainActor () -> Void)? = nil
    ) {
        guard appState != nil else { return }

        windowSnapshotRequestID += 1
        let requestID = windowSnapshotRequestID
        windowEnumerationTask?.cancel()

        // AX enumeration is pure cross-process IPC; run it off the main actor so an unresponsive
        // target app cannot stall the main thread. The request id also prevents an older detached
        // pass from overwriting a newer picker snapshot if cancellation arrives too late.
        windowEnumerationTask = Task.detached(priority: priority) { [weak self] in
            let windows = WindowEnumerator.isTrusted ? WindowEnumerator.runningWindows() : [:]
            await MainActor.run { [weak self] in
                guard let self,
                      self.windowSnapshotRequestID == requestID,
                      let appState = self.appState
                else { return }
                appState.runningWindowsByAppID = windows
                appState.appWindowActivityUpdatedAt = Date()
                self.windowEnumerationTask = nil
                completion?()
            }
        }
    }
}
