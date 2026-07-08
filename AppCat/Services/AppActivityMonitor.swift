import AppKit

@MainActor
final class AppActivityMonitor {
    private weak var appState: AppState?
    private var observers: [NSObjectProtocol] = []
    private var windowRefreshTask: Task<Void, Never>?
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
        windowPollingTask?.cancel()
        windowPollingTask = nil
        appListRefreshTask?.cancel()
        appListRefreshTask = nil
    }

    func refreshRunningApplications() {
        guard let appState else { return }

        let runningApplications = NSWorkspace.shared.runningApplications
        appState.runningAppBundleIDs = Set(runningApplications.compactMap(\.bundleIdentifier))
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

        appState.runningWindowsByAppID = WindowEnumerator.isTrusted ? WindowEnumerator.runningWindows() : [:]
        appState.appWindowActivityUpdatedAt = Date()
    }

    /// One-shot detached enumeration for a picker that is already on screen. Deliberately
    /// bypasses `scheduleWindowRefresh`'s isPickerVisible guard: the switcher opens instantly
    /// from the cached snapshot and requests this live pass to correct the list in place.
    /// `completion` runs on the main actor after the fresh windows are published.
    func refreshWindowsForVisiblePicker(completion: @escaping @MainActor () -> Void) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let windows = WindowEnumerator.isTrusted ? WindowEnumerator.runningWindows() : [:]
            await MainActor.run { [weak self] in
                guard let self, let appState = self.appState else { return }
                appState.runningWindowsByAppID = windows
                appState.appWindowActivityUpdatedAt = Date()
                completion()
            }
        }
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
        guard appState != nil else { return }

        // AX enumeration is pure cross-process IPC; run it off the main actor so an unresponsive
        // target app cannot stall the main thread (and the picker). Hop back only to publish.
        Task.detached(priority: .utility) { [weak self] in
            let windows = WindowEnumerator.isTrusted ? WindowEnumerator.runningWindows() : [:]
            await MainActor.run { [weak self] in
                guard let self, let appState = self.appState else { return }
                appState.runningWindowsByAppID = windows
                appState.appWindowActivityUpdatedAt = Date()
            }
        }
    }
}
