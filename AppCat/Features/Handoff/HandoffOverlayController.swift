import AppKit
import QuartzCore
import SwiftUI

/// Shows the cat handoff near the cursor whenever AppCat routes a link/file, then flies the
/// destination icon to where that app is. Both panels are borderless, non-activating and
/// click-through; they self-dismiss and never steal focus.
@MainActor
final class HandoffOverlayController {
    static let shared = HandoffOverlayController()

    private var panel: NSPanel?
    private var flightPanel: NSPanel?
    private var closeWorkItem: DispatchWorkItem?
    private let size = HandoffLayout.panelSize

    /// Total on-screen lifetime of the plate; must outlast `HandoffView.run()` (about 1.32 s).
    private let lifetime: TimeInterval = 1.4
    private let flightDuration: CFTimeInterval = 0.52
    private let flightFade: CFTimeInterval = 0.16

    private init() {}

    func present(_ presentation: HandoffPresentation, style: HandoffAnimationStyle = .full, locale: Locale = .current) {
        closeWorkItem?.cancel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if style == .compact {
            // No plate and no cat: the icon pops up just above the cursor and flies to the app.
            panel?.orderOut(nil)
            panel?.contentView = nil
            guard !reduceMotion else { return }
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
            flyIcon(
                presentation.icon,
                from: CGPoint(x: mouse.x, y: mouse.y + 30),
                on: screen,
                toAppWithBundleIdentifier: presentation.bundleIdentifier,
                popsIn: true
            )
            return
        }

        let panel = ensurePanel()

        // Fresh hosting view each time so SwiftUI state resets and the animation replays.
        let host = NSHostingView(
            rootView: HandoffView(presentation: presentation, reduceMotion: reduceMotion) { [weak self] in
                self?.flyIconFromPlate(presentation.icon, toAppWithBundleIdentifier: presentation.bundleIdentifier)
            }
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

    // MARK: - Icon flight

    /// Runs entirely in Core Animation: one icon-sized layer in a window with no backing store of
    /// its own, so the flight costs no per-frame app work and almost no memory.
    private func flyIconFromPlate(_ icon: NSImage?, toAppWithBundleIdentifier bundleIdentifier: String?) {
        guard let panel else { return }
        let iconCenter = HandoffLayout.iconCenterInPanel
        flyIcon(
            icon,
            from: CGPoint(x: panel.frame.minX + iconCenter.x, y: panel.frame.maxY - iconCenter.y),
            on: panel.screen ?? NSScreen.main ?? NSScreen.screens[0],
            toAppWithBundleIdentifier: bundleIdentifier,
            popsIn: false
        )
    }

    private func flyIcon(
        _ icon: NSImage?,
        from start: CGPoint,
        on screen: NSScreen,
        toAppWithBundleIdentifier bundleIdentifier: String?,
        popsIn: Bool
    ) {
        guard let icon else { return }
        let end = HandoffTargetLocator.targetPoint(bundleIdentifier: bundleIdentifier, fallbackScreen: screen)
        let control = CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 110)

        let side = HandoffLayout.iconSide
        let margin = side * 1.5
        let xs = [start.x, end.x, control.x]
        let ys = [start.y, end.y, control.y]
        let minX = (xs.min() ?? 0) - margin
        let minY = (ys.min() ?? 0) - margin
        let frame = CGRect(
            x: minX,
            y: minY,
            width: (xs.max() ?? 0) + margin - minX,
            height: (ys.max() ?? 0) + margin - minY
        )
        func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - frame.minX, y: point.y - frame.minY) }

        let flight = ensureFlightPanel()
        flight.setFrame(frame, display: false)
        guard let root = flight.contentView?.layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        layer.contents = icon
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = screen.backingScaleFactor
        layer.position = local(end)
        layer.opacity = 0 // model value is the end state; the animations below show the flight
        root.addSublayer(layer)

        let path = CGMutablePath()
        path.move(to: local(start))
        path.addQuadCurve(to: local(end), control: local(control))

        let travel = CAKeyframeAnimation(keyPath: "position")
        travel.path = path
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -340 * Double.pi / 180
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = popsIn ? [0.4, 1, 1.5] : [1, 1, 1.5]
        grow.keyTimes = [0, 0.18, 1]
        for animation in [travel, spin, grow] as [CAAnimation] {
            animation.duration = flightDuration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.3, 1)
            animation.fillMode = .forwards
        }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        let total = flightDuration + flightFade
        fade.values = [popsIn ? 0 : 1, 1, 1, 0]
        fade.keyTimes = [0, 0.06, NSNumber(value: flightDuration / total), 1]
        fade.duration = total

        let group = CAAnimationGroup()
        group.animations = [travel, spin, grow, fade]
        group.duration = total

        flight.orderFrontRegardless()
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak flight, weak layer] in
            // A newer flight may have replaced this layer; only hide when it is still the last one.
            guard let flight, let layer, layer.superlayer != nil else { return }
            layer.removeFromSuperlayer()
            flight.orderOut(nil)
        }
        layer.add(group, forKey: "flight")
        CATransaction.commit()
    }

    // MARK: - Panels

    private func makeOverlayPanel(size: NSSize) -> NSPanel {
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
        p.hasShadow = false
        p.ignoresMouseEvents = true // click-through; purely decorative
        p.hidesOnDeactivate = false
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return p
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = makeOverlayPanel(size: size)
        panel = p
        return p
    }

    private func ensureFlightPanel() -> NSPanel {
        if let flightPanel { return flightPanel }
        let p = makeOverlayPanel(size: NSSize(width: 100, height: 100))
        let view = NSView()
        view.layer = CALayer() // layer-hosting: no drawing, so no backing store
        view.wantsLayer = true
        p.contentView = view
        flightPanel = p
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
