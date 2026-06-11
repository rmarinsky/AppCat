import AppKit
import SwiftUI

@main
struct BrowserCatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                onReopenURL: { urlString in appDelegate.pickerCoordinator.reopenURL(urlString, state: appDelegate.appState) },
                onCheckForUpdates: { appDelegate.updaterManager.checkForUpdates() }
            )
            .environment(appDelegate.appState)
            .environment(\.statsManager, appDelegate.statsManager)
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.menu)

        Window("BrowserCat", id: "main-window") {
            MainWindowView()
                .environment(appDelegate.appState)
                .environment(\.browserManager, appDelegate.browserManager)
                .environment(\.appManager, appDelegate.appManager)
                .environment(\.urlRulesManager, appDelegate.urlRulesManager)
                .environment(\.defaultBrowserManager, appDelegate.defaultBrowserManager)
                .environment(\.pickerCoordinator, appDelegate.pickerCoordinator)
                .environment(\.historyManager, appDelegate.historyManager)
                .environment(\.suggestionsManager, appDelegate.suggestionsManager)
                .environment(\.statsManager, appDelegate.statsManager)
        }
        .defaultSize(width: 1000, height: 680)
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarIconView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "cat.fill")
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel("BrowserCat")
            .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
                openWindow(id: "main-window")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

extension Notification.Name {
    /// Posted by AppDelegate to ask the always-alive menu-bar label to open the main window.
    static let openMainWindow = Notification.Name("ua.com.rmarinsky.browsercat.openMainWindow")
}
