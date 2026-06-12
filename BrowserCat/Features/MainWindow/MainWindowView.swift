import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(240)
                .toolbar(removing: .sidebarToggle)
                .background(Color("SurfaceSidebar"))
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color("SurfaceWindow"))
        }
        .navigationSplitViewStyle(.balanced)
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
            section(HistorySettingsView())
        case .suggestions:
            SuggestionsView()
        case .settingsGeneral:
            section(GeneralSettingsView())
        case .settingsBrowsers:
            BrowsersSettingsView()
        case .settingsApps:
            AppsScreenView()
        case .settingsRules:
            section(RulesSettingsView())
        case .settingsShortcuts:
            ShortcutsSettingsView()
        case .settingsAccount:
            section(AboutSettingsView())
        }
    }

    /// Wraps a detail view with the flat section header (title + hairline) used across
    /// every non-Overview screen. Overview and Suggestions provide their own headers.
    private func section(_ content: some View) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(appState.mainWindowSection.label)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color("HairlineBorder"))
                .frame(height: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color("SurfaceWindow"))
    }
}

// MARK: - One-time window setup

private struct MainWindowSetup: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let win = view.window else { return }
            win.setFrameAutosaveName("BrowserCatMainWindow")
            win.minSize = NSSize(width: 900, height: 620)

            // Unified flat chrome — traffic lights float over the sidebar, no toolbar strip.
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.styleMask.insert(.fullSizeContentView)
            win.isMovableByWindowBackground = true
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
