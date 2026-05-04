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
        if let profile {
            openWithProfile(url: url, browser: browser, profile: profile, mode: mode)
            return
        }

        switch mode {
        case .normal:
            openNormal(url: url, browser: browser, inBackground: false)
        case .background:
            openNormal(url: url, browser: browser, inBackground: true)
        case .privateMode:
            openPrivate(url: url, browser: browser)
        }
    }

    private func openNormal(url: URL, browser: InstalledBrowser, inBackground: Bool) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = !inBackground

        NSWorkspace.shared.open(
            [url],
            withApplicationAt: browser.appURL,
            configuration: config
        ) { _, error in
            if let error {
                Log.browser.error("Failed to open \(url) with \(browser.displayName): \(error.localizedDescription)")
            } else {
                let mode = inBackground ? "background" : "foreground"
                Log.browser.info("Opened \(url) with \(browser.displayName) in \(mode)")
            }
        }
    }

    private func openPrivate(url: URL, browser: InstalledBrowser) {
        guard let args = browser.privateModeArgs else {
            // Fallback to normal open if no private mode support
            openNormal(url: url, browser: browser, inBackground: false)
            return
        }

        let executablePath = browser.appURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(executableName(for: browser))
            .path

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args + [url.absoluteString]

        do {
            try process.run()
            Log.browser.info("Opened \(url) with \(browser.displayName) in private mode")
            activateRunningApp(bundleID: browser.id)
        } catch {
            Log.browser.error("Failed to open private mode for \(browser.displayName): \(error.localizedDescription)")
            // Fallback to normal open
            openNormal(url: url, browser: browser, inBackground: false)
        }
    }

    private func openWithProfile(url: URL, browser: InstalledBrowser, profile: BrowserProfile, mode: OpenMode) {
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

        args.append(url.absoluteString)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args

        do {
            try process.run()
            Log.browser.info("Opened \(url) with \(browser.displayName) profile '\(profile.displayName)'")
            activateRunningApp(bundleID: browser.id)
        } catch {
            Log.browser.error("Failed to open with profile for \(browser.displayName): \(error.localizedDescription)")
            openNormal(url: url, browser: browser, inBackground: false)
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

    private func activateRunningApp(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let app = running.first {
            app.activate()
        } else {
            // Browser is still launching — wait briefly then activate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                    .first?.activate()
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
