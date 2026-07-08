import AppKit
import os

@MainActor
final class BrowserLauncher {
    enum OpenMode {
        case normal
        case background
        case privateMode
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

    func activate(browser: InstalledBrowser, profile: BrowserProfile? = nil, windowTarget: AppWindowTarget? = nil) {
        if let windowTarget, WindowEnumerator.activate(windowTarget) {
            Log.browser.info("Activated \(browser.displayName) window '\(windowTarget.title)'")
            return
        }

        if let profile {
            openProfileWindow(browser: browser, profile: profile)
            return
        }

        activateApplication(
            bundleID: browser.id,
            appURL: browser.appURL,
            displayName: browser.displayName
        )
    }

    func activate(app: InstalledApp, windowTarget: AppWindowTarget? = nil) {
        if let windowTarget, WindowEnumerator.activate(windowTarget) {
            Log.apps.info("Activated \(app.displayName) window '\(windowTarget.title)'")
            return
        }

        activateApplication(
            bundleID: app.id,
            appURL: app.appURL,
            displayName: app.displayName
        )
    }

    private func openNormal(url: URL, browser: InstalledBrowser, inBackground: Bool) {
        openNormal(urls: [url], browser: browser, inBackground: inBackground)
    }

    private func openNormal(urls: [URL], browser: InstalledBrowser, inBackground: Bool) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !inBackground

        NSWorkspace.shared.open(
            urls,
            withApplicationAt: browser.appURL,
            configuration: config
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args + urls.map(\.absoluteString)

        do {
            try process.run()
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args

        do {
            try process.run()
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

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: app.appURL,
            configuration: config
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

    private func activateApplication(bundleID: String, appURL: URL, displayName: String) {
        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            activateRunningApplication(runningApp, displayName: displayName)
            if WindowEnumerator.hasOpenWindows(bundleID: bundleID) == false {
                reopenApplication(bundleID: bundleID, appURL: appURL, displayName: displayName)
                return
            }
            retryLaunchIfActivationDidNotStick(
                runningApp,
                bundleID: bundleID,
                appURL: appURL,
                displayName: displayName
            )
            return
        }

        launchApplication(bundleID: bundleID, appURL: appURL, displayName: displayName)
    }

    private func reopenApplication(bundleID: String, appURL: URL, displayName: String) {
        Log.apps.info("Reopening \(displayName) because it is running without open windows")
        launchApplication(bundleID: bundleID, appURL: appURL, displayName: displayName)
    }

    private func launchApplication(bundleID: String, appURL: URL, displayName: String) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { launchedApp, error in
            if let error {
                Log.apps.error("Failed to activate \(displayName): \(error.localizedDescription)")
            } else {
                Log.apps.info("Launched \(displayName)")
                Task { @MainActor in
                    if let launchedApp {
                        self.activateRunningApplication(launchedApp, displayName: displayName)
                        self.sendReopenEvent(to: launchedApp, displayName: displayName)
                    } else if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                        self.activateRunningApplication(runningApp, displayName: displayName)
                        self.sendReopenEvent(to: runningApp, displayName: displayName)
                    }
                }
            }
        }
    }

    @discardableResult
    private func activateRunningApplication(_ app: NSRunningApplication, displayName: String) -> Bool {
        app.unhide()
        let options = strongActivationOptions
        let activated = app.activate(options: options)
        Log.apps.info("Activated \(displayName)")

        for delay in [0.15, 0.55] {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
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

    private func retryLaunchIfActivationDidNotStick(
        _ runningApp: NSRunningApplication,
        bundleID: String,
        appURL: URL,
        displayName: String
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !runningApp.isTerminated else { return }
            let hasOpenWindows = WindowEnumerator.hasOpenWindows(bundleID: bundleID)
            guard !runningApp.isActive || hasOpenWindows == false else { return }
            if hasOpenWindows == false {
                reopenApplication(bundleID: bundleID, appURL: appURL, displayName: displayName)
            } else {
                launchApplication(bundleID: bundleID, appURL: appURL, displayName: displayName)
            }
        }
    }

    private func sendReopenEvent(to app: NSRunningApplication, displayName: String) {
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
    }

    private func openProfileWindow(browser: InstalledBrowser, profile: BrowserProfile) {
        guard browser.profileType != nil else {
            activate(browser: browser)
            return
        }

        let executablePath = browser.appURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(executableName(for: browser))
            .path

        var args: [String] = []
        switch browser.profileType {
        case .chromium:
            args.append("--profile-directory=\(profile.directoryName)")
        case .firefox:
            args.append(contentsOf: ["-P", profile.displayName])
        case nil:
            break
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args

        do {
            try process.run()
            Log.browser.info("Activated \(browser.displayName) profile '\(profile.displayName)'")
            activateRunningApp(bundleID: browser.id)
        } catch {
            Log.browser.error("Failed to activate profile for \(browser.displayName): \(error.localizedDescription)")
            activate(browser: browser)
        }
    }

    private func activateRunningApp(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let app = running.first {
            activateRunningApplication(app, displayName: app.localizedName ?? bundleID)
        } else {
            // Browser is still launching — wait briefly then activate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
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
