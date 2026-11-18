import SwiftUI
import SquishSoft

/// Every squishy does one cool thing on top of the normal squish (Content/moves.json, from the
/// design thread's signature-moves-spec). Moves are for show only: the Squish Room, the squishy
/// card, the Buddy and the reveal. They never change play, coins or drops.
struct MoveSpec {
    let effect: String
    private let raw: [String: Any]

    init?(_ raw: [String: Any]) {
        guard let effect = raw["effect"] as? String else { return nil }
        self.effect = effect
        self.raw = raw
    }

    func num(_ key: String) -> Double? { (raw[key] as? NSNumber)?.doubleValue }
    func str(_ key: String) -> String? { raw[key] as? String }
    func flag(_ key: String) -> Bool { (raw[key] as? Bool) ?? false }
    func point(_ key: String) -> (x: Double, y: Double)? {
        guard let a = raw[key] as? [NSNumber], a.count >= 2 else { return nil }
        return (a[0].doubleValue, a[1].doubleValue)
    }
    func numbers(_ key: String) -> [Double] { (raw[key] as? [NSNumber])?.map(\.doubleValue) ?? [] }
    func strings(_ key: String) -> [String] { raw[key] as? [String] ?? [] }
    func dict(_ key: String) -> [String: Any]? { raw[key] as? [String: Any] }
    var limbs: [[String: Any]] { raw["limbs"] as? [[String: Any]] ?? [] }
}

/// The moves file, read once.
final class SignatureMoves {
    static let shared = SignatureMoves()
    private var moves: [String: [MoveSpec]] = [:]
    private var dy: [String: Double] = [:]
    private var materials: [String: SquishRope.Material] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "moves", withExtension: "json", subdirectory: "Content"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (id, list) in file["moves"] as? [String: [[String: Any]]] ?? [:] {
            moves[id] = list.compactMap(MoveSpec.init)
        }
        for (id, value) in file["dy"] as? [String: NSNumber] ?? [:] { dy[id] = value.doubleValue }
        for (name, m) in file["limbMaterials"] as? [String: [String: NSNumber]] ?? [:] {
            materials[name] = SquishRope.Material(k: m["k"]?.doubleValue ?? 700, heldK: m["heldK"]?.doubleValue ?? 0.05,
                                                  curl: m["curl"]?.doubleValue ?? 0.1, smax: m["smax"]?.doubleValue ?? 1.8,
                                                  damp: m["damp"]?.doubleValue ?? 2, grav: m["grav"]?.doubleValue ?? 4)
        }
    }

    /// The effects this build can play for a squishy. The ribbon rope (Tapey) is not built yet.
    func moves(for id: String) -> [MoveSpec] {
        (moves[id] ?? []).filter { !($0.effect == "ROPE" && $0.str("body") != "taffy") && $0.effect != "SHIFT" }
    }

    func seat(_ id: String) -> Double { dy[id] ?? 0 }
    func material(_ name: String?) -> SquishRope.Material { materials[name ?? "tail"] ?? .trunk }

    /// The whole body is a rope (Taffy Snake).
    func isRope(_ id: String) -> Bool { moves(for: id).contains { $0.effect == "ROPE" } }

    /// The art with its moving part taken off, when the move brings its own part.
    func baseArt(for id: String) -> String? {
        guard !moves(for: id).isEmpty else { return nil }
        let name = "move-\(id)-base"
        return UIImage(named: name) == nil ? nil : name
    }
}

/// What the soft body is doing right now, for the moves drawn over it.
struct SquishPulse: Equatable {
    /// 0 at rest, 1 at a full squeeze.
    var squeeze = 0.0
    var held = false
    /// The middle of the body in the view, its side, and how far it has turned.
    var x = 0.0
    var y = 0.0
    var side = 0.0
    var angle = 0.0
}

/// Carries the pulse from the scene to the moves. Only `held` and `awake` redraw SwiftUI.
final class MovePulse: ObservableObject {
    @Published var held = false
    @Published var awake = false
    var value = SquishPulse()
    /// What the layers last drew. They wake again once the body has moved on from it.
    var shown = SquishPulse()

    func take(_ next: SquishPulse) {
        value = next
        if next.held != held { held = next.held }
        guard !awake else { return }
        let moved = abs(next.x - shown.x) + abs(next.y - shown.y) > 0.5 || abs(next.angle - shown.angle) > 0.004
            || abs(next.side - shown.side) > 1
        if next.held || next.squeeze > 0.05 || moved { awake = true }
    }
}

extension Color {
    /// "#FFAA00" from the moves file.
    init(css: String?, fallback: Color = .white) {
        guard let css, css.hasPrefix("#"), let v = UInt32(css.dropFirst(), radix: 16) else { self = fallback; return }
        self = Color(uiColor: UIColor(hex: v))
    }
}

/// The little engine behind the moves that are drawn: particles, glow, the lifted part, limbs.
/// Stepped once a frame by the front layer.
final class MoveSim {
    struct Particle {
        var x: Double, y: Double, vx: Double, vy: Double
        var life: Double, span: Double
        var color: Color
        var glyph: String?
        var size: Double
        var gravity: Double
    }
    struct Limb {
        let rope: SquishRope
        let width: Double
        let taper: Double
        let fill: Color
        let outline: Color?
        let behind: Bool
        let tipFill: Color?
        let tipLength: Double
    }

    let id: String
    let specs: [MoveSpec]
    let dy: Double
    var pulse = SquishPulse()
    var particles: [Particle] = []
    var level = 0.0
    var glow = 0.0
    var hue = 0.0
    /// The lifted or hinged part: 0 down, 1 fully up. A spring, so it bounces on the way down.
    var lift = 0.0
    private var liftSpeed = 0.0
    var spin = 0.0
    private var spinning = false
    var melt = 0.0
    var limbs: [Limb] = []
    private var orbit: [(angle: Double, radius: Double, speed: Double)] = []
    private var wasHeld = false
    private var holdTime = 0.0
    private var peak = 0.0
    private var last: Date?
    private var quiet = 0.0
    private var lastSound = Date.distantPast
    var reduceMotion = false
    var play: (String, String) -> Void = { _, _ in }
    var tick: (Bool) -> Void = { _ in }

    init(id: String, specs: [MoveSpec]) {
        self.id = id
        self.specs = specs
        dy = SignatureMoves.shared.seat(id)
    }

    /// An art point (120-unit box) in the view, riding on the body.
    func place(_ a: (x: Double, y: Double), lifted: Double = 0) -> CGPoint {
        let u: Double = pulse.side / 120
        let lx: Double = (a.x - 60) * u
        let ly: Double = (a.y + dy - 60 - lifted) * u
        let c: Double = cos(pulse.angle), s: Double = sin(pulse.angle)
        let x: Double = pulse.x + c * lx - s * ly
        let y: Double = pulse.y + s * lx + c * ly
        return CGPoint(x: x, y: y)
    }

    private func buildLimbs() {
        guard limbs.isEmpty, pulse.side > 10 else { return }
        for spec in specs where spec.effect == "LIMB" {
            for l in spec.limbs {
                guard let spine = (l["spine"] as? [[NSNumber]])?.map({ $0.map(\.doubleValue) }), spine.count >= 2 else { continue }
                let first = (x: spine[0][0], y: spine[0][1])
                let rope = SquishRope(points: spine, n: 8, size: pulse.side, radius: 4, headR: 4,
                                      material: SignatureMoves.shared.material(l["material"] as? String),
                                      root: { [unowned self] in
                                          let at = self.place(first)
                                          return SquishRope.Root(x: at.x, y: at.y, a: self.pulse.angle)
                                      })
                let at = place(first)
                rope.place(x: at.x, y: at.y)
                let tip = l["tip"] as? [String: Any]
                limbs.append(Limb(rope: rope, width: (l["width"] as? NSNumber)?.doubleValue ?? 10,
                                  taper: (l["taper"] as? NSNumber)?.doubleValue ?? 1,
                                  fill: Color(css: l["fill"] as? String), outline: (l["outline"] as? String).map { Color(css: $0) },
                                  behind: (l["behind"] as? Bool) ?? false,
                                  tipFill: (tip?["fill"] as? String).map { Color(css: $0) },
                                  tipLength: (tip?["length"] as? NSNumber)?.doubleValue ?? 0))
            }
        }
    }

    /// One frame. Returns false once everything has come to rest, so the layer can stop drawing.
    func advance(to now: Date, pulse next: SquishPulse) -> Bool {
        let dt = min(1.0 / 20, max(0, now.timeIntervalSince(last ?? now)))
        last = now
        let moved = abs(next.x - pulse.x) + abs(next.y - pulse.y) > 0.5 || abs(next.angle - pulse.angle) > 0.004
        // A new size (a rotated phone, a new place): the limbs are made again for it.
        if abs(next.side - pulse.side) > 1 { limbs = [] }
        pulse = next
        buildLimbs()
        let held = next.held
        if held && !wasHeld { pressed() }
        if !held && wasHeld { released() }
        wasHeld = held
        holdTime = held ? holdTime + dt : 0
        peak = held ? max(peak, next.squeeze) : peak
        let target = held ? next.squeeze : 0
        level += (target - level) * min(1, dt * 10)
        glow += (target - glow) * min(1, dt * (held ? 12 : 1.4))
        // The part rides up with the squeeze and drops back on a spring.
        let k = 170.0, c = held ? 22.0 : 9.0
        liftSpeed += ((target - lift) * k - liftSpeed * c) * dt
        lift += liftSpeed * dt
        if spinning {
            spin += dt / 0.6
            if spin >= 1 { spin = 0; spinning = false }
        }
        // A melt starts after a second of holding and pulls itself back together on release.
        let melting = held && holdTime > 1 && specs.contains { $0.effect == "MELT" }
        melt += ((melting ? 1 : 0) - melt) * min(1, dt * (melting ? 1.2 : 5))
        for i in particles.indices {
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].vy += particles[i].gravity * dt
            particles[i].life -= dt
        }
        particles.removeAll { $0.life <= 0 }
        swirl(dt, held: held)
        for limb in limbs {
            for _ in 0..<4 { limb.rope.step(dt / 4, world: SquishRope.World(floor: 1e9, left: -1e9, right: 1e9)) }
        }
        let busy = held || moved || !particles.isEmpty || glow > 0.02 || abs(lift) > 0.01 || abs(liftSpeed) > 0.05
            || melt > 0.01 || spinning || !orbit.isEmpty
        quiet = busy ? 0 : quiet + dt
        // Limbs take a moment to stop swinging.
        return quiet < (limbs.isEmpty ? 0.3 : 2.5)
    }

    private func pressed() {
        peak = 0
        tick(false)
        for spec in specs where spec.effect == "SOUND" {
            guard Date().timeIntervalSince(lastSound) > 0.7 else { continue }
            lastSound = Date()
            play(spec.str("sound") ?? "", fallback(for: spec.str("sound")))
        }
        if specs.contains(where: { $0.effect == "GLOW" && $0.flag("cycleColours") }) { hue += 67 }
        if specs.contains(where: { $0.effect == "VORTEX" }) {
            let count = reduceMotion ? 4 : 10
            orbit = []
            for i in 0..<count {
                let angle: Double = Double(i) / Double(count) * 2 * Double.pi
                let radius: Double = 0.75 + Double(i % 3) * 0.12
                let speed: Double = 3.2 + Double(i % 4) * 0.5
                orbit.append((angle: angle, radius: radius, speed: speed))
            }
        }
    }

    private func released() {
        tick(true)
        if specs.contains(where: { $0.effect == "LIFT" && $0.flag("spin") }), !reduceMotion, peak > 0.3 {
            spin = 0
            spinning = true
        }
        for spec in specs where spec.effect == "BURST" { burst(spec) }
        // What a vortex pulled in bursts back out.
        if let spec = specs.first(where: { $0.effect == "VORTEX" }) {
            let centre = place(spec.point("centre") ?? (60, 60))
            for o in orbit {
                let speed: Double = pulse.side * 1.6
                let vx: Double = cos(o.angle) * speed, vy: Double = sin(o.angle) * speed
                particles.append(Particle(x: Double(centre.x), y: Double(centre.y), vx: vx, vy: vy,
                                          life: 0.7, span: 0.7, color: Theme.butter, glyph: "✦", size: pulse.side * 0.07, gravity: 0))
            }
            orbit = []
        }
    }

    private func fallback(for sound: String?) -> String {
        switch sound {
        case "bell_ring": return "star_2"
        case "beat_drop": return "combo_2"
        case "keys": return "combo_1"
        case "mic_echo": return "squeak_low"
        case "snore": return "squeeze_out"
        default: return "squeak_mid"
        }
    }

    private func burst(_ spec: MoveSpec) {
        guard peak > 0.25 else { return }
        let from = place(spec.point("at") ?? (60, 40))
        let colors = spec.strings("colors").map { Color(css: $0) }
        let kind = spec.str("particle") ?? ""
        let glyph: String?
        switch kind {
        case "hearts": glyph = "♥"
        case "notes": glyph = "♪"
        case "stars", "sparkles", "glitter": glyph = "✦"
        case "smoke-rings": glyph = "○"
        default: glyph = nil
        }
        let floaty = ["steam", "smoke-rings", "spores", "feathers", "notes", "hearts"].contains(kind)
        var count = Int(spec.num("count") ?? 10)
        if reduceMotion { count = max(3, count / 3) }
        let u = pulse.side / 120
        for i in 0..<count {
            // A fan upwards, wider for the heavy things.
            let spread = floaty ? 0.9 : 1.25
            let share: Double = Double(i) / Double(max(1, count - 1)) - 0.5
            let jitter: Double = Double.random(in: -0.12...0.12)
            let a: Double = -Double.pi / 2 + share * 2 * spread + jitter
            let fast: ClosedRange<Double> = floaty ? 40...80 : 90...170
            let long: ClosedRange<Double> = floaty ? 1.0...1.5 : 0.7...1.1
            let small: ClosedRange<Double> = glyph == nil ? 5...8 : 12...17
            let speed: Double = u * Double.random(in: fast)
            let life: Double = Double.random(in: long)
            let grain: Double = u * Double.random(in: small)
            let pull: Double = floaty ? -u * 20 : u * 260
            particles.append(Particle(x: Double(from.x), y: Double(from.y), vx: cos(a) * speed, vy: sin(a) * speed,
                                      life: life, span: life, color: colors.isEmpty ? .white : colors[i % colors.count],
                                      glyph: glyph, size: grain, gravity: pull))
        }
    }

    private func swirl(_ dt: Double, held: Bool) {
        guard held, !orbit.isEmpty else { return }
        for i in orbit.indices {
            orbit[i].angle += orbit[i].speed * dt
            orbit[i].radius -= dt * 0.45
            // Sucked in: it comes round again from outside.
            if orbit[i].radius < 0.08 { orbit[i].radius = 0.85 }
        }
    }

    /// Where the swirling stars are, for the drawer.
    func orbiters() -> [(at: CGPoint, scale: Double)] {
        guard let spec = specs.first(where: { $0.effect == "VORTEX" }) else { return [] }
        let centre = place(spec.point("centre") ?? (60, 60))
        var out: [(at: CGPoint, scale: Double)] = []
        for o in orbit {
            let x: Double = Double(centre.x) + cos(o.angle) * o.radius * pulse.side * 0.7
            let y: Double = Double(centre.y) + sin(o.angle) * o.radius * pulse.side * 0.55
            out.append((at: CGPoint(x: x, y: y), scale: 0.4 + o.radius))
        }
        return out
    }
}

/// The drawn part of the moves, over (or just behind) the soft body. It never takes a touch.
@MainActor
struct MoveLayer: View {
    let sim: MoveSim
    @ObservedObject var pulse: MovePulse
    /// The layer under the body draws what hangs behind it; the one on top steps the engine.
    let behind: Bool
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !pulse.awake)) { timeline in
            Canvas { ctx, _ in
                if !behind { step(timeline.date) }
                guard sim.pulse.side > 10 else { return }
                if behind { drawPuddle(&ctx) }
                for limb in sim.limbs where limb.behind == behind { draw(limb, &ctx) }
                if !behind {
                    drawParts(&ctx)
                    drawGlow(&ctx)
                    drawParticles(&ctx)
                }
            } symbols: {
                if let part = partImage { Image(part).resizable().tag(0) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var partImage: String? {
        let name = "move-\(sim.id)-part"
        return UIImage(named: name) == nil ? nil : name
    }

    private func step(_ date: Date) {
        sim.reduceMotion = reduceMotion
        sim.play = { [weak model] name, other in model?.sounds.play(name, or: other) }
        sim.tick = { [weak model] strong in if strong { model?.haptics.land() } else { model?.haptics.lift() } }
        let pulse = self.pulse
        pulse.shown = pulse.value
        if !sim.advance(to: date, pulse: pulse.value) {
            DispatchQueue.main.async { if !pulse.held, pulse.awake { pulse.awake = false } }
        }
    }

    /// A lifted part (hat, glasses, lid) or one that opens on a hinge, drawn in the layer's own frame.
    private func drawParts(_ ctx: inout GraphicsContext) {
        guard let image = ctx.resolveSymbol(id: 0) else { return }
        let p = sim.pulse, u = p.side / 120
        let frame = p.side * 128 / 120
        for spec in sim.specs where spec.effect == "LIFT" || spec.effect == "SPLIT" {
            var part = ctx
            part.translateBy(x: p.x, y: p.y)
            part.rotate(by: .radians(p.angle))
            let up = max(-0.15, sim.lift)
            if spec.effect == "LIFT" {
                let anchor = spec.point("anchor") ?? (60, 40)
                let ax = (anchor.x - 60) * u, ay = (anchor.y + sim.dy - 60) * u
                part.translateBy(x: 0, y: -(spec.num("lift") ?? 18) * u * up)
                // On the way down it spins once round where it sits, or flips like a card.
                part.translateBy(x: ax, y: ay)
                if spec.flag("flip") || spec.str("pivot") == "flip-up" {
                    part.scaleBy(x: cos(up * Double.pi), y: 1)
                } else if sim.spin > 0 {
                    let t = sim.spin
                    part.rotate(by: .radians((1 - (1 - t) * (1 - t)) * 2 * Double.pi))
                }
                part.translateBy(x: -ax, y: -ay)
            } else if let hinge = spec.point("hinge") {
                let hx = (hinge.x - 60) * u, hy = (hinge.y + sim.dy - 60) * u
                part.translateBy(x: hx, y: hy)
                part.rotate(by: .degrees(-(spec.num("open") ?? 30) * up))
                part.translateBy(x: -hx, y: -hy)
            } else {
                // The cream variant: the top pulls away and the cream stretches after it.
                let anchor = spec.point("anchor") ?? (60, 70)
                let pull = (spec.num("maxPull") ?? 0.4) * p.side * max(0, up)
                if pull > 2 {
                    let ax = (anchor.x - 60) * u, ay = (anchor.y + sim.dy - 60) * u
                    var strand = Path()
                    strand.move(to: CGPoint(x: ax, y: ay))
                    strand.addLine(to: CGPoint(x: ax, y: ay - pull))
                    let width = max(8, 46 * u * (1 - 0.6 * max(0, up)))
                    // A dark edge down both sides, like the art's own outline, so the cream shows on any
                    // background (it is nearly the colour of the Cream room).
                    part.stroke(strand, with: .color(Theme.plum), style: StrokeStyle(lineWidth: width + 5 * u, lineCap: .butt))
                    part.stroke(strand, with: .color(Color(uiColor: UIColor(hex: 0xFFF4E8))), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
                part.translateBy(x: 0, y: -pull)
            }
            part.draw(image, in: CGRect(x: -frame / 2, y: -frame / 2, width: frame, height: frame))
        }
    }

    private func drawGlow(_ ctx: inout GraphicsContext) {
        guard sim.glow > 0.02 else { return }
        let u = sim.pulse.side / 120
        for spec in sim.specs where spec.effect == "GLOW" {
            let at = sim.place(spec.point("at") ?? (60, 50))
            let base: Double = spec.num("radius") ?? 20
            let r: Double = base * u * (1.4 + sim.glow * 0.8)
            var light = ctx
            light.blendMode = .plusLighter
            if spec.flag("cycleColours") { light.addFilter(.hueRotation(.degrees(sim.hue))) }
            let color = Color(css: spec.str("color"), fallback: Theme.butter)
            light.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)),
                       with: .radialGradient(Gradient(colors: [color.opacity(0.9 * sim.glow), color.opacity(0)]),
                                             center: at, startRadius: 0, endRadius: r))
        }
    }

    private func drawParticles(_ ctx: inout GraphicsContext) {
        for o in sim.orbiters() {
            ctx.draw(Text(verbatim: "✦").font(.system(size: sim.pulse.side * 0.08 * o.scale)).foregroundColor(Theme.butter), at: o.at)
        }
        for p in sim.particles {
            let fade = min(1, p.life / (p.span * 0.4))
            if let glyph = p.glyph {
                ctx.draw(Text(verbatim: glyph).font(.system(size: p.size, weight: .bold)).foregroundColor(p.color.opacity(fade)),
                         at: CGPoint(x: p.x, y: p.y))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - p.size / 2, y: p.y - p.size / 2, width: p.size, height: p.size)),
                         with: .color(p.color.opacity(fade)))
            }
        }
    }

    /// A melt leaves a glossy puddle under the toy, with a drip or two.
    private func drawPuddle(_ ctx: inout GraphicsContext) {
        guard sim.melt > 0.02, let spec = sim.specs.first(where: { $0.effect == "MELT" }) else { return }
        let p = sim.pulse
        let color = Color(css: spec.str("puddle"), fallback: Theme.butter)
        let w: Double = p.side * (0.7 + 0.7 * sim.melt), h: Double = p.side * 0.16 * sim.melt
        let floor: Double = p.y + p.side * 0.5 * (1 - 0.4 * sim.melt)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - w / 2, y: floor - h / 2, width: w, height: h)), with: .color(color.opacity(0.9)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - w * 0.3, y: floor - h * 0.35, width: w * 0.25, height: h * 0.25)),
                 with: .color(.white.opacity(0.5)))
        let u = p.side / 120
        for x in spec.numbers("drips") {
            let dx: Double = p.x + (x - 60) * u * 1.3
            let r: Double = 3.5 * u * sim.melt
            let top: Double = floor - h * 0.2 - r * 3 * (1 - sim.melt)
            ctx.fill(Path(ellipseIn: CGRect(x: dx - r, y: top, width: r * 2, height: r * 2.6)),
                     with: .color(color))
        }
    }

    /// A floppy tail, ear or tentacle: round strokes along the chain, thinner towards the tip.
    private func draw(_ limb: MoveSim.Limb, _ ctx: inout GraphicsContext) {
        let rope = limb.rope, n = rope.n, u = sim.pulse.side / 120
        func at(_ i: Int) -> CGPoint { CGPoint(x: rope.p[i * 2], y: rope.p[i * 2 + 1]) }
        func strokes(_ color: Color, inset: Double, from: Int = 0) {
            for i in max(0, from)..<(n - 1) {
                let t = Double(i) / Double(n - 1)
                let wide: Double = limb.width * (1 + (limb.taper - 1) * t) - inset
                let width: Double = max(1.5, wide * u)
                var seg = Path()
                seg.move(to: at(i))
                seg.addLine(to: at(i + 1))
                ctx.stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        if let outline = limb.outline {
            strokes(outline, inset: 0)
            strokes(limb.fill, inset: 6)
        } else {
            strokes(limb.fill, inset: 0)
        }
        if let tip = limb.tipFill, limb.tipLength > 0 {
            strokes(tip, inset: limb.outline == nil ? 0 : 6, from: Int(Double(n - 1) * (1 - limb.tipLength)))
        }
    }
}

/// The moves that change the whole toy: puffing up, melting flat, and tap tricks.
struct MoveBodyEffect: ViewModifier {
    let specs: [MoveSpec]
    @ObservedObject var pulse: MovePulse
    /// Off for the Buddy on Home, whose taps already mean something.
    var tricks = true
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var puff: CGFloat = 1
    @State private var flatX: CGFloat = 1
    @State private var flatY: CGFloat = 1
    @State private var spin = 0.0
    @State private var flip = 0.0
    @State private var hop: CGFloat = 0
    @State private var chomp: CGFloat = 0
    @State private var pressedAt = Date.distantPast
    @State private var press = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(puff)
            .scaleEffect(x: flatX * (1 + chomp), y: flatY * (1 - chomp), anchor: .bottom)
            .rotationEffect(.degrees(spin))
            .modifier(FlipEffect(turn: flip))
            .offset(y: hop)
            .onChange(of: pulse.held) { _, held in held ? pressed() : released() }
    }

    private func pressed() {
        pressedAt = Date()
        press += 1
        let mine = press
        if let spec = specs.first(where: { $0.effect == "PUFF" }) {
            // Bigger the longer it is held.
            withAnimation(.easeOut(duration: 1.6)) { puff = CGFloat(spec.num("scale") ?? 1.2) }
        }
        if let spec = specs.first(where: { $0.effect == "MELT" }) {
            let form = spec.dict("form")
            let sx = (form?["sx"] as? NSNumber)?.doubleValue ?? 1.35, sy = (form?["sy"] as? NSNumber)?.doubleValue ?? 0.55
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard pulse.held, press == mine else { return }
                withAnimation(.easeInOut(duration: 1.3)) { flatX = CGFloat(sx); flatY = CGFloat(sy) }
            }
        }
    }

    private func released() {
        if let spec = specs.first(where: { $0.effect == "PUFF" }) {
            let wobble = spec.num("wobble") ?? 1
            withAnimation(.spring(response: 0.38, dampingFraction: max(0.18, 0.42 / max(0.5, wobble)))) { puff = 1 }
        }
        if flatX != 1 || flatY != 1 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.4)) { flatX = 1; flatY = 1 }
        }
        // A quick tap is a trick.
        if tricks, Date().timeIntervalSince(pressedAt) < 0.28, let spec = specs.first(where: { $0.effect == "TRICK" }) {
            trick(spec.str("trick") ?? "hop")
        }
    }

    private func trick(_ name: String) {
        guard spin == 0, flip == 0, hop == 0, chomp == 0 else { return }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { hop = -12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { withAnimation(.easeIn(duration: 0.2)) { hop = 0 } }
            return
        }
        switch name {
        case "spin":
            withAnimation(.easeInOut(duration: 0.6)) { spin = 360 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { spin = 0 }
        case "flap", "belly-slide":
            withAnimation(.easeInOut(duration: 0.7)) { flip = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { flip = 0 }
        case "roar", "chomp", "wink":
            // A quick open-and-shut: wide and short, twice.
            withAnimation(.easeInOut(duration: 0.11).repeatCount(4, autoreverses: true)) { chomp = 0.16 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { withAnimation(.easeOut(duration: 0.1)) { chomp = 0 } }
        default:
            withAnimation(.easeOut(duration: 0.18)) { hop = -34 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.interpolatingSpring(stiffness: 260, damping: 9)) { hop = 0 }
            }
        }
    }
}
