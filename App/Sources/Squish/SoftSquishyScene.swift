import CoreMotion
import SpriteKit
import UIKit
import SquishSoft
import SquishPolicy

/// Where the art is, sampled from its transparency, so only the toy itself is soft.
struct SquishMask {
    private static let n = 64
    private let alpha: [UInt8]
    /// Where the art's lowest pixel sits, 0 (top) to 1 (bottom).
    let footV: Double
    /// The toy's puffy rest shape for the light (`SquishBody.heightField`), `restSize` a side, top row first.
    let rest: [UInt8]
    static let restSize = 128

    /// The picture's transparency at `n` by `n`, top row first.
    private static func alpha(of image: CGImage, side n: Int) -> [UInt8]? {
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let raw = ctx.data else { return nil }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var alpha = [UInt8](repeating: 0, count: n * n)
        // The first row in memory is the top of the picture.
        for i in 0..<(n * n) { alpha[i] = pixels[i * 4 + 3] }
        return alpha
    }

    private static var boxes: [String: CGRect] = [:]

    /// The part of a toy's picture that is not see-through, as shares of the picture (top left origin).
    /// Pictures come with different margins, so anything that stacks toys lines them up by this.
    static func opaqueBox(named name: String) -> CGRect {
        if let known = boxes[name] { return known }
        var box = CGRect(x: 0, y: 0, width: 1, height: 1)
        let n = SquishMask.n
        if let cg = UIImage(named: name)?.cgImage, let alpha = SquishMask.alpha(of: cg, side: n) {
            var x0 = n, x1 = -1, y0 = n, y1 = -1
            for y in 0..<n {
                for x in 0..<n where alpha[y * n + x] > 40 {
                    x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                }
            }
            if x1 >= x0, y1 >= y0 {
                box = CGRect(x: Double(x0) / Double(n), y: Double(y0) / Double(n),
                             width: Double(x1 - x0 + 1) / Double(n), height: Double(y1 - y0 + 1) / Double(n))
            }
        }
        boxes[name] = box
        return box
    }

    init?(image: UIImage) {
        let n = SquishMask.n
        guard let cg = image.cgImage, let alpha = SquishMask.alpha(of: cg, side: n),
              let fine = SquishMask.alpha(of: cg, side: SquishMask.restSize) else { return nil }
        self.alpha = alpha
        rest = SquishBody.heightField(alpha: fine, size: SquishMask.restSize)
        var foot = 1.0
        search: for y in stride(from: n - 1, through: 0, by: -1) {
            for x in 0..<n where alpha[y * n + x] > 60 {
                foot = Double(y + 1) / Double(n)
                break search
            }
        }
        footV = foot
    }

    func inside(_ u: Double, _ v: Double) -> Bool {
        let n = SquishMask.n
        let x = min(n - 1, max(0, Int((u * Double(n - 1)).rounded())))
        let y = min(n - 1, max(0, Int((v * Double(n - 1)).rounded())))
        return alpha[y * n + x] > 60
    }
}

/// The light on a soft squishy: a port of the fragment shader in the page's `SquishGL`.
/// The toy is shaded as a puffy object from its rest shape, minus the dent, times
/// how thick it is where the lattice is squeezed together; the painted face slides a
/// little; jelly and gel get a wet highlight.
enum SquishLight {
    /// `u_hm` rest shape, `u_zm` surface (`SquishBody.surface`). `u_L` light in the toy's own frame.
    /// `u_m` = (kd, gloss, shin, relief), `u_m2` = (pinch, ao, dent relief, unused),
    /// `u_e` = (1 / rest size, zres - 1, 1 / zres). `u_u` and `u_c0` let the painted face keep
    /// more of its own shape than the outline does (`SquishBody.faceStretch`). Everything is written out in `main`
    /// with no helper functions, which is the form SpriteKit's shader translator is surest of.
    /// `q` counts downwards like the page; the data textures have their first row at 0.
    static let source = """
    void main() {
        vec2 q = vec2(v_tex_coord.x, 1.0 - v_tex_coord.y);
        float d1 = u_e.x * 1.5;
        float d2 = 1.0 / u_e.y;
        vec4 h0 = texture2D(u_hm, q + vec2(d1, 0.0));
        vec4 h1 = texture2D(u_hm, q - vec2(d1, 0.0));
        vec4 h2 = texture2D(u_hm, q + vec2(0.0, d1));
        vec4 h3 = texture2D(u_hm, q - vec2(0.0, d1));
        vec2 gh = vec2((h0.r - h1.r) * 65280.0 + (h0.g - h1.g) * 255.0, (h2.r - h3.r) * 65280.0 + (h2.g - h3.g) * 255.0) / 65535.0 / (2.0 * d1);
        vec4 z0 = texture2D(u_zm, ((q + vec2(d2, 0.0)) * u_e.y + 0.5) * u_e.z);
        vec4 z1 = texture2D(u_zm, ((q - vec2(d2, 0.0)) * u_e.y + 0.5) * u_e.z);
        vec4 z2 = texture2D(u_zm, ((q + vec2(0.0, d2)) * u_e.y + 0.5) * u_e.z);
        vec4 z3 = texture2D(u_zm, ((q - vec2(0.0, d2)) * u_e.y + 0.5) * u_e.z);
        vec2 gz = vec2((z0.r - z1.r) * 65280.0 + (z0.g - z1.g) * 255.0, (z2.r - z3.r) * 65280.0 + (z2.g - z3.g) * 255.0) / 65535.0 * 4.0 / (2.0 * d2);
        vec4 zc = texture2D(u_zm, (q * u_e.y + 0.5) * u_e.z);
        float z = (zc.r * 65280.0 + zc.g * 255.0) / 65535.0 * 4.0 - 2.0;
        float th = zc.b * 2.0;
        vec4 hh = texture2D(u_hm, q);
        vec2 dq = q - u_c0;
        vec2 p = q + hh.b * vec2(u_u.x * dq.x + u_u.y * dq.y, u_u.y * dq.x + u_u.z * dq.y) - u_tilt * hh.b - u_m2.x * gz * hh.b;
        vec4 a = texture2D(u_texture, vec2(p.x, 1.0 - p.y));
        vec2 g = gh * th * u_m.w - gz * u_m2.z;
        vec3 N = normalize(vec3(-g, 1.0));
        float nl = dot(N, u_L) - u_L.z;
        float al = max(a.a, 0.0001);
        vec3 c = a.rgb / al;
        float ink = smoothstep(0.1, 0.38, dot(c, vec3(0.3, 0.59, 0.11)));
        float zin = clamp(z, 0.0, 1.2);
        float sh = clamp(-nl * u_m.x, 0.0, 0.7) + zin * u_m2.y;
        c = mix(c, c * c * vec3(0.8, 0.62, 0.7), clamp(sh, 0.0, 0.85));
        c += ink * clamp(nl * u_m.x, 0.0, 0.6) * (1.0 - 0.5 * min(zin, 1.0)) * (vec3(1.0, 0.98, 0.94) - c) * 0.75;
        vec3 Hv = normalize(u_L + vec3(0.0, 0.0, 1.0));
        float sp = pow(max(dot(N, Hv), 0.0), u_m.z);
        c += ink * u_m.y * smoothstep(0.25, 0.95, sp) * (vec3(1.0) - c) * 0.85;
        gl_FragColor = vec4(clamp(c, 0.0, 1.0) * a.a, a.a) * v_color_mix.a;
    }
    """
}

/// Soft squishies. Each body is a `SquishBody` (the page's engine, ported); this
/// draws it by warping its sprite over the body's lattice each frame, and
/// passes fingers, sound and haptics in and out. Most places show one toy; the
/// Squish Room can hold a few, and they bump into each other.
final class SoftSquishyScene: SKScene {
    enum Mode {
        /// Squish Room: knead, pull, pinch, pick up, drop and throw, with a floor and walls.
        case room
        /// Buddy, capsule reveal, Maker: press and let go only.
        case pressOnly
    }

    /// One toy to show: which it is, its picture and how it feels.
    struct Toy {
        let id: String
        let image: UIImage
        let feel: SquishFeel
        /// Its quick-tap trick from the moves file ("spin", "hop"...), if it has one.
        var trick: String?
    }

    /// Everything one toy on screen needs.
    private final class Piece {
        let id: String
        var image: UIImage
        var feel: SquishFeel
        var trick: String?
        let mask: SquishMask?
        var body: SquishBody?
        let sprite = SKSpriteNode()
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 100, height: 18))
        var mixer = SquishSoundMixer()
        /// A let-go dent that has not popped out past flat yet (jelly's light tap).
        var waitsForPop = false
        /// Seconds the toy has sat untouched and settled.
        var stillFor = 0.0
        var shader: SKShader?
        let lightUniform = SKUniform(name: "u_L", vectorFloat3: SIMD3<Float>(-0.46, -0.62, 0.64))
        let tiltUniform = SKUniform(name: "u_tilt", vectorFloat2: SIMD2<Float>(0, 0))
        let lookUniform = SKUniform(name: "u_m", vectorFloat4: SIMD4<Float>(0.5, 0, 30, 0.2))
        let dentUniform = SKUniform(name: "u_m2", vectorFloat4: SIMD4<Float>(0.004, 0.15, 0.3, 1))
        let sizeUniform = SKUniform(name: "u_e", vectorFloat3: SIMD3<Float>(1.0 / 128, 96, 1.0 / 97))
        let faceUniform = SKUniform(name: "u_u", vectorFloat3: SIMD3<Float>(0, 0, 0))
        let centreUniform = SKUniform(name: "u_c0", vectorFloat2: SIMD2<Float>(0.5, 0.5))
        let restUniform = SKUniform(name: "u_hm", texture: nil)
        let surfaceUniform = SKUniform(name: "u_zm", texture: nil)

        init(toy: Toy) {
            id = toy.id
            image = toy.image
            feel = toy.feel
            trick = toy.trick
            mask = SquishMask(image: toy.image)
            sprite.texture = SKTexture(image: toy.image)
            shadow.fillColor = UIColor(red: 0.23, green: 0.16, blue: 0.35, alpha: 1)
            shadow.strokeColor = .clear
            shadow.zPosition = -1
            shadow.isHidden = true
        }
    }

    var mode = Mode.pressOnly
    /// The Buddy on Home: once thrown and settled, it slides back to the middle.
    var comesHome = false
    var reduceMotion = false
    var soundOn: () -> Bool = { true }
    var hapticsOn: () -> Bool = { true }
    var sounds: SquishSound?
    var haptics: SquishHaptics?
    /// A finger landed on a toy.
    var onTouch: (() -> Void)?
    /// The last finger left the main toy; the number is how deep the squeeze was (`metric.D`).
    var onLetGo: ((Double) -> Void)?
    var onDoubleTap: (() -> Void)?
    /// A finger drew a trick (a flick up, a circle). True if a trick was done, so the toy is not also thrown.
    var onGesture: ((TrickGesture) -> Bool)?
    /// Each frame: where the main body is and how hard it is squeezed, for the signature moves drawn over it.
    var onPulse: ((SquishPulse) -> Void)?
    /// The same for each of the other toys in the room, by id.
    var onMatePulse: ((String, SquishPulse) -> Void)?
    /// Each finger's path since it went down, on or beside the toy.
    private var paths: [Int: (points: [(x: Double, y: Double)], began: TimeInterval)] = [:]

    private let tuning = SquishTuning.standard
    /// The toys on screen. The first is the main one: it has the signature moves, the tricks and the pokes.
    private var pieces: [Piece] = []
    /// The toy last touched: the one that is heard and felt.
    private weak var active: Piece?
    private var body: SquishBody? { pieces.first?.body }
    private var world = SquishBody.World(floor: 0, left: 0, right: 0)
    private var side = 0.0
    private var source: [SIMD2<Float>] = []
    private var lastTime: TimeInterval = 0
    private var carried = 0.0
    private var rng = SystemRandomNumberGenerator()
    private var touchTimes: [Int: TimeInterval] = [:]
    /// Which toy each finger is on.
    private var touchOwner: [Int: Piece] = [:]
    private var pokeEnds: TimeInterval?
    private static let pokeID = -1
    /// Where each finger went down, and how big its contact patch was then.
    private var touchStarts: [Int: (x: Double, y: Double, radius: Double)] = [:]
    /// When each finger went down, to tell a quick tap from a squeeze.
    private var touchBegan: [Int: TimeInterval] = [:]
    private var drawTick = 0
    private let motion = SquishMotion.shared

    override init() {
        super.init(size: CGSize(width: 300, height: 300))
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        view.allowsTransparency = true
    }

    override func willMove(from view: SKView) { goQuiet() }

    override func didChangeSize(_ oldSize: CGSize) {
        guard abs(oldSize.width - size.width) > 1 || abs(oldSize.height - size.height) > 1 else { return }
        spawn(drop: false, fresh: [], keepPlaces: false)
    }

    /// Goes quiet when the toys leave the screen.
    func goQuiet() {
        for piece in pieces { piece.body?.releaseAll() }
        touchTimes = [:]
        touchStarts = [:]
        touchOwner = [:]
        touchBegan = [:]
        paths = [:]
        motion.stop(self)
        pokeEnds = nil
        sounds?.rest()
        haptics?.letGo()
    }

    // MARK: - What is shown

    /// One toy: new art, new body.
    func show(image: UIImage, feel: SquishFeel, drop: Bool) {
        show(toys: [Toy(id: "", image: image, feel: feel)], fresh: [""], drop: drop)
    }

    /// The toys to show, main one first. A toy named in `fresh` is new and drops in; the others keep
    /// their places on the floor.
    func show(toys: [Toy], fresh: Set<String>, drop: Bool) {
        let old = pieces
        for piece in old {
            piece.sprite.removeFromParent()
            piece.shadow.removeFromParent()
        }
        var next: [Piece] = []
        for toy in toys where !next.contains(where: { $0.id == toy.id }) {
            if !fresh.contains(toy.id), let kept = old.first(where: { $0.id == toy.id }) {
                kept.image = toy.image
                kept.feel = toy.feel
                kept.trick = toy.trick
                kept.sprite.texture = SKTexture(image: toy.image)
                next.append(kept)
            } else {
                next.append(Piece(toy: toy))
            }
        }
        pieces = next
        for (i, piece) in pieces.enumerated() {
            piece.sprite.zPosition = CGFloat(i)
            addChild(piece.shadow)
            addChild(piece.sprite)
        }
        spawn(drop: drop, fresh: fresh, keepPlaces: mode == .room)
    }

    /// Same main toy, new look (Morph Squad, or a Maker part): the body carries on as it is.
    func redraw(image: UIImage) {
        guard let main = pieces.first else { return }
        main.image = image
        main.sprite.texture = SKTexture(image: image)
    }

    private func layout() {
        let w = Double(size.width), h = Double(size.height)
        switch mode {
        case .room:
            world = SquishBody.World(floor: h - 28, left: 6, right: w - 6, top: 4)
            // A wide screen (an iPad) has room for a bigger toy; a few toys together are each smaller.
            let most = w >= 700 ? 460.0 : 340.0
            let alone = min(w * 0.70, (world.floor - 20) * 0.62, most)
            // Side by side they must all fit across the floor.
            let together = (w - 12) / Double(max(1, pieces.count)) * 0.92
            side = pieces.count > 1 ? max(90, min(alone, together)) : max(120, alone)
        case .pressOnly:
            world = SquishBody.World(floor: h - 2, left: -100_000, right: 100_000, top: nil)
            side = min(w, h) * 0.84
        }
    }

    private func spawn(drop: Bool, fresh: Set<String>, keepPlaces: Bool) {
        var before: [String: Double] = [:]
        if keepPlaces {
            for piece in pieces where !fresh.contains(piece.id) {
                if let x = piece.body?.centre().x { before[piece.id] = x }
            }
        }
        layout()
        touchTimes = [:]
        touchStarts = [:]
        touchOwner = [:]
        touchBegan = [:]
        paths = [:]
        pokeEnds = nil
        carried = 0
        active = pieces.first
        guard !pieces.isEmpty, side > 10 else { return }
        let w = Double(size.width)
        let half = side / 2 + 8
        for (i, piece) in pieces.enumerated() {
            let mask = piece.mask
            let footV = mask?.footV ?? 1
            let falls = drop && fresh.contains(piece.id) && mode == .room && !reduceMotion
            let slot = w * (Double(i) + 0.5) / Double(pieces.count)
            let x = mode == .room ? min(max(before[piece.id] ?? slot, half), max(half, w - half)) : w / 2
            let made = SquishBody(size: side, n: 12, material: tuning.material(piece.feel, reduceMotion: reduceMotion),
                                  x: x,
                                  y: falls ? -side * 0.6 : world.floor - footV * side + side / 2,
                                  footV: footV, inside: { u, v in mask?.inside(u, v) ?? true })
            made.breathScale = reduceMotion ? 0 : 1
            piece.body = made
            piece.sprite.size = CGSize(width: side, height: side)
            piece.mixer.reset()
            piece.waitsForPop = false
            piece.stillFor = 0
            piece.shadow.isHidden = mode != .room
            light(piece, made)
        }
        if let n = pieces.first?.body?.n {
            source = []
            for r in 0...n {
                for i in 0...n { source.append(SIMD2(Float(i) / Float(n), Float(r) / Float(n))) }
            }
        }
        if reduceMotion { motion.stop(self) } else { motion.start(self) }
        for piece in pieces { draw(piece) }
    }

    /// Sets up the light for this toy: its rest shape once, then the surface every frame.
    private func light(_ piece: Piece, _ body: SquishBody) {
        guard let rest = piece.mask?.rest, !rest.isEmpty else {
            piece.sprite.shader = nil
            return
        }
        let look = body.material
        let side = SquishMask.restSize
        piece.restUniform.textureValue = SKTexture(data: Data(rest), size: CGSize(width: side, height: side))
        piece.lookUniform.vectorFloat4Value = SIMD4(Float(look.kd), Float(look.gloss), Float(look.shin), Float(tuning.restRelief))
        piece.dentUniform.vectorFloat4Value = SIMD4(Float(tuning.dentPinch), Float(look.ao), Float(tuning.dentRelief), 1)
        piece.sizeUniform.vectorFloat3Value = SIMD3(1 / Float(side), Float(body.zres - 1), 1 / Float(body.zres))
        if piece.shader == nil {
            let made = SKShader(source: SquishLight.source)
            made.uniforms = [piece.lightUniform, piece.tiltUniform, piece.lookUniform, piece.dentUniform, piece.sizeUniform,
                             piece.faceUniform, piece.centreUniform, piece.restUniform, piece.surfaceUniform]
            piece.shader = made
        }
        piece.sprite.shader = piece.shader
    }

    // MARK: - Fingers

    /// Pressing harder flattens more of the fingertip onto the glass: growth since touch down adds to the dent.
    private func force(_ touch: UITouch, since start: Double) -> Double {
        let now = Double(touch.majorRadius)
        guard start > 4, now > 4 else { return 1 }
        return 1 + max(0, min(1.2, (now - start) / max(start, 20))) * tuning.hardPressExtra
    }

    private func point(_ touch: UITouch) -> (x: Double, y: Double) {
        let at = touch.location(in: self)
        // The body counts y downwards, like the page.
        return (Double(at.x), Double(size.height - at.y))
    }

    private var pan: Double {
        guard mode == .room, let body = active?.body ?? body, size.width > 0 else { return 0 }
        return max(-1, min(1, body.metric.cx / Double(size.width) * 2 - 1)) * 0.7
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let main = pieces.first, let body = main.body else { return }
        for touch in touches {
            let at = point(touch), id = ObjectIdentifier(touch).hashValue
            var held = at
            var owner = main
            if onGesture != nil { paths[id] = ([at], touch.timestamp) }
            // A double tap counts wherever it lands in the toy's own space, not only right on its body.
            if touch.tapCount == 2 { onDoubleTap?() }
            if mode == .room {
                // The toy in front takes the finger.
                guard let hit = pieces.reversed().first(where: { $0.body?.grab(id, x: at.x, y: at.y) == true }) else { continue }
                owner = hit
            } else {
                // Press-only places: the press is taken near the top of the toy, so the whole toy
                // squashes and says "squeeze me"; the dent still forms under the finger.
                let b = body.bounds()
                guard at.x >= b.x0, at.x <= b.x1, at.y >= b.y0, at.y <= b.y1 else { continue }
                let top = (x: at.x, y: b.y0 + 0.08 * body.size)
                if body.grab(id, x: top.x, y: top.y, dent: at) {
                    held = top
                } else if !body.grab(id, x: at.x, y: at.y) {
                    continue
                }
            }
            touchOwner[id] = owner
            if active !== owner {
                // The one last touched is the one heard.
                sounds?.rest()
                active = owner
            }
            touchTimes[id] = touch.timestamp
            touchStarts[id] = (held.x, held.y, Double(touch.majorRadius))
            touchBegan[id] = touch.timestamp
            owner.waitsForPop = false
            owner.stillFor = 0
            onTouch?()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch).hashValue
            if let n = paths[id]?.points.count, n < 600 { paths[id]?.points.append(point(touch)) }
            guard let last = touchTimes[id], let start = touchStarts[id], let body = touchOwner[id]?.body else { continue }
            // Outside the Squish Room the finger only presses: it stays where it went down.
            let at = mode == .room ? point(touch) : (x: start.x, y: start.y)
            body.move(id, x: at.x, y: at.y, dt: touch.timestamp - last, force: force(touch, since: start.radius))
            touchTimes[id] = touch.timestamp
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = ObjectIdentifier(touch).hashValue
            var trick = false
            if let path = paths.removeValue(forKey: id), let onGesture, let main = body {
                let c = main.centre()
                if let gesture = TrickGesture.classify(points: path.points, seconds: touch.timestamp - path.began,
                                                       centre: (x: c.x, y: c.y), size: main.size) {
                    trick = onGesture(gesture)
                }
            }
            let owner = touchOwner.removeValue(forKey: id)
            guard touchTimes.removeValue(forKey: id) != nil else { continue }
            touchStarts[id] = nil
            let began = touchBegan.removeValue(forKey: id)
            guard let owner, let body = owner.body else { continue }
            let depth = body.metric.D
            let dent = body.metric.Z
            body.release(id)
            guard !body.isHeld else { continue }
            // Reduce Motion: let go without a throw.
            if reduceMotion || trick { body.stop() }
            owner.waitsForPop = tuning.feel(owner.feel).hapticDentPop && dent > 0.2
            if let volume = owner.mixer.pop(depth: depth, feel: owner.feel) {
                sounds?.pop(volume: volume, pan: pan, enabled: soundOn())
            }
            if owner === pieces.first { onLetGo?(depth) }
            // With several toys out, a quick tap makes the tapped one do its trick by itself.
            // (Alone, the view around the toy does the trick.)
            if pieces.count > 1, let began, touch.timestamp - began < 0.28 { trick(owner) }
        }
    }

    /// A quick press from the app itself (a treat, a pat), as if a finger tapped the top.
    func poke() {
        guard let body, !body.isHeld else { return }
        let b = body.bounds()
        if body.grab(SoftSquishyScene.pokeID, x: (b.x0 + b.x1) / 2, y: b.y0 + (b.y1 - b.y0) * 0.12) {
            pokeEnds = lastTime + 0.2
        }
    }

    /// A toy's own quick-tap trick, done on its sprite and body so the others stay as they are.
    private func trick(_ piece: Piece) {
        guard let name = piece.trick, let body = piece.body, !piece.sprite.hasActions() else { return }
        if name == "spin", !reduceMotion {
            let sprite = piece.sprite
            sprite.run(.sequence([.rotate(byAngle: -2 * .pi, duration: 0.6), .run { sprite.zRotation = 0 }]))
        } else if !body.metric.air {
            // Everything else is a hop: a real one, so it can land on a neighbour.
            body.bump(dx: 0, dy: 0, dvx: 0, dvy: -side * (reduceMotion ? 1.2 : 2.6), other: (x: 0, y: 0, r: 0), press: 0)
        }
        piece.stillFor = 0
    }

    /// The tickle: a quick shake.
    func wiggle() {
        guard !reduceMotion, let sprite = pieces.first?.sprite else { return }
        sprite.removeAction(forKey: "wiggle")
        let turn = SKAction.sequence([.rotate(toAngle: 0.1, duration: 0.04), .rotate(toAngle: -0.1, duration: 0.08), .rotate(toAngle: 0, duration: 0.04)])
        sprite.run(.repeat(turn, count: 3), withKey: "wiggle")
    }

    // MARK: - Each frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, max(0, currentTime - lastTime))
        lastTime = currentTime
        guard let main = pieces.first, let body = main.body else { return }
        if let ends = pokeEnds, currentTime >= ends {
            body.release(SoftSquishyScene.pokeID)
            pokeEnds = nil
        }
        carried += dt
        var steps = 0
        while carried >= tuning.stepSeconds && steps < 8 {
            for piece in pieces { piece.body?.step(tuning.stepSeconds, world: world) }
            if pieces.count > 1 { bump() }
            carried -= tuning.stepSeconds
            steps += 1
        }
        if steps == 8 { carried = 0 }
        feedback(dt)
        if let onPulse { onPulse(pulse(of: main, body)) }
        if let onMatePulse {
            for piece in pieces.dropFirst() {
                if let b = piece.body { onMatePulse(piece.id, pulse(of: piece, b)) }
            }
        }
        drawTick &+= 1
        var sliding = false
        for piece in pieces {
            guard let b = piece.body else { continue }
            let pm = b.metric
            let held = touchOwner.values.contains { $0 === piece }
            let busy = held || (piece === main && pokeEnds != nil) || pm.air || pm.speed > 0.02 || pm.Z > 0.01 || abs(pm.rate) > 0.01
            piece.stillFor = busy ? 0 : piece.stillFor + dt
        }
        if comesHome, main.stillFor > 0.5, size.width > 0 {
            let off = Double(size.width) / 2 - body.centre().x
            if abs(off) > 1.5 {
                body.shift(dx: off * min(1, dt * 4))
                sliding = true
            }
        }
        // Untouched and settled, only the slow breath and the phone's lean are left to show:
        // a third of the frames is plenty for those, and easier on the battery.
        for piece in pieces where piece.stillFor < 1 || (sliding && piece === main) || drawTick % 3 == 0 { draw(piece) }
    }

    /// Where a toy is and how hard it is squeezed, for the signature moves drawn over it.
    private func pulse(of piece: Piece, _ body: SquishBody) -> SquishPulse {
        let m = body.metric
        let c = body.centre(), held = touchOwner.values.contains { $0 === piece }
        // The moves are drawn from the middle of the picture, which is not the middle of the
        // body when the art is lopsided (Cream Puff's base is only its lower half).
        let ox: Double = (0.5 - body.c0.x) * side, oy: Double = (0.5 - body.c0.y) * side
        let ct: Double = cos(body.theta), st: Double = sin(body.theta)
        return SquishPulse(squeeze: min(1, max(m.D / 0.15, held ? 0.35 : 0)), held: held,
                           x: c.x + ct * ox - st * oy, y: c.y + st * ox + ct * oy, side: side, angle: body.theta)
    }

    /// Toys in the Squish Room bump into each other: they are moved apart, a thrown one bounces off,
    /// and both dent where they meet. A toy under a finger stays put and the other one gives way.
    private func bump() {
        for i in 0..<pieces.count {
            for j in (i + 1)..<pieces.count {
                guard let a = pieces[i].body, let b = pieces[j].body else { continue }
                let ha = a.hull(), hb = b.hull()
                let dx = hb.x - ha.x, dy = hb.y - ha.y
                let d = max(0.001, (dx * dx + dy * dy).squareRoot())
                let overlap = ha.r + hb.r - d
                guard overlap > 0 else { continue }
                let nx = dx / d, ny = dy / d
                let shareA = a.isHeld == b.isHeld ? 0.5 : (a.isHeld ? 0.0 : 1.0)
                let shareB = 1 - shareA
                // Only as fast as a soft thing gives way, so a toy dropped onto another sinks in and rolls off.
                let apart = min(overlap, side * 0.04)
                let va = a.velocity(), vb = b.velocity()
                let closing = (va.x - vb.x) * nx + (va.y - vb.y) * ny
                // A real hit bounces; slow contact only stops pressing in.
                let bounce = closing > side * 0.6 ? 0.45 : 0.0
                let kick = closing > 0 ? closing * (1 + bounce) : 0
                a.bump(dx: -nx * apart * shareA, dy: -ny * apart * shareA, dvx: -nx * kick * shareA, dvy: -ny * kick * shareA,
                       other: hb, press: 0.5)
                b.bump(dx: nx * apart * shareB, dy: ny * apart * shareB, dvx: nx * kick * shareB, dvy: ny * kick * shareB,
                       other: ha, press: 0.5)
                pieces[i].stillFor = 0
                pieces[j].stillFor = 0
            }
        }
    }

    private func feedback(_ dt: Double) {
        // Toys that are not the one in hand make no sound of their own: their landings are forgotten.
        for piece in pieces where piece !== active { piece.body?.clearImpact() }
        guard let piece = active ?? pieces.first, let body = piece.body else { return }
        let metric = body.metric
        let rules = tuning.feel(piece.feel)
        let frame = piece.mixer.frame(dt: dt, metric: metric, feel: piece.feel, rng: &rng)
        body.clearImpact()
        sounds?.play(frame, pan: pan, dt: dt, enabled: soundOn())
        guard let haptics, hapticsOn() else {
            haptics?.letGo()
            return
        }
        if touchTimes.isEmpty {
            haptics.letGo()
        } else {
            haptics.hold(intensity: piece.mixer.hapticIntensity(metric: metric), sharpness: rules.hapticSharpness)
            if let set = rules.hapticGrainSet, frame.grains.contains(where: { $0.set == set }) {
                haptics.tap(intensity: 0.18, sharpness: 0.7, atMostPerSecond: tuning.hapticGrainsPerSecond)
            }
        }
        if frame.thud != nil {
            haptics.tap(intensity: min(1, tuning.hapticLandingGain * metric.impact), sharpness: 0.3)
        }
        // Jelly: one light tap as the let-go dent pops out past flat.
        if piece.waitsForPop, metric.Z < 0.02 {
            piece.waitsForPop = false
            haptics.tap(intensity: 0.35, sharpness: 0.5)
        }
    }

    private func draw(_ piece: Piece) {
        guard let body = piece.body, side > 0, !source.isEmpty else { return }
        let sprite = piece.sprite, shadow = piece.shadow
        let n = body.n, p = body.p
        let centre = body.centre()
        // The sprite's square follows the body, so the warp stays close to the sprite.
        let left = centre.x - side / 2, top = centre.y - side / 2
        sprite.position = CGPoint(x: centre.x, y: Double(size.height) - centre.y)
        var to = [SIMD2<Float>](repeating: .zero, count: source.count)
        for r in 0...n {
            // SpriteKit counts rows from the bottom, the body from the top.
            let j = n - r
            for i in 0...n {
                let k = j * (n + 1) + i
                to[r * (n + 1) + i] = SIMD2(Float((Double(p[k * 2]) - left) / side), Float(1 - (Double(p[k * 2 + 1]) - top) / side))
            }
        }
        sprite.warpGeometry = SKWarpGeometryGrid(columns: n, rows: n, sourcePositions: source, destinationPositions: to)
        if sprite.shader != nil {
            let res = body.zres
            piece.surfaceUniform.textureValue = SKTexture(data: Data(body.surface()), size: CGSize(width: res, height: res))
            // The light stays put in the room when the toy turns. A tilt of the phone moves it, and the face, a little.
            let lean = reduceMotion ? (x: 0.0, y: 0.0) : motion.lean(limit: tuning.phoneTilt)
            let th = body.theta, c = cos(th), s = sin(th)
            let lx = tuning.light[0] + lean.x, ly = tuning.light[1] + lean.y
            piece.lightUniform.vectorFloat3Value = SIMD3(Float(c * lx + s * ly), Float(-s * lx + c * ly), Float(tuning.light[2]))
            piece.tiltUniform.vectorFloat2Value = reduceMotion
                ? SIMD2(0, 0)
                : SIMD2(Float(body.tilt.x + lean.x), Float(body.tilt.y + lean.y))
            let face = body.faceStretch(keep: tuning.faceKeep)
            piece.faceUniform.vectorFloat3Value = SIMD3(Float(face.xx), Float(face.xy), Float(face.yy))
            piece.centreUniform.vectorFloat2Value = SIMD2(Float(body.c0.x), Float(body.c0.y))
        }
        guard !shadow.isHidden else { return }
        let b = body.bounds()
        let lift = max(0, world.floor - b.y1)
        let width = (b.x1 - b.x0) * max(0.5, 1.05 - lift / (side * 2))
        shadow.position = CGPoint(x: (b.x0 + b.x1) / 2, y: Double(size.height) - world.floor)
        shadow.xScale = CGFloat(width / 100)
        shadow.yScale = CGFloat(width / 100)
        shadow.alpha = CGFloat(max(0.25, 1 - lift / (side * 1.2)) * 0.16)
    }
}

/// A little of the phone's tilt, shared by every soft squishy on screen. No permission is needed for this.
final class SquishMotion {
    static let shared = SquishMotion()
    private let manager = CMMotionManager()
    private var users = Set<ObjectIdentifier>()

    func start(_ user: AnyObject) {
        users.insert(ObjectIdentifier(user))
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 20
        manager.startDeviceMotionUpdates()
    }

    func stop(_ user: AnyObject) {
        users.remove(ObjectIdentifier(user))
        if users.isEmpty, manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }

    /// How far the phone leans from an easy holding angle, as a small offset: x to the right, y downwards.
    func lean(limit: Double) -> (x: Double, y: Double) {
        guard let gravity = manager.deviceMotion?.gravity else { return (0, 0) }
        func cap(_ v: Double) -> Double { max(-limit, min(limit, v)) }
        // Held upright the pull is along -y; a relaxed hold is about halfway to flat.
        return (cap(gravity.x * limit * 2), cap(-(gravity.y + 0.7) * limit * 2))
    }
}
