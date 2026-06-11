import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.locale, appState.appLanguage.locale)
        .background(MainWindowSetup())
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.mainWindowSection {
        case .overview:
            OverviewView()
        case .history:
            HistorySettingsView()
        case .suggestions:
            SuggestionsView()
        case .settingsGeneral:
            GeneralSettingsView()
        case .settingsBrowsers:
            AppsSettingsView()
        case .settingsRules:
            RulesSettingsView()
        case .settingsShortcuts:
            AppsSettingsView()
        case .settingsAccount:
            AboutSettingsView()
        }
    }
}

// MARK: - One-time window setup

private struct MainWindowSetup: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let win = view.window else { return }
            win.setFrameAutosaveName("BrowserCatMainWindow")
            win.minSize = NSSize(width: 820, height: 580)
            var bh = win.collectionBehavior
            bh.insert(.moveToActiveSpace)
            bh.insert(.fullScreenPrimary)
            win.collectionBehavior = bh
        }
        return view
    }

    func updateNSView(_: NSView, context: Context) {}
}
