import AppKit
import os

@MainActor
final class DefaultBrowserManager {
    func checkIsDefault(state: AppState) {
        let httpDefault = isCurrentAppDefault(for: "http")
        let httpsDefault = isCurrentAppDefault(for: "https")

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
        guard let bundleURL = Bundle.main.bundleURL as URL? else { return }

        // Run scheme updates sequentially to avoid overlapping system prompts.
        setDefaultApplication(
            at: bundleURL,
            schemes: ["http", "https"],
            index: 0,
            state: state
        )
    }

    private func setDefaultApplication(at bundleURL: URL, schemes: [String], index: Int, state: AppState) {
        guard index < schemes.count else {
            checkIsDefault(state: state)
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
                    self.checkIsDefault(state: state)
                    return
                }

                self.setDefaultApplication(
                    at: bundleURL,
                    schemes: schemes,
                    index: index + 1,
                    state: state
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
           let defaultBundleID = Bundle(url: defaultAppURL)?.bundleIdentifier {
            return currentBundleID == defaultBundleID
        }

        return defaultAppURL.resolvingSymlinksInPath().path == Bundle.main.bundleURL.resolvingSymlinksInPath().path
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
