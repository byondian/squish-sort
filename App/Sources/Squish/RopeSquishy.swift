import SwiftUI
import UIKit
import SquishSoft

/// Catches every finger on its own, so two hands can pull the two ends of a rope.
struct FingerPad: UIViewRepresentable {
    var began: (Int, CGPoint) -> Void
    var moved: (Int, CGPoint) -> Void
    var ended: (Int) -> Void

    func makeUIView(context: Context) -> Pad {
        let pad = Pad()
        pad.isMultipleTouchEnabled = true
        pad.backgroundColor = .clear
        return pad
    }

    func updateUIView(_ pad: Pad, context: Context) {
        pad.began = began
        pad.moved = moved
        pad.ended = ended
    }

    final class Pad: UIView {
        var began: ((Int, CGPoint) -> Void)?
        var moved: ((Int, CGPoint) -> Void)?
        var ended: ((Int) -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches { began?(ObjectIdentifier(touch).hashValue, touch.location(in: self)) }
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches { moved?(ObjectIdentifier(touch).hashValue, touch.location(in: self)) }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches { ended?(ObjectIdentifier(touch).hashValue) }
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches { ended?(ObjectIdentifier(touch).hashValue) }
        }
    }
}

/// Taffy Snake: a coiled rope. Pull his head or tail and he uncoils; let go and he springs back.
/// The body is `SquishRope`; the drawing is the same three strokes as his art, along the live spine.
@MainActor
struct RopeSquishy: View {
    @EnvironmentObject var model: AppModel
    /// The Squish Room has a floor to sit on with room above; elsewhere he fills his frame.
    var room = false
    var onTouch: (() -> Void)?
    var onLetGo: ((Double) -> Void)?
    @StateObject private var holder = Holder()

    final class Holder: ObservableObject {
        var rope: SquishRope?
        var size = CGSize.zero
        var world = SquishRope.World(floor: 0, left: 0, right: 0)
        var last: Date?
        var band = 0
        var quiet = 0.0
        var head = (x: 0.0, y: 0.0)
        @Published var awake = true
    }

    /// His spine in art units, from the art (the seat offset is already in).
    private static let cubics: [[Double]] = [
        [38, 35.2, 66, 27.2, 94, 37.2, 84, 57.2], [84, 57.2, 74, 77.2, 30, 65.2, 34, 85.2], [34, 85.2, 36, 97.2, 70, 99.2, 98, 89.2],
    ]
    private static let ink = Color(uiColor: UIColor(hex: 0x3B2A4A))
    private static let pink = Color(uiColor: UIColor(hex: 0xFF9CC8))

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !holder.awake)) { timeline in
                Canvas { ctx, size in
                    step(timeline.date, size)
                    draw(&ctx)
                }
            }
            FingerPad(began: { id, at in
                guard let rope = holder.rope, rope.grab(id, x: at.x, y: at.y) else { return }
                if !holder.awake { holder.awake = true }
                model.haptics.lift()
                model.sounds.play("pop", volume: 0.3)
                onTouch?()
            }, moved: { id, at in
                holder.rope?.move(id, x: at.x, y: at.y)
            }, ended: { id in
                guard let rope = holder.rope, rope.isHeld else { return }
                let depth = max(rope.metric.D, rope.metric.unravel)
                rope.release(id)
                if !rope.isHeld { onLetGo?(depth) }
            })
        }
    }

    private func build(_ size: CGSize) {
        let holder = self.holder
        let w = Double(size.width), h = Double(size.height)
        guard w > 20, h > 20 else { return }
        let floor = room ? h - 28 : h - 2
        let side = room ? max(120, min(w * 0.70, (floor - 20) * 0.62, 340)) : min(w, h) * 0.84
        holder.size = size
        holder.world = SquishRope.World(floor: floor, left: 6, right: w - 6)
        holder.rope = SquishRope(cubics: RopeSquishy.cubics, n: 30, size: side, x: w / 2, y: floor - side * 0.36,
                                 radius: 15.5, headR: 22, material: .taffy)
        holder.band = 0
        holder.quiet = 0
    }

    private func step(_ now: Date, _ size: CGSize) {
        let holder = self.holder
        if holder.rope == nil || abs(holder.size.width - size.width) > 1 || abs(holder.size.height - size.height) > 1 { build(size) }
        guard let rope = holder.rope else { return }
        let dt = min(1.0 / 30, max(0, now.timeIntervalSince(holder.last ?? now)))
        holder.last = now
        let n = max(1, Int((dt * 240).rounded()))
        if dt > 0 { for _ in 0..<n { rope.step(dt / Double(n), world: holder.world) } }
        // A pop as each curve straightens, and a boing on the way back.
        let m = rope.metric
        let band = Int(m.unravel * 4)
        if band > holder.band, band <= 4 { model.sounds.play("pop", volume: Float(0.35 + Double(band) * 0.12)) }
        holder.band = band
        if m.recoil > 0 {
            rope.metric.recoil = 0
            model.sounds.play("hop")
            model.haptics.land()
        }
        // Lying still and let go: stop drawing until a finger comes back.
        let moved = abs(rope.p[0] - holder.head.x) + abs(rope.p[1] - holder.head.y)
        holder.head = (rope.p[0], rope.p[1])
        holder.quiet = rope.isHeld || moved > 0.03 ? 0 : holder.quiet + dt
        if holder.quiet > 1.5 {
            DispatchQueue.main.async { if holder.awake, holder.quiet > 1.5 { holder.awake = false } }
        }
    }

    private func spine(_ rope: SquishRope) -> Path {
        let p = rope.p, n = rope.n
        var path = Path()
        path.move(to: CGPoint(x: p[0], y: p[1]))
        if n > 2 {
            for i in 1..<(n - 1) {
                path.addQuadCurve(to: CGPoint(x: (p[i * 2] + p[i * 2 + 2]) / 2, y: (p[i * 2 + 1] + p[i * 2 + 3]) / 2),
                                  control: CGPoint(x: p[i * 2], y: p[i * 2 + 1]))
            }
        }
        path.addLine(to: CGPoint(x: p[(n - 1) * 2], y: p[(n - 1) * 2 + 1]))
        return path
    }

    /// Where a held-still finger squeezes, the tube bulges.
    private func bulges(_ rope: SquishRope, _ radius: Double, _ color: Color, _ ctx: inout GraphicsContext) {
        let p = rope.p
        for i in 2..<rope.n where rope.w[i] > 1.02 {
            let r = radius * rope.w[i]
            ctx.fill(Path(ellipseIn: CGRect(x: p[i * 2] - r, y: p[i * 2 + 1] - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }

    private func draw(_ ctx: inout GraphicsContext) {
        guard let rope = holder.rope else { return }
        let k = rope.scale, p = rope.p, world = holder.world
        if room {
            var minX = Double.infinity, maxX = -Double.infinity, low = 0.0
            for i in 0..<rope.n {
                minX = min(minX, p[i * 2])
                maxX = max(maxX, p[i * 2])
                low = max(low, p[i * 2 + 1])
            }
            let lift = max(0, world.floor - low - 15 * k), sw = (maxX - minX) * 0.5 + 20 * k
            let rx = sw * max(0.5, 1 - lift / (2 * rope.size)), ry = 9 * k * 0.5
            ctx.fill(Path(ellipseIn: CGRect(x: (minX + maxX) / 2 - rx, y: world.floor - 2 - ry, width: rx * 2, height: ry * 2)),
                     with: .color(Theme.plum.opacity(0.16 * max(0.25, 1 - lift / rope.size))))
        }
        let line = spine(rope)
        let round = { (width: Double) in StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round) }
        ctx.stroke(line, with: .color(RopeSquishy.ink), style: round(31 * k))
        bulges(rope, 15.5 * k, RopeSquishy.ink, &ctx)
        ctx.stroke(line, with: .color(RopeSquishy.pink), style: round(24 * k))
        bulges(rope, 12 * k, RopeSquishy.pink, &ctx)
        // The stripes stretch with him.
        let grow = rope.restLen > 0 ? rope.length / rope.restLen : 1
        ctx.stroke(line, with: .color(.white.opacity(0.85)),
                   style: StrokeStyle(lineWidth: 24 * k, lineCap: .butt, lineJoin: .round, dash: [7 * k * grow, 11 * k * grow]))

        // The head, on top, turning with his neck.
        var turn = rope.headTurn()
        while turn > Double.pi { turn -= 2 * Double.pi }
        while turn < -Double.pi { turn += 2 * Double.pi }
        let c = cos(turn), s = sin(turn)
        let hx = p[0] + (-4 * c + 2 * s) * k, hy = p[1] + (-4 * s - 2 * c) * k
        let m = rope.metric
        var head = ctx
        head.translateBy(x: hx, y: hy)
        head.rotate(by: .radians(max(-0.6, min(0.6, turn * 0.5))))
        head.scaleBy(x: k, y: k)
        let ink = GraphicsContext.Shading.color(RopeSquishy.ink)
        var tongue = Path()
        tongue.move(to: CGPoint(x: -20, y: 4)); tongue.addLine(to: CGPoint(x: -28, y: 6))
        tongue.move(to: CGPoint(x: -20, y: 4)); tongue.addLine(to: CGPoint(x: -27, y: 9))
        head.stroke(tongue, with: ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        let face = Path(ellipseIn: CGRect(x: -21, y: -21, width: 42, height: 42))
        head.fill(face, with: .color(RopeSquishy.pink))
        head.stroke(face, with: ink, lineWidth: 3.5)
        head.fill(face, with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.75), location: 0),
                                                                .init(color: .white.opacity(0), location: 0.38)]),
                                              center: CGPoint(x: -6.3, y: -6.3), startRadius: 0, endRadius: 34))
        let pen = StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
        if m.squash > 0.08 {
            // A happy squint while he is squeezed.
            var eyes = Path()
            eyes.move(to: CGPoint(x: -11, y: -2)); eyes.addQuadCurve(to: CGPoint(x: -3, y: -2), control: CGPoint(x: -7, y: -7))
            eyes.move(to: CGPoint(x: 5, y: -2)); eyes.addQuadCurve(to: CGPoint(x: 13, y: -2), control: CGPoint(x: 9, y: -7))
            head.stroke(eyes, with: ink, style: pen)
        } else {
            for x in [-7.0, 9.0] {
                head.fill(Path(ellipseIn: CGRect(x: x - 5.5, y: -7.5, width: 11, height: 11)), with: ink)
                head.fill(Path(ellipseIn: CGRect(x: x - 1.8 - 1.9, y: -5.9, width: 3.8, height: 3.8)), with: .color(.white))
            }
        }
        if m.unravel > 0.55 {
            // "Ooh!"
            head.fill(Path(ellipseIn: CGRect(x: 1 - 3.2, y: 4, width: 6.4, height: 8)), with: ink)
        } else {
            var smile = Path()
            smile.move(to: CGPoint(x: -4, y: 6)); smile.addQuadCurve(to: CGPoint(x: 6, y: 6), control: CGPoint(x: 1, y: 11))
            head.stroke(smile, with: ink, style: pen)
        }
    }
}
