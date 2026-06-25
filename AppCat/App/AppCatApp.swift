import AppKit
import SwiftUI

@main
struct AppCatApp: App {
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
    }
}

private struct MenuBarIconView: View {
    var body: some View {
        Image(systemName: "cat.fill")
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel("AppCat")
    }
}
