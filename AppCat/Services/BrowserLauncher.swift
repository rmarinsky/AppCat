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

    func activate(browser: InstalledBrowser, profile: BrowserProfile? = nil) {
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
        // Step 1: Check if the app has a custom URL converter (like Browserosaurus convertUrl)
        if let definition = AppDefinition.registryByID[app.id],
           let convertURL = definition.convertURL,
           let deepURL = convertURL(url)
        {
            Log.apps.info("Using convertURL for \(app.displayName): \(url) → \(deepURL)")
            if NSWorkspace.shared.open(deepURL) {
                Log.apps.info("Opened \(deepURL) with \(app.displayName) via converted URL")
                return
            }
            Log.apps.warning("Converted URL open failed, falling back to direct open")
        }

        // Step 2: Open the HTTPS URL directly with the app (like `open -a "AppName" URL`)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: app.appURL,
            configuration: config
        ) { _, error in
            if let error {
                guard !url.isFileURL else {
                    Log.apps.error("Failed to open file with \(app.displayName): \(error.localizedDescription)")
                    return
                }
                Log.apps.warning("Direct open failed for \(app.displayName): \(error.localizedDescription), trying URL scheme")
                // Step 3: Fallback to generic URL scheme transformation
                Task { @MainActor in
                    self.openViaScheme(url: url, app: app)
                }
            } else {
                Log.apps.info("Opened \(url) with \(app.displayName)")
            }
        }
    }

    private func openViaScheme(url: URL, app: InstalledApp) {
        guard let scheme = app.urlSchemes.first,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            Log.apps.error("No URL scheme available for \(app.displayName)")
            return
        }

        components.scheme = scheme
        guard let deepURL = components.url else {
            Log.apps.error("Failed to construct deep link URL for \(app.displayName)")
            return
        }

        if NSWorkspace.shared.open(deepURL) {
            Log.apps.info("Opened \(deepURL) with \(app.displayName) via URL scheme")
        } else {
            Log.apps.error("Scheme open failed for \(app.displayName)")
        }
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
