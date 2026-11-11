import SwiftUI

/// Fixed geometry of the handoff plate, shared with `HandoffOverlayController` so it can start
/// the icon's flight from exactly where the cat flicked it.
enum HandoffLayout {
    static let panelSize = CGSize(width: 238, height: 152)
    static let stageSize = CGSize(width: 170, height: 84)
    static let platePadding: CGFloat = 14
    static let iconSide: CGFloat = 44
    /// Icon centre inside the stage (top-left origin).
    static let iconCenterInStage = CGPoint(x: 140, y: 52)

    /// Icon centre inside the panel, measured from the panel's top-left corner.
    static var iconCenterInPanel: CGPoint {
        let plate = CGSize(width: stageSize.width + platePadding * 2, height: stageSize.height + platePadding * 2)
        return CGPoint(
            x: (panelSize.width - plate.width) / 2 + platePadding + iconCenterInStage.x,
            y: (panelSize.height - plate.height) / 2 + platePadding + iconCenterInStage.y
        )
    }
}

/// The handoff moment shown whenever AppCat routes a link/file somewhere: a cat asleep on a
/// glass plate, the destination icon drops in beside it, the cat lifts its head and flicks the
/// icon away with a paw (the controller then flies the icon to the destination app), and the
/// cat goes back to sleep. Non-interactive; it plays once and the controller tears it down.
struct HandoffView: View {
    let presentation: HandoffPresentation
    let reduceMotion: Bool
    /// Called at the instant the paw hits the icon.
    let onFlick: () -> Void

    @State private var plateScale: CGFloat = 0.9
    @State private var plateOpacity: Double = 0
    @State private var iconScale: CGFloat = 0.4
    @State private var iconYOffset: CGFloat = -14
    @State private var iconOpacity: Double = 0
    @State private var headUp = false
    @State private var eyesOpen = false
    @State private var armAngle: Double = 0
    @State private var snoreOpacity: Double = 0.8
    @State private var showsPing = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            SleepingCatView(headUp: headUp, eyesOpen: eyesOpen, armAngle: armAngle, snoreOpacity: snoreOpacity)
                .offset(y: HandoffLayout.stageSize.height / 2 + 4 - SleepingCatView.size.height / 2)

            if showsPing {
                PingRing()
                    .position(HandoffLayout.iconCenterInStage)
            }

            destinationIcon
                .frame(width: HandoffLayout.iconSide, height: HandoffLayout.iconSide)
                .scaleEffect(iconScale)
                .offset(y: iconYOffset)
                .opacity(iconOpacity)
                .position(HandoffLayout.iconCenterInStage)
        }
        .frame(width: HandoffLayout.stageSize.width, height: HandoffLayout.stageSize.height)
        .padding(HandoffLayout.platePadding)
        .handoffPlate()
        .scaleEffect(plateScale)
        .opacity(plateOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel(presentation.destinationName)
        .task { await run() }
    }

    @ViewBuilder
    private var destinationIcon: some View {
        if let icon = presentation.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "globe")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }

    private func pause(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    /// Single-shot choreography, about 1.3 s. Times in comments are from the start.
    private func run() async {
        if reduceMotion {
            iconScale = 1
            iconYOffset = 0
            iconOpacity = 1
            plateScale = 1
            withAnimation(.easeOut(duration: 0.15)) { plateOpacity = 1 }
            await pause(750)
            withAnimation(.easeOut(duration: 0.15)) { plateOpacity = 0 }
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            plateScale = 1
            plateOpacity = 1
        }
        await pause(40)
        // The icon drops in beside the sleeping cat.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            iconScale = 1
            iconYOffset = 0
            iconOpacity = 1
        }
        withAnimation(.easeOut(duration: 0.25)) { snoreOpacity = 0 }
        await pause(210) // 250: the head comes up
        withAnimation(.spring(response: 0.26, dampingFraction: 0.6)) { headUp = true }
        await pause(90) // 340
        eyesOpen = true
        await pause(90) // 430: wind up
        withAnimation(.easeOut(duration: 0.1)) { armAngle = -55 }
        await pause(105) // 535: strike
        withAnimation(.easeIn(duration: 0.055)) { armAngle = -6 }
        await pause(55) // 590: contact
        iconOpacity = 0
        showsPing = true
        onFlick()
        await pause(165) // 755: the paw comes back
        withAnimation(.easeInOut(duration: 0.2)) { armAngle = 0 }
        await pause(105) // 860: back to sleep
        withAnimation(.easeInOut(duration: 0.26)) { headUp = false }
        await pause(190) // 1050
        eyesOpen = false
        await pause(100) // 1150
        withAnimation(.easeOut(duration: 0.17)) {
            plateOpacity = 0
            plateScale = 0.97
        }
    }
}

/// One ring that pings outward from the point of contact, once.
private struct PingRing: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Color("BrandAccentDeep"), lineWidth: 2)
            .frame(width: 60, height: 60)
            .scaleEffect(expanded ? 1.6 : 0.5)
            .opacity(expanded ? 0 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) { expanded = true }
            }
    }
}

private extension View {
    /// System Liquid Glass on macOS 26+, the system material on older systems (the same split the
    /// picker panel uses).
    @ViewBuilder
    func handoffPlate() -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color("HairlineBorder"), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        }
    }
}
