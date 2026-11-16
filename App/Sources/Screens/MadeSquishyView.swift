import SwiftUI
import UIKit
import SquishPolicy

/// Any squeezable thing by reference: a collectible, a starter toy or a made squishy.
struct SquishRefView: View {
    @EnvironmentObject var model: AppModel
    let ref: String
    var squash: CGFloat = 0

    var body: some View {
        if let made = model.progress.made.first(where: { $0.ref == ref }) {
            MadeSquishyView(made: made, squash: squash)
        } else {
            SquishyView(id: ref, rarity: model.roster.collectible(ref)?.rarity ?? .common, squash: squash)
        }
    }
}

/// A squishy from the Maker, drawn from its parts.
struct MadeSquishyView: View {
    let made: MadeSquishy
    var squash: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            let d = min(size.width, size.height) * 0.56
            // Anchored at the bottom centre, like the launch art.
            ctx.translateBy(x: size.width / 2, y: size.height * 0.92)
            ctx.scaleBy(x: 1 + squash * 0.25, y: 1 - squash * 0.35)
            ctx.translateBy(x: 0, y: -d * 0.55)
            MadeSquishyView.draw(made, in: &ctx, d: d, squash: squash)
        }
        .accessibilityLabel(Text(made.name))
    }

    private static let plum = Color(uiColor: .plum)

    static func color(_ index: Int) -> Color {
        let palette = MakerParts.palette
        return Color(uiColor: UIColor(hex: palette[min(max(0, index), palette.count - 1)]))
    }

    private static func blob(_ ctx: inout GraphicsContext, _ path: Path, _ fill: Color, _ line: CGFloat) {
        ctx.stroke(path, with: .color(plum), style: StrokeStyle(lineWidth: line * 2, lineJoin: .round))
        ctx.fill(path, with: .color(fill))
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    static func bodyPath(_ shape: MadeSquishy.Shape, d: CGFloat) -> Path {
        switch shape {
        case .bun:
            return Path(ellipseIn: CGRect(x: -d * 0.5, y: -d * 0.4, width: d, height: d * 0.8))
        case .egg:
            return Path(ellipseIn: CGRect(x: -d * 0.4, y: -d * 0.5, width: d * 0.8, height: d))
        case .bean:
            return Path(roundedRect: CGRect(x: -d * 0.5, y: -d * 0.36, width: d, height: d * 0.72), cornerRadius: d * 0.34)
        case .drop:
            var p = Path()
            p.move(to: CGPoint(x: 0, y: -d * 0.58))
            p.addQuadCurve(to: CGPoint(x: d * 0.42, y: d * 0.1), control: CGPoint(x: d * 0.38, y: -d * 0.2))
            p.addArc(center: CGPoint(x: 0, y: d * 0.1), radius: d * 0.42, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addQuadCurve(to: CGPoint(x: 0, y: -d * 0.58), control: CGPoint(x: -d * 0.38, y: -d * 0.2))
            p.closeSubpath()
            return p
        case .dome:
            var p = Path()
            p.move(to: CGPoint(x: -d * 0.48, y: d * 0.4))
            p.addLine(to: CGPoint(x: -d * 0.48, y: 0))
            p.addArc(center: .zero, radius: d * 0.48, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            p.addLine(to: CGPoint(x: d * 0.48, y: d * 0.4))
            p.addQuadCurve(to: CGPoint(x: -d * 0.48, y: d * 0.4), control: CGPoint(x: 0, y: d * 0.52))
            p.closeSubpath()
            return p
        case .cloud:
            var p = Path()
            p.addPath(circle(-d * 0.25, 0, d * 0.28))
            p.addPath(circle(d * 0.25, 0, d * 0.28))
            p.addPath(circle(0, -d * 0.18, d * 0.32))
            p.addPath(Path(roundedRect: CGRect(x: -d * 0.5, y: 0, width: d, height: d * 0.4), cornerRadius: d * 0.2))
            return p
        }
    }

    private static func topY(_ shape: MadeSquishy.Shape, d: CGFloat) -> CGFloat {
        switch shape {
        case .bun: return -d * 0.4
        case .bean: return -d * 0.36
        case .dome: return -d * 0.48
        case .egg, .cloud: return -d * 0.5
        case .drop: return -d * 0.52
        }
    }

    static func draw(_ m: MadeSquishy, in ctx: inout GraphicsContext, d: CGFloat, squash: CGFloat) {
        let line = d * 0.04
        let fill = color(m.color)
        let top = topY(m.shape, d: d)
        let earX = m.shape == .drop || m.shape == .egg ? d * 0.2 : d * 0.28
        let earY = top + d * 0.14

        // Ears sit behind the body.
        for side: CGFloat in [-1, 1] {
            let x = side * earX
            switch m.ears {
            case .none: break
            case .cat:
                blob(&ctx, polygon([CGPoint(x: x - d * 0.14, y: earY), CGPoint(x: x + d * 0.14, y: earY),
                                    CGPoint(x: x + side * d * 0.06, y: earY - d * 0.28)]), fill, line)
            case .bear:
                blob(&ctx, circle(x, earY - d * 0.04, d * 0.14), fill, line)
            case .bunny:
                blob(&ctx, Path(ellipseIn: CGRect(x: x * 0.7 - d * 0.08, y: earY - d * 0.46, width: d * 0.16, height: d * 0.5)), fill, line)
            case .horns:
                blob(&ctx, polygon([CGPoint(x: x - d * 0.07, y: earY), CGPoint(x: x + d * 0.07, y: earY),
                                    CGPoint(x: x + side * d * 0.03, y: earY - d * 0.22)]), Theme.butter, line)
            }
        }
        if m.accessory == .headphones {
            var band = Path()
            band.addArc(center: .zero, radius: d * 0.53, startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(band, with: .color(plum), style: StrokeStyle(lineWidth: line * 2.5, lineCap: .round))
        }

        blob(&ctx, bodyPath(m.shape, d: d), fill, line)
        // Gloss
        ctx.fill(Path(ellipseIn: CGRect(x: -d * 0.3, y: -d * 0.26, width: d * 0.2, height: d * 0.11)), with: .color(.white.opacity(0.55)))

        // Face
        let eyeY = -d * 0.02
        for side: CGFloat in [-1, 1] {
            let x = side * d * 0.17
            let closed = m.eyes == .sleepy || (m.eyes == .wink && side > 0) || squash > 0.6
            if closed {
                var lid = Path()
                lid.addArc(center: CGPoint(x: x, y: eyeY - d * 0.02), radius: d * 0.055, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                ctx.stroke(lid, with: .color(plum), style: StrokeStyle(lineWidth: line * 0.8, lineCap: .round))
            } else {
                ctx.fill(circle(x, eyeY, d * 0.055), with: .color(plum))
                if m.eyes == .sparkle {
                    ctx.fill(circle(x - d * 0.018, eyeY - d * 0.02, d * 0.022), with: .color(.white))
                    ctx.fill(circle(x + d * 0.02, eyeY + d * 0.02, d * 0.011), with: .color(.white))
                }
            }
            ctx.fill(Path(ellipseIn: CGRect(x: side * d * 0.29 - d * 0.08, y: d * 0.05, width: d * 0.16, height: d * 0.07)),
                     with: .color(Color(red: 1, green: 0.62, blue: 0.71).opacity(0.7)))
        }
        let mouthStyle = StrokeStyle(lineWidth: line * 0.75, lineCap: .round)
        switch m.mouth {
        case .smile, .tongue:
            var smile = Path()
            smile.addArc(center: CGPoint(x: 0, y: d * 0.05), radius: d * 0.06, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
            if m.mouth == .tongue {
                ctx.fill(Path(ellipseIn: CGRect(x: -d * 0.03, y: d * 0.09, width: d * 0.06, height: d * 0.06)),
                         with: .color(Color(red: 1, green: 0.5, blue: 0.6)))
            }
            ctx.stroke(smile, with: .color(plum), style: mouthStyle)
        case .open:
            ctx.fill(Path(ellipseIn: CGRect(x: -d * 0.05, y: d * 0.05, width: d * 0.1, height: d * 0.09)), with: .color(plum))
        case .cat:
            for side: CGFloat in [-1, 1] {
                var half = Path()
                half.addArc(center: CGPoint(x: side * d * 0.045, y: d * 0.06), radius: d * 0.045, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                ctx.stroke(half, with: .color(plum), style: mouthStyle)
            }
        }

        // Accessories sit on top.
        switch m.accessory {
        case .none: break
        case .bow:
            let y = top + d * 0.02
            blob(&ctx, polygon([CGPoint(x: 0, y: y), CGPoint(x: -d * 0.2, y: y - d * 0.1), CGPoint(x: -d * 0.2, y: y + d * 0.1)]), Theme.bubblegum, line * 0.8)
            blob(&ctx, polygon([CGPoint(x: 0, y: y), CGPoint(x: d * 0.2, y: y - d * 0.1), CGPoint(x: d * 0.2, y: y + d * 0.1)]), Theme.bubblegum, line * 0.8)
            blob(&ctx, circle(0, y, d * 0.05), Theme.bubblegum, line * 0.8)
        case .crown:
            let y = top + d * 0.04
            blob(&ctx, polygon([CGPoint(x: -d * 0.16, y: y), CGPoint(x: -d * 0.16, y: y - d * 0.18), CGPoint(x: -d * 0.08, y: y - d * 0.09),
                                CGPoint(x: 0, y: y - d * 0.22), CGPoint(x: d * 0.08, y: y - d * 0.09), CGPoint(x: d * 0.16, y: y - d * 0.18),
                                CGPoint(x: d * 0.16, y: y)]), Theme.butter, line * 0.8)
        case .headphones:
            for side: CGFloat in [-1, 1] {
                blob(&ctx, Path(roundedRect: CGRect(x: side * d * 0.5 - d * 0.07, y: -d * 0.15, width: d * 0.14, height: d * 0.28), cornerRadius: d * 0.06),
                     Theme.sky, line * 0.8)
            }
        case .unicornHorn:
            let y = top + d * 0.05
            blob(&ctx, polygon([CGPoint(x: -d * 0.07, y: y), CGPoint(x: d * 0.07, y: y), CGPoint(x: 0, y: y - d * 0.3)]), Theme.butter, line * 0.8)
        case .leaf:
            let y = top + d * 0.03
            var stem = Path()
            stem.move(to: CGPoint(x: 0, y: y))
            stem.addLine(to: CGPoint(x: 0, y: y - d * 0.1))
            ctx.stroke(stem, with: .color(plum), style: StrokeStyle(lineWidth: line, lineCap: .round))
            blob(&ctx, Path(ellipseIn: CGRect(x: 0, y: y - d * 0.2, width: d * 0.2, height: d * 0.11)), Color(red: 0.56, green: 0.83, blue: 0.42), line * 0.8)
        }
    }
}

/// The Buddy's speech bubble.
struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Theme.body(16))
            .foregroundStyle(Theme.plum)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.plum.opacity(0.15), lineWidth: 2))
            .accessibilityIdentifier("buddy-says")
    }
}
