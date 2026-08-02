import AppKit

@MainActor
final class AppActivityMonitor {
    private weak var appState: AppState?
    private var observers: [NSObjectProtocol] = []
    private var windowRefreshTask: Task<Void, Never>?
    private var windowEnumerationTask: Task<Void, Never>?
    private var pendingWindowSnapshotCompletions: [@MainActor () -> Void] = []
    private var windowPollingTask: Task<Void, Never>?
    private var appListRefreshTask: Task<Void, Never>?
    private var isStopped = false
    private let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    private let windowRefreshDebounce: TimeInterval = 0.25
    // Backstop poll; real changes arrive via workspace notifications, so this can be coarse.
    private let windowPollInterval: UInt64
    private let enumerateWindows: @Sendable () -> [String: [AppWindowTarget]]
    /// Coalesces installed-app rescans triggered by app launch/termination bursts.
    private let appListRefreshDebounce: UInt64 = 2_000_000_000
    /// Fired (debounced) when a running app launches or terminates — the installed-app list
    /// may be stale (e.g. a freshly installed app was just started for the first time).
    var onAppListChanged: (@MainActor () -> Void)?

    /// Fired when a live window snapshot lands while a toggle/service picker session can consume it.
    var onManualPickerNeedsRefresh: (@MainActor () -> Void)?

    init(
        appState: AppState,
        windowPollInterval: UInt64 = 5_000_000_000,
        enumerateWindows: @escaping @Sendable () -> [String: [AppWindowTarget]] = {
            WindowEnumerator.isTrusted ? WindowEnumerator.runningWindows() : [:]
        }
    ) {
        self.appState = appState
        self.windowPollInterval = windowPollInterval
        self.enumerateWindows = enumerateWindows
    }

    func start() {
        guard observers.isEmpty else { return }
        isStopped = false

        refreshRunningApplications()
        scheduleWindowRefresh(after: 0.15)
        observeWorkspaceChanges()
        startWindowPolling()
    }

    func stop() {
        isStopped = true
        for observer in observers {
            workspaceNotificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        windowRefreshTask?.cancel()
        windowRefreshTask = nil
        windowEnumerationTask?.cancel()
        windowEnumerationTask = nil
        pendingWindowSnapshotCompletions.removeAll()
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
        requestWindowSnapshot(priority: .userInitiated)
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
                guard !Task.isCancelled else { return }
                self?.refreshRunningApplications()
                self?.scheduleWindowRefresh(after: 0)
            }
        }
    }

    private func scheduleWindowRefresh(after delay: TimeInterval) {
        // Hold/link sessions freeze their snapshot; toggle/service keep consuming live refreshes.
        if appState?.isPickerSessionActive == true,
           appState?.pickerInvocationSource.refreshesLiveSnapshot != true
        {
            return
        }

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
        guard !isStopped, appState != nil else { return }
        if let completion {
            pendingWindowSnapshotCompletions.append(completion)
        }
        guard windowEnumerationTask == nil else { return }
        let enumerateWindows = self.enumerateWindows

        // AX enumeration is synchronous cross-process IPC. Keep exactly one pass in flight;
        // cancellation cannot stop that IPC, so replacement tasks only create overlap.
        windowEnumerationTask = Task.detached(priority: priority) { [weak self] in
            let windows = enumerateWindows()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.windowEnumerationTask = nil
                guard !self.isStopped, let appState = self.appState else {
                    self.pendingWindowSnapshotCompletions.removeAll()
                    return
                }
                appState.runningWindowsByAppID = windows
                appState.appWindowActivityUpdatedAt = Date()
                let completions = self.pendingWindowSnapshotCompletions
                self.pendingWindowSnapshotCompletions.removeAll()
                if appState.isPickerSessionActive,
                   appState.pickerInvocationSource.refreshesLiveSnapshot
                {
                    self.onManualPickerNeedsRefresh?()
                }
                completions.forEach { $0() }
            }
        }
    }
}
