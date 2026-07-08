import AppKit
import os

@MainActor
protocol BrowserLauncherRunningApplication: AnyObject {
    var isActive: Bool { get }
    var isTerminated: Bool { get }
    var localizedName: String? { get }
    var processIdentifier: pid_t { get }

    @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool
    @discardableResult func unhide() -> Bool
}

extension NSRunningApplication: BrowserLauncherRunningApplication {}

@MainActor
final class BrowserLauncher {
    enum OpenMode {
        case normal
        case background
        case privateMode
    }

    struct Dependencies {
        var activateWindowTarget: @MainActor (AppWindowTarget) -> Bool
        var runningApplication: @MainActor (String) -> BrowserLauncherRunningApplication?
        var hasOpenWindows: @MainActor (String) -> Bool?
        var openURLs: @MainActor ([URL], URL, NSWorkspace.OpenConfiguration, @escaping @MainActor (BrowserLauncherRunningApplication?, Error?) -> Void) -> Void
        var sendReopenEvent: @MainActor (BrowserLauncherRunningApplication, String) -> Void
        var runExecutable: @MainActor (String, [String]) throws -> Void
        var schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void

        static let live = Dependencies(
            activateWindowTarget: { WindowEnumerator.activate($0) },
            runningApplication: { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first },
            hasOpenWindows: { WindowEnumerator.hasOpenWindows(bundleID: $0) },
            openURLs: { urls, appURL, configuration, completion in
                NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { app, error in
                    Task { @MainActor in completion(app, error) }
                }
            },
            sendReopenEvent: { app, displayName in
                let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
                let event = NSAppleEventDescriptor.appleEvent(
                    withEventClass: AEEventClass(kCoreEventClass),
                    eventID: AEEventID(kAEReopenApplication),
                    targetDescriptor: target,
                    returnID: AEReturnID(kAutoGenerateReturnID),
                    transactionID: AETransactionID(kAnyTransactionID)
                )
                do {
                    _ = try event.sendEvent(options: [.noReply, .canSwitchLayer], timeout: 1)
                } catch {
                    Log.apps.debug("Reopen event for \(displayName) failed: \(error.localizedDescription)")
                }
            },
            runExecutable: { executablePath, arguments in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                try process.run()
            },
            schedule: { delay, action in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    action()
                }
            }
        )
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func open(url: URL, with browser: InstalledBrowser, mode: OpenMode = .normal, profile: BrowserProfile? = nil) {
        open(urls: [url], with: browser, mode: mode, profile: profile)
    }

    func open(urls: [URL], with browser: InstalledBrowser, mode: OpenMode = .normal, profile: BrowserProfile? = nil) {
        guard !urls.isEmpty else { return }

        if let profile {
            openWithProfile(urls: urls, browser: browser, profile: profile, mode: mode)
            return
        }

        switch mode {
        case .normal:
            openNormal(urls: urls, browser: browser, inBackground: false)
        case .background:
            openNormal(urls: urls, browser: browser, inBackground: true)
        case .privateMode:
            openPrivate(urls: urls, browser: browser)
        }
    }

    @discardableResult
    func activate(browser: InstalledBrowser, profile: BrowserProfile? = nil, windowTarget: AppWindowTarget? = nil) -> Bool {
        if let windowTarget, dependencies.activateWindowTarget(windowTarget) {
            Log.browser.info("Activated \(browser.displayName) window '\(windowTarget.title)'")
            return true
        }

        if let profile {
            Log.browser.info("Ignoring profile '\(profile.displayName)' for manual activation of \(browser.displayName)")
        }

        return activateApplication(
            bundleID: browser.id,
            displayName: browser.displayName,
            reopenWindowlessWith: nil
        )
    }

    @discardableResult
    func activate(app: InstalledApp, windowTarget: AppWindowTarget? = nil) -> Bool {
        if let windowTarget, dependencies.activateWindowTarget(windowTarget) {
            Log.apps.info("Activated \(app.displayName) window '\(windowTarget.title)'")
            return true
        }

        return activateApplication(
            bundleID: app.id,
            displayName: app.displayName,
            reopenWindowlessWith: app.appURL
        )
    }

    private func openNormal(url: URL, browser: InstalledBrowser, inBackground: Bool) {
        openNormal(urls: [url], browser: browser, inBackground: inBackground)
    }

    private func openNormal(urls: [URL], browser: InstalledBrowser, inBackground: Bool) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !inBackground

        dependencies.openURLs(
            urls,
            browser.appURL,
            config
        ) { _, error in
            if let error {
                Log.browser.error("Failed to open \(urls.count) URL(s) with \(browser.displayName): \(error.localizedDescription)")
            } else {
                let mode = inBackground ? "background" : "foreground"
                Log.browser.info("Opened \(urls.count) URL(s) with \(browser.displayName) in \(mode)")
            }
        }
    }

    private func openPrivate(urls: [URL], browser: InstalledBrowser) {
        guard let args = browser.privateModeArgs else {
            // Fallback to normal open if no private mode support
            openNormal(urls: urls, browser: browser, inBackground: false)
            return
        }

        let executablePath = browser.appURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(executableName(for: browser))
            .path

        do {
            try dependencies.runExecutable(executablePath, args + urls.map(\.absoluteString))
            Log.browser.info("Opened \(urls.count) URL(s) with \(browser.displayName) in private mode")
            activateRunningApp(bundleID: browser.id)
        } catch {
            Log.browser.error("Failed to open private mode for \(browser.displayName): \(error.localizedDescription)")
            // Fallback to normal open
            openNormal(urls: urls, browser: browser, inBackground: false)
        }
    }

    private func openWithProfile(urls: [URL], browser: InstalledBrowser, profile: BrowserProfile, mode: OpenMode) {
        let executablePath = browser.appURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(executableName(for: browser))
            .path

        var args: [String] = []

        // Profile argument
        switch browser.profileType {
        case .chromium:
            args.append("--profile-directory=\(profile.directoryName)")
        case .firefox:
            args.append(contentsOf: ["-P", profile.displayName])
        case nil:
            break
        }

        // Private mode args
        if mode == .privateMode, let privateArgs = browser.privateModeArgs {
            args.append(contentsOf: privateArgs)
        }

        args.append(contentsOf: urls.map(\.absoluteString))

        do {
            try dependencies.runExecutable(executablePath, args)
            Log.browser.info("Opened \(urls.count) URL(s) with \(browser.displayName) profile '\(profile.displayName)'")
            activateRunningApp(bundleID: browser.id)
        } catch {
            Log.browser.error("Failed to open with profile for \(browser.displayName): \(error.localizedDescription)")
            openNormal(urls: urls, browser: browser, inBackground: false)
        }
    }

    // MARK: - Open in native app

    func open(url: URL, with app: InstalledApp) {
        openCandidateURLs(Self.candidateURLs(for: url, app: app)[...], originalURL: url, app: app)
    }

    private func openCandidateURLs(_ urls: ArraySlice<URL>, originalURL: URL, app: InstalledApp) {
        guard let url = urls.first else {
            Log.apps.warning("Could not open \(originalURL) with \(app.displayName); activating selected app as fallback")
            activate(app: app)
            return
        }

        openWithSelectedApp(url, app: app) { [weak self] _ in
            self?.openCandidateURLs(urls.dropFirst(), originalURL: originalURL, app: app)
        }
    }

    private func openWithSelectedApp(
        _ url: URL,
        app: InstalledApp,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        dependencies.openURLs(
            [url],
            app.appURL,
            config
        ) { openedApp, error in
            if let error {
                Log.apps.warning("Failed to open \(url) with \(app.displayName): \(error.localizedDescription)")
                Task { @MainActor in onFailure(error) }
                return
            }

            Log.apps.info("Opened \(url) with \(app.displayName)")
            Task { @MainActor in
                if let openedApp {
                    self.activateRunningApplication(openedApp, displayName: app.displayName)
                } else {
                    self.activateRunningApp(bundleID: app.id)
                }
            }
        }
    }

    static func candidateURLs(for url: URL, app: InstalledApp) -> [URL] {
        var urls: [URL] = []
        if !url.isFileURL,
           let definition = AppDefinition.registryByID[app.id],
           let deepURL = definition.convertURL?(url)
        {
            urls.append(deepURL)
        }

        urls.append(url)

        if !url.isFileURL,
           let scheme = app.urlSchemes.first,
           let schemeURL = fallbackSchemeURL(for: url, scheme: scheme),
           !urls.contains(schemeURL)
        {
            urls.append(schemeURL)
        }

        return urls
    }

    static func fallbackSchemeURL(for url: URL, scheme: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = scheme
        return components.url
    }

    // MARK: - Helpers

    private func activateApplication(bundleID: String, displayName: String, reopenWindowlessWith appURL: URL?) -> Bool {
        guard let runningApp = dependencies.runningApplication(bundleID) else {
            Log.apps.info("Skipping activation for \(displayName) because it is no longer running")
            return false
        }

        activateRunningApplication(runningApp, displayName: displayName)
        if let appURL, dependencies.hasOpenWindows(bundleID) == false {
            reopenWindowlessApplication(runningApp, appURL: appURL, displayName: displayName)
            return true
        }

        retryActivateIfActivationDidNotStick(
            runningApp,
            bundleID: bundleID,
            displayName: displayName,
            reopenWindowlessWith: appURL
        )
        return true
    }

    @discardableResult
    private func activateRunningApplication(_ app: BrowserLauncherRunningApplication, displayName: String) -> Bool {
        app.unhide()
        let options = strongActivationOptions
        let activated = app.activate(options: options)
        Log.apps.info("Activated \(displayName)")

        for delay in [0.15, 0.55] {
            dependencies.schedule(delay) { [weak app] in
                guard let app else { return }
                guard !app.isTerminated else { return }
                app.unhide()
                app.activate(options: options)
            }
        }

        return activated
    }

    private var strongActivationOptions: NSApplication.ActivationOptions {
        var options: NSApplication.ActivationOptions = [.activateAllWindows]
        if #unavailable(macOS 14.0) {
            options.insert(.activateIgnoringOtherApps)
        }
        return options
    }

    private func retryActivateIfActivationDidNotStick(
        _ runningApp: BrowserLauncherRunningApplication,
        bundleID: String,
        displayName: String,
        reopenWindowlessWith appURL: URL?
    ) {
        dependencies.schedule(0.35) { [weak self, weak runningApp] in
            guard let self, let runningApp else { return }
            guard !runningApp.isTerminated else { return }
            let hasOpenWindows = self.dependencies.hasOpenWindows(bundleID)
            guard !runningApp.isActive || hasOpenWindows == false else { return }
            if let appURL, hasOpenWindows == false {
                reopenWindowlessApplication(runningApp, appURL: appURL, displayName: displayName)
                return
            }
            activateRunningApplication(runningApp, displayName: displayName)
        }
    }

    private func reopenWindowlessApplication(
        _ app: BrowserLauncherRunningApplication,
        appURL: URL,
        displayName: String
    ) {
        Log.apps.info("Reopening \(displayName) because it is running without open windows at \(appURL.path)")
        dependencies.sendReopenEvent(app, displayName)
        activateRunningApplication(app, displayName: displayName)
    }

    private func activateRunningApp(bundleID: String) {
        if let app = dependencies.runningApplication(bundleID) {
            activateRunningApplication(app, displayName: app.localizedName ?? bundleID)
        } else {
            // Browser is still launching — wait briefly then activate
            dependencies.schedule(0.8) { [weak self] in
                guard let self,
                      let app = self.dependencies.runningApplication(bundleID)
                else { return }
                self.activateRunningApplication(app, displayName: app.localizedName ?? bundleID)
            }
        }
    }

    private func executableName(for browser: InstalledBrowser) -> String {
        // Read the executable name from the app bundle's Info.plist
        if let bundle = Bundle(url: browser.appURL),
           let execName = bundle.infoDictionary?["CFBundleExecutable"] as? String
        {
            return execName
        }
        // Fallback: derive from app name
        return browser.appURL.deletingPathExtension().lastPathComponent
    }
}
