import AppKit
import SwiftUI

/// Shows the Cat Pounce handoff overlay near the cursor whenever AppCat routes a
/// link/file. It is a borderless, non-activating, click-through panel floating above the
/// destination app that is launching underneath — so the app comes forward as the overlay
/// fades, reading as "the cat carried you there." Self-dismisses; never steals focus.
@MainActor
final class HandoffOverlayController {
    static let shared = HandoffOverlayController()

    private var panel: NSPanel?
    private var closeWorkItem: DispatchWorkItem?
    private let size = NSSize(width: 280, height: 240)

    /// Total on-screen lifetime — must outlast `HandoffView.run()`'s choreography (~1.0s).
    private let lifetime: TimeInterval = 1.15

    private init() {}

    func present(_ presentation: HandoffPresentation, locale: Locale = .current) {
        closeWorkItem?.cancel()

        let panel = ensurePanel()

        // Fresh hosting view each time so SwiftUI state resets and the animation replays.
        let host = NSHostingView(
            rootView: HandoffView(presentation: presentation)
                .environment(\.locale, locale)
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host

        position(panel)
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.contentView = nil
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime, execute: work)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar // above the destination app that activates underneath
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false // the SwiftUI card draws its own shadow
        p.ignoresMouseEvents = true // click-through; purely decorative
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel = p
        return p
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        var origin = NSPoint(
            x: mouse.x - size.width / 2,
            y: mouse.y - size.height / 2 + 30
        )
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
        origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - size.height - 8))

        panel.setFrameOrigin(origin)
    }
}
