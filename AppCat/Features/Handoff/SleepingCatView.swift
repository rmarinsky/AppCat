import SwiftUI

/// The handoff cat: a ginger tabby asleep on its paws. It is three small vector layers (body,
/// striking arm, head) so the head lift and the paw flick are plain compositing transforms;
/// the artwork itself is rasterised only when the eyes open or close.
struct SleepingCatView: View {
    var headUp: Bool
    var eyesOpen: Bool
    /// Degrees; 0 rests on the floor, negative lifts the paw.
    var armAngle: Double
    var snoreOpacity: Double

    /// Artwork is authored in a 200 x 120 box and drawn at this scale.
    static let scale: CGFloat = 0.62
    static let size = CGSize(width: 200 * scale, height: 120 * scale)

    private static let armAnchor = UnitPoint(x: 128.0 / 200, y: 96.0 / 120)
    private static let headAnchor = UnitPoint(x: 130.0 / 200, y: 84.0 / 120)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in CatArt.drawBody(&ctx) }
            Canvas { ctx, _ in CatArt.drawArm(&ctx) }
                .rotationEffect(.degrees(armAngle), anchor: Self.armAnchor)
            Canvas { ctx, _ in CatArt.drawHead(&ctx, eyesOpen: eyesOpen) }
                .rotationEffect(.degrees(headUp ? 0 : 9), anchor: Self.headAnchor)
                .offset(x: headUp ? 0 : 3 * Self.scale, y: headUp ? 0 : 15 * Self.scale)
            Text(verbatim: "z")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(snoreOpacity)
                .offset(x: 172 * Self.scale, y: (snoreOpacity > 0 ? 14 : 4) * Self.scale)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

private enum CatArt {
    static let fur = Color(red: 0.914, green: 0.584, blue: 0.294)
    static let stripe = Color(red: 0.761, green: 0.416, blue: 0.145)
    static let cream = Color(red: 0.984, green: 0.914, blue: 0.843)
    static let dark = Color(red: 0.165, green: 0.102, blue: 0.039)
    static let pink = Color(red: 0.867, green: 0.510, blue: 0.447)
    static let eye = Color(red: 0.663, green: 0.773, blue: 0.322)

    static let tail = Path(svg: "M20 96 C4 104 14 113 42 111 C72 109 96 111 114 107")
    static let body = Path(svg: "M24 104 C10 100 8 74 22 58 C38 40 70 34 100 38 C122 41 138 52 144 70 C148 84 146 98 140 104 Z")
    static let backStripes = Path(svg: "M52 45 q5 10 0 20 M68 40 q5 10 2 21 M84 38 q5 10 3 21 M100 39 q5 10 4 19")
    static let haunch = Path(svg: "M24 104 C14 92 18 70 36 64 C54 58 70 70 70 88 C70 96 66 102 60 104 Z")
    static let haunchStripes = Path(svg: "M30 74 q8 -4 16 0 M28 84 q10 -4 20 0")
    static let chest = Path(svg: "M128 74 C138 80 142 92 138 104 L120 104 C118 92 120 82 128 74 Z")
    static let arm = Path(svg: "M124 90 C140 88 164 90 176 93 C183 95 183 102 176 103 C162 105 140 104 124 102 Z")
    static let toes = Path(svg: "M177 95.5 v5 M173 95 v6")
    static let ears = Path(svg: "M114 52 L111 25 L131 40 Z M149 40 L169 25 L166 52 Z")
    static let innerEars = Path(svg: "M117 45 L116 32 L126 40 Z M154 40 L164 32 L163 45 Z")
    static let head = Path(svg: "M112 62 C110 46 124 36 140 36 C156 36 170 46 168 62 C168 70 173 72 166 78 C158 86 146 88 140 88 C134 88 122 86 114 78 C107 72 112 70 112 62 Z")
    static let faceStripes = Path(svg: "M134 40 v8 M140 39 v9 M146 40 v8 M113 65 l8 2 M114 71 h8 M167 65 l-8 2 M166 71 h-8")
    static let nose = Path(svg: "M136.5 66 h7 l-3.5 4.5 z")
    static let mouth = Path(svg: "M140 70.5 v3 M140 73.5 q-4 4 -7 1 M140 73.5 q4 4 7 1")
    static let closedEyes = Path(svg: "M121 60 q6 5 12 0 M147 60 q6 5 12 0")
    static let whiskers = Path(svg: "M130 73 l-24 -4 M130 76 l-24 3 M150 73 l24 -4 M150 76 l24 3")

    private static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private static func line(_ width: CGFloat, dash: [CGFloat] = []) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
    }

    private static func furShape(_ ctx: inout GraphicsContext, _ path: Path) {
        ctx.fill(path, with: .color(fur))
        ctx.stroke(path, with: .color(stripe), style: line(1.2))
    }

    static func drawBody(_ ctx: inout GraphicsContext) {
        ctx.scaleBy(x: SleepingCatView.scale, y: SleepingCatView.scale)
        ctx.fill(ellipse(88, 107, 80, 5), with: .color(.black.opacity(0.16)))
        ctx.stroke(tail, with: .color(fur), style: line(11))
        ctx.stroke(tail, with: .color(stripe.opacity(0.8)), style: line(11, dash: [3, 10]))
        furShape(&ctx, body)
        ctx.stroke(backStripes, with: .color(stripe.opacity(0.85)), style: line(4))
        furShape(&ctx, haunch)
        ctx.stroke(haunchStripes, with: .color(stripe.opacity(0.7)), style: line(3))
        furShape(&ctx, ellipse(62, 102, 14, 5))
        ctx.fill(chest, with: .color(cream))
        furShape(&ctx, ellipse(134, 102, 13, 5))
    }

    static func drawArm(_ ctx: inout GraphicsContext) {
        ctx.scaleBy(x: SleepingCatView.scale, y: SleepingCatView.scale)
        furShape(&ctx, arm)
        ctx.fill(ellipse(175, 98, 8, 5.5), with: .color(cream))
        ctx.stroke(toes, with: .color(stripe), style: line(0.9))
    }

    static func drawHead(_ ctx: inout GraphicsContext, eyesOpen: Bool) {
        ctx.scaleBy(x: SleepingCatView.scale, y: SleepingCatView.scale)
        furShape(&ctx, ears)
        ctx.fill(innerEars, with: .color(pink))
        furShape(&ctx, head)
        ctx.stroke(faceStripes, with: .color(stripe), style: line(2.4))
        ctx.fill(ellipse(140, 73, 12, 9), with: .color(cream))
        ctx.fill(nose, with: .color(pink))
        ctx.stroke(mouth, with: .color(dark), style: line(1.1))
        if eyesOpen {
            for cx in [127.0, 153.0] {
                ctx.fill(ellipse(cx, 59, 5.8, 5.2), with: .color(eye))
                ctx.fill(ellipse(cx, 59, 1.9, 4.6), with: .color(dark))
                ctx.fill(ellipse(cx + 1.6, 57, 1.1, 1.1), with: .color(.white))
            }
        } else {
            ctx.stroke(closedEyes, with: .color(dark), style: line(1.8))
        }
        ctx.stroke(whiskers, with: .color(.white.opacity(0.85)), style: line(0.8))
    }
}

private extension Path {
    /// Minimal SVG path-data reader (M L H V C Q Z, absolute and relative) for the cat artwork.
    init(svg data: String) {
        self.init()
        // swiftlint:disable:next force_try
        let tokens = data.matches(of: try! Regex("[A-Za-z]|-?[0-9]*\\.?[0-9]+")).map { String(data[$0.range]) }
        var index = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        func number() -> CGFloat {
            defer { index += 1 }
            return index < tokens.count ? CGFloat(Double(tokens[index]) ?? 0) : 0
        }
        func point(relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = first
                index += 1
                if command == "Z" || command == "z" {
                    closeSubpath()
                    current = subpathStart
                }
                continue
            }
            let relative = command.isLowercase
            switch command {
            case "M", "m":
                current = point(relative: relative)
                subpathStart = current
                move(to: current)
                command = relative ? "l" : "L"
            case "L", "l":
                current = point(relative: relative)
                addLine(to: current)
            case "H", "h":
                let x = number()
                current.x = relative ? current.x + x : x
                addLine(to: current)
            case "V", "v":
                let y = number()
                current.y = relative ? current.y + y : y
                addLine(to: current)
            case "C", "c":
                let c1 = point(relative: relative), c2 = point(relative: relative), end = point(relative: relative)
                addCurve(to: end, control1: c1, control2: c2)
                current = end
            case "Q", "q":
                let control = point(relative: relative), end = point(relative: relative)
                addQuadCurve(to: end, control: control)
                current = end
            default:
                index += 1
            }
        }
    }
}
