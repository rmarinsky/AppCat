import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 240)
                .background(Color("SurfaceSidebar"))

            Rectangle()
                .fill(Color("HairlineBorder"))
                .frame(width: 1)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color("SurfaceWindow"))
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Color("SurfaceWindow"))
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.locale, appState.appLanguage.locale)
        .background(MainWindowSetup())
        .onAppear {
            MainWindowActivation.focusAfterWindowOpen()
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
            BrowsersSettingsView()
        case .settingsApps:
            AppsScreenView()
        case .settingsRules:
            RulesSettingsView()
        case .settingsShortcuts:
            ShortcutsSettingsView()
        case .settingsAccount:
            AboutSettingsView()
        }
    }
}

// MARK: - One-time window setup

private struct MainWindowSetup: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let win = view.window else { return }
            MainWindowActivation.configure(win)
            win.setFrameAutosaveName("AppCatMainWindow")
            win.minSize = NSSize(width: 900, height: 620)

            win.isOpaque = true
            if let surface = NSColor(named: "SurfaceWindow") {
                win.backgroundColor = surface
            }

            var bh = win.collectionBehavior
            bh.insert(.moveToActiveSpace)
            bh.insert(.fullScreenPrimary)
            win.collectionBehavior = bh
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
