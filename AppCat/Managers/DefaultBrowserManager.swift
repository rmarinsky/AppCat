import AppKit
import os
import UniformTypeIdentifiers

@MainActor
final class DefaultBrowserManager {
    func checkIsDefault(state: AppState) {
        let httpDefault = isCurrentAppDefault(for: "http")
        let httpsDefault = isCurrentAppDefault(for: "https")
        state.isDefaultWebFileHandler = isDefaultForWebFileTypes()

        if let httpDefault, let httpsDefault {
            state.isDefaultBrowser = httpDefault && httpsDefault
            return
        }

        if let fallback = httpDefault ?? httpsDefault {
            state.isDefaultBrowser = fallback
            return
        }

        state.isDefaultBrowser = false
    }

    func setAsDefault(state: AppState) {
        let bundleURL = Bundle.main.bundleURL
        state.isSettingDefaultBrowser = true

        // Run scheme updates sequentially to avoid overlapping system prompts.
        setDefaultApplication(
            at: bundleURL,
            schemes: ["http", "https"],
            index: 0,
            state: state
        ) { [weak self] in
            state.isSettingDefaultBrowser = false
            self?.checkIsDefault(state: state)
        }
    }

    func setAsDefaultForWebFiles(state: AppState) {
        let bundleURL = Bundle.main.bundleURL
        state.isSettingDefaultWebFileHandler = true

        setDefaultApplication(
            at: bundleURL,
            contentTypes: BrowserFileType.defaultHandlerContentTypes,
            index: 0,
            state: state
        ) { [weak self] in
            state.isSettingDefaultWebFileHandler = false
            self?.checkIsDefault(state: state)
        }
    }

    private func setDefaultApplication(
        at bundleURL: URL,
        schemes: [String],
        index: Int,
        state: AppState,
        completion: (() -> Void)? = nil
    ) {
        guard index < schemes.count else {
            if let completion {
                completion()
            } else {
                checkIsDefault(state: state)
            }
            return
        }

        let scheme = schemes[index]
        NSWorkspace.shared.setDefaultApplication(
            at: bundleURL,
            toOpenURLsWithScheme: scheme
        ) { error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    Log.app.error("Failed to set default browser (\(scheme)): \(error.localizedDescription)")
                    self.openDefaultBrowserSettings()
                }

                self.setDefaultApplication(
                    at: bundleURL,
                    schemes: schemes,
                    index: index + 1,
                    state: state,
                    completion: completion
                )
            }
        }
    }

    private func isCurrentAppDefault(for scheme: String) -> Bool? {
        guard let probeURL = URL(string: "\(scheme)://example.com"),
              let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL)
        else {
            return nil
        }

        if let currentBundleID = Bundle.main.bundleIdentifier,
           let defaultBundleID = Bundle(url: defaultAppURL)?.bundleIdentifier
        {
            return currentBundleID == defaultBundleID
        }

        return defaultAppURL.resolvingSymlinksInPath().path == Bundle.main.bundleURL.resolvingSymlinksInPath().path
    }

    private func setDefaultApplication(
        at bundleURL: URL,
        contentTypes: [UTType],
        index: Int,
        state: AppState,
        failures: [String] = [],
        completion: (() -> Void)? = nil
    ) {
        guard index < contentTypes.count else {
            if !failures.isEmpty {
                let sample = failures.prefix(8).joined(separator: ", ")
                Log.app.error("Failed to set \(failures.count) default file handlers: \(sample)")
            }
            checkIsDefault(state: state)
            completion?()
            return
        }

        let contentType = contentTypes[index]
        NSWorkspace.shared.setDefaultApplication(
            at: bundleURL,
            toOpen: contentType
        ) { error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var nextFailures = failures

                if let error {
                    Log.app.error("Failed to set default web file handler (\(contentType.identifier)): \(error.localizedDescription)")
                    nextFailures.append(contentType.identifier)
                }

                self.setDefaultApplication(
                    at: bundleURL,
                    contentTypes: contentTypes,
                    index: index + 1,
                    state: state,
                    failures: nextFailures,
                    completion: completion
                )
            }
        }
    }

    private func isDefaultForWebFileTypes() -> Bool {
        let contentTypes = BrowserFileType.defaultHandlerStatusContentTypes
        guard !contentTypes.isEmpty else { return false }

        return contentTypes.allSatisfy { contentType in
            guard let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: contentType) else {
                return false
            }

            if let currentBundleID = Bundle.main.bundleIdentifier,
               let defaultBundleID = Bundle(url: defaultAppURL)?.bundleIdentifier
            {
                return currentBundleID == defaultBundleID
            }

            return defaultAppURL.resolvingSymlinksInPath().path == Bundle.main.bundleURL.resolvingSymlinksInPath().path
        }
    }

    private func openDefaultBrowserSettings() {
        let fallbackURLs = [
            URL(string: "x-apple.systempreferences:com.apple.preference.general?DefaultWebBrowser"),
            URL(string: "x-apple.systempreferences:com.apple.settings.DefaultApps.extension"),
            URL(fileURLWithPath: "/System/Library/PreferencePanes/General.prefPane"),
        ]

        for url in fallbackURLs.compactMap({ $0 }) {
            if NSWorkspace.shared.open(url) {
                Log.app.info("Opened Default Browser settings: \(url.absoluteString)")
                return
            }
        }

        Log.app.error("Failed to open Default Browser settings fallback")
    }
}
