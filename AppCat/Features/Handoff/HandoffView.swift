import SwiftUI

/// "Cat Pounce" handoff — the brief, springy moment shown whenever AppCat routes a
/// link/file somewhere. The destination icon pounces up out of a marmalade ripple, a paw
/// swipes across, and a small cat signs off with a wink so it's unmistakably the cat doing
/// the navigating. Non-interactive; it animates once and the controller tears it down.
struct HandoffView: View {
    let presentation: HandoffPresentation

    // Card
    @State private var cardScale: CGFloat = 0.9
    @State private var cardOpacity: Double = 0
    // Ripple / glow
    @State private var ripple = false
    @State private var glow = false
    // Icon pounce
    @State private var iconScale: CGFloat = 0.35
    @State private var iconOpacity: Double = 0
    @State private var iconYOffset: CGFloat = 16
    // Paw swipe
    @State private var pawOffset: CGFloat = -64
    @State private var pawOpacity: Double = 0
    @State private var pawRotation: Double = -28
    // Text + cat wink
    @State private var textOpacity: Double = 0
    @State private var catScale: CGFloat = 1

    private var caption: String {
        switch presentation.reason {
        case .userPicked: return "Відкриваю в"
        case .ruleMatched: return "Правило киці · відкриваю в"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            pounceStage
                .frame(width: 132, height: 104)

            VStack(spacing: 2) {
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(presentation.destinationName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .opacity(textOpacity)

            HStack(spacing: 4) {
                Image(systemName: "cat.fill")
                    .font(.system(size: 9, weight: .semibold))
                Text("AppCat")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.tertiary)
            .opacity(textOpacity * 0.9)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color("SurfaceCard"))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color("HairlineBorder"), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        )
        .scaleEffect(cardScale)
        .opacity(cardOpacity)
        .task { await run() }
    }

    private var pounceStage: some View {
        ZStack {
            // Soft marmalade glow that expands once behind the icon.
            Circle()
                .fill(Color("AccentColor").opacity(0.22))
                .frame(width: 92, height: 92)
                .scaleEffect(glow ? 1.25 : 0.55)
                .opacity(glow ? 0 : 1)
                .blur(radius: 8)

            // Two ripple rings pinging outward.
            ForEach(0 ..< 2, id: \.self) { i in
                Circle()
                    .stroke(Color("BrandAccentDeep").opacity(0.55), lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .scaleEffect(ripple ? 1.7 + CGFloat(i) * 0.3 : 0.5)
                    .opacity(ripple ? 0 : 0.7)
            }

            // The destination app icon — the thing that "pounces" into view.
            destinationIcon
                .frame(width: 60, height: 60)
                .scaleEffect(iconScale)
                .offset(y: iconYOffset)
                .opacity(iconOpacity)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

            // Cat paw swiping across the icon.
            Image(systemName: "pawprint.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color("AccentColor"))
                .rotationEffect(.degrees(pawRotation))
                .offset(x: pawOffset, y: -4)
                .opacity(pawOpacity)

            // Tiny cat in the corner that winks at the end.
            Image(systemName: "cat.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color("BrandAccentDeep"))
                .scaleEffect(catScale)
                .opacity(textOpacity)
                .offset(x: 44, y: 36)
        }
    }

    @ViewBuilder
    private var destinationIcon: some View {
        if let icon = presentation.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color("AccentColor"), Color("BrandAccentDeep")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Image(systemName: "cat.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
    }

    /// Single-shot choreography. Roughly: card pops in → ripple/glow ping → paw swipe →
    /// icon springs up → caption fades in → cat winks → everything eases out (~1s total).
    private func run() async {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
            cardScale = 1
            cardOpacity = 1
        }
        try? await Task.sleep(for: .milliseconds(60))

        withAnimation(.easeOut(duration: 0.55)) { ripple = true }
        withAnimation(.easeOut(duration: 0.5)) { glow = true }
        withAnimation(.easeOut(duration: 0.16)) {
            pawOpacity = 1
            pawOffset = 6
            pawRotation = 10
        }
        try? await Task.sleep(for: .milliseconds(120))

        withAnimation(.spring(response: 0.42, dampingFraction: 0.56)) {
            iconScale = 1
            iconOpacity = 1
            iconYOffset = 0
        }
        withAnimation(.easeIn(duration: 0.2).delay(0.1)) {
            pawOpacity = 0
            pawOffset = 46
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.12)) { textOpacity = 1 }
        try? await Task.sleep(for: .milliseconds(420))

        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { catScale = 0.55 }
        try? await Task.sleep(for: .milliseconds(110))
        withAnimation(.spring(response: 0.26, dampingFraction: 0.6)) { catScale = 1 }
        try? await Task.sleep(for: .milliseconds(150))

        withAnimation(.easeIn(duration: 0.18)) {
            cardOpacity = 0
            cardScale = 0.97
            iconScale = 1.06
        }
    }
}
