import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AppsSettingsView()
                .tabItem {
                    Label("Apps", systemImage: "square.grid.2x2")
                }

            RulesSettingsView()
                .tabItem {
                    Label("Rules", systemImage: "arrow.triangle.branch")
                }

            StatsSettingsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.xaxis")
                }

            HistorySettingsView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 620, height: 620)
        .background(SettingsWindowConfigurator().frame(width: 0, height: 0))
        .environment(\.locale, appState.appLanguage.locale)
    }
}

@MainActor
enum SettingsWindowManager {
    private static let settingsWindowIdentifier = NSUserInterfaceItemIdentifier("browsercat.settings.window")

    static func showSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)

        // SwiftUI creates/reuses the Settings window asynchronously.
        DispatchQueue.main.async {
            focusSettingsWindowIfAvailable()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            focusSettingsWindowIfAvailable()
        }
    }

    static func configure(window: NSWindow?) {
        guard let window else { return }

        window.identifier = settingsWindowIdentifier
        window.level = .floating

        var behavior = window.collectionBehavior
        behavior.insert(.moveToActiveSpace)
        behavior.insert(.fullScreenAuxiliary)
        window.collectionBehavior = behavior

        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private static func focusSettingsWindowIfAvailable() {
        guard let window = NSApp.windows.first(where: { $0.identifier == settingsWindowIdentifier }) else { return }
        configure(window: window)
    }
}

struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            SettingsWindowManager.configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        DispatchQueue.main.async {
            SettingsWindowManager.configure(window: nsView.window)
        }
    }
}
