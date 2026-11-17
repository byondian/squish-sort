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

/// One soft squishy. The body is `SquishBody` (the page's engine, ported); this
/// draws it by warping the sprite over the body's lattice each frame, and
/// passes fingers, sound and haptics in and out.
final class SoftSquishyScene: SKScene {
    enum Mode {
        /// Squish Room: knead, pull, pinch, pick up, drop and throw, with a floor and walls.
        case room
        /// Buddy, capsule reveal, Maker: press and let go only.
        case pressOnly
    }

    var mode = Mode.pressOnly
    /// The Buddy on Home: once thrown and settled, it slides back to the middle.
    var comesHome = false
    var reduceMotion = false
    var soundOn: () -> Bool = { true }
    var hapticsOn: () -> Bool = { true }
    var sounds: SquishSound?
    var haptics: SquishHaptics?
    /// A finger landed on the toy.
    var onTouch: (() -> Void)?
    /// The last finger left; the number is how deep the squeeze was (`metric.D`).
    var onLetGo: ((Double) -> Void)?
    var onDoubleTap: (() -> Void)?
    /// A finger drew a trick (a flick up, a circle). True if a trick was done, so the toy is not also thrown.
    var onGesture: ((TrickGesture) -> Bool)?
    /// Each frame: where the body is and how hard it is squeezed, for the signature moves drawn over it.
    var onPulse: ((SquishPulse) -> Void)?
    /// Each finger's path since it went down, on or beside the toy.
    private var paths: [Int: (points: [(x: Double, y: Double)], began: TimeInterval)] = [:]

    private let tuning = SquishTuning.standard
    private var body: SquishBody?
    private var image: UIImage?
    private var mask: SquishMask?
    private var feel = SquishFeel.jelly
    private let sprite = SKSpriteNode()
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 100, height: 18))
    private var world = SquishBody.World(floor: 0, left: 0, right: 0)
    private var side = 0.0
    private var source: [SIMD2<Float>] = []
    private var lastTime: TimeInterval = 0
    private var carried = 0.0
    private var mixer = SquishSoundMixer()
    private var rng = SystemRandomNumberGenerator()
    private var touchTimes: [Int: TimeInterval] = [:]
    private var pokeEnds: TimeInterval?
    private static let pokeID = -1
    /// Where each finger went down, and how big its contact patch was then.
    private var touchStarts: [Int: (x: Double, y: Double, radius: Double)] = [:]
    /// A let-go dent that has not popped out past flat yet (jelly's light tap).
    private var waitsForPop = false
    private var lightShader: SKShader?
    /// Seconds the toy has sat untouched and settled, and a frame count for drawing less often then.
    private var stillFor = 0.0
    private var drawTick = 0
    private let lightUniform = SKUniform(name: "u_L", vectorFloat3: SIMD3<Float>(-0.46, -0.62, 0.64))
    private let tiltUniform = SKUniform(name: "u_tilt", vectorFloat2: SIMD2<Float>(0, 0))
    private let lookUniform = SKUniform(name: "u_m", vectorFloat4: SIMD4<Float>(0.5, 0, 30, 0.2))
    private let dentUniform = SKUniform(name: "u_m2", vectorFloat4: SIMD4<Float>(0.004, 0.15, 0.3, 1))
    private let sizeUniform = SKUniform(name: "u_e", vectorFloat3: SIMD3<Float>(1.0 / 128, 96, 1.0 / 97))
    private let faceUniform = SKUniform(name: "u_u", vectorFloat3: SIMD3<Float>(0, 0, 0))
    private let centreUniform = SKUniform(name: "u_c0", vectorFloat2: SIMD2<Float>(0.5, 0.5))
    private let restUniform = SKUniform(name: "u_hm", texture: nil)
    private let surfaceUniform = SKUniform(name: "u_zm", texture: nil)
    private let motion = SquishMotion.shared

    override init() {
        super.init(size: CGSize(width: 300, height: 300))
        scaleMode = .resizeFill
        backgroundColor = .clear
        shadow.fillColor = UIColor(red: 0.23, green: 0.16, blue: 0.35, alpha: 1)
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        shadow.isHidden = true
        addChild(shadow)
        addChild(sprite)
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
        spawn(drop: false)
    }

    /// Goes quiet when the toy leaves the screen.
    func goQuiet() {
        body?.releaseAll()
        touchTimes = [:]
        touchStarts = [:]
        paths = [:]
        motion.stop(self)
        pokeEnds = nil
        sounds?.rest()
        haptics?.letGo()
    }

    // MARK: - What is shown

    /// A new toy: new art, new body.
    func show(image: UIImage, feel: SquishFeel, drop: Bool) {
        self.image = image
        self.feel = feel
        mask = SquishMask(image: image)
        sprite.texture = SKTexture(image: image)
        spawn(drop: drop)
    }

    /// Same toy, new look (Morph Squad, or a Maker part): the body carries on as it is.
    func redraw(image: UIImage) {
        self.image = image
        sprite.texture = SKTexture(image: image)
    }

    private func layout() {
        let w = Double(size.width), h = Double(size.height)
        switch mode {
        case .room:
            world = SquishBody.World(floor: h - 28, left: 6, right: w - 6, top: 4)
            side = max(120, min(w * 0.70, (world.floor - 20) * 0.62, 340))
        case .pressOnly:
            world = SquishBody.World(floor: h - 2, left: -100_000, right: 100_000, top: nil)
            side = min(w, h) * 0.84
        }
    }

    private func spawn(drop: Bool) {
        layout()
        guard image != nil, side > 10 else { return }
        let mask = self.mask
        let footV = mask?.footV ?? 1
        let falls = drop && mode == .room && !reduceMotion
        let made = SquishBody(size: side, n: 12, material: tuning.material(feel, reduceMotion: reduceMotion),
                              x: Double(size.width) / 2,
                              y: falls ? -side * 0.6 : world.floor - footV * side + side / 2,
                              footV: footV, inside: { u, v in mask?.inside(u, v) ?? true })
        made.breathScale = reduceMotion ? 0 : 1
        body = made
        sprite.size = CGSize(width: side, height: side)
        let n = made.n
        source = []
        for r in 0...n {
            for i in 0...n { source.append(SIMD2(Float(i) / Float(n), Float(r) / Float(n))) }
        }
        touchTimes = [:]
        touchStarts = [:]
        paths = [:]
        pokeEnds = nil
        waitsForPop = false
        carried = 0
        mixer.reset()
        shadow.isHidden = mode != .room
        light(made)
        if reduceMotion { motion.stop(self) } else { motion.start(self) }
        draw()
    }

    /// Sets up the light for this toy: its rest shape once, then the surface every frame.
    private func light(_ body: SquishBody) {
        guard let rest = mask?.rest, !rest.isEmpty else {
            sprite.shader = nil
            return
        }
        let look = body.material
        let side = SquishMask.restSize
        restUniform.textureValue = SKTexture(data: Data(rest), size: CGSize(width: side, height: side))
        lookUniform.vectorFloat4Value = SIMD4(Float(look.kd), Float(look.gloss), Float(look.shin), Float(tuning.restRelief))
        dentUniform.vectorFloat4Value = SIMD4(Float(tuning.dentPinch), Float(look.ao), Float(tuning.dentRelief), 1)
        sizeUniform.vectorFloat3Value = SIMD3(1 / Float(side), Float(body.zres - 1), 1 / Float(body.zres))
        if lightShader == nil {
            let made = SKShader(source: SquishLight.source)
            made.uniforms = [lightUniform, tiltUniform, lookUniform, dentUniform, sizeUniform, faceUniform, centreUniform, restUniform, surfaceUniform]
            lightShader = made
        }
        sprite.shader = lightShader
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
        guard mode == .room, let body, size.width > 0 else { return 0 }
        return max(-1, min(1, body.metric.cx / Double(size.width) * 2 - 1)) * 0.7
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let body else { return }
        for touch in touches {
            let at = point(touch), id = ObjectIdentifier(touch).hashValue
            var held = at
            if onGesture != nil { paths[id] = ([at], touch.timestamp) }
            if mode == .room {
                guard body.grab(id, x: at.x, y: at.y) else { continue }
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
            touchTimes[id] = touch.timestamp
            touchStarts[id] = (held.x, held.y, Double(touch.majorRadius))
            waitsForPop = false
            onTouch?()
            if touch.tapCount == 2 { onDoubleTap?() }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let body else { return }
        for touch in touches {
            let id = ObjectIdentifier(touch).hashValue
            if let n = paths[id]?.points.count, n < 600 { paths[id]?.points.append(point(touch)) }
            guard let last = touchTimes[id], let start = touchStarts[id] else { continue }
            // Outside the Squish Room the finger only presses: it stays where it went down.
            let at = mode == .room ? point(touch) : (x: start.x, y: start.y)
            body.move(id, x: at.x, y: at.y, dt: touch.timestamp - last, force: force(touch, since: start.radius))
            touchTimes[id] = touch.timestamp
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        guard let body else { return }
        for touch in touches {
            let id = ObjectIdentifier(touch).hashValue
            var trick = false
            if let path = paths.removeValue(forKey: id), let onGesture {
                let c = body.centre()
                if let gesture = TrickGesture.classify(points: path.points, seconds: touch.timestamp - path.began,
                                                       centre: (x: c.x, y: c.y), size: body.size) {
                    trick = onGesture(gesture)
                }
            }
            guard touchTimes.removeValue(forKey: id) != nil else { continue }
            touchStarts[id] = nil
            let depth = body.metric.D
            let dent = body.metric.Z
            body.release(id)
            guard !body.isHeld else { continue }
            // Reduce Motion: let go without a throw.
            if reduceMotion || trick { body.stop() }
            waitsForPop = tuning.feel(feel).hapticDentPop && dent > 0.2
            if let volume = mixer.pop(depth: depth, feel: feel) {
                sounds?.pop(volume: volume, pan: pan, enabled: soundOn())
            }
            onLetGo?(depth)
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

    /// The tickle: a quick shake.
    func wiggle() {
        guard !reduceMotion else { return }
        sprite.removeAction(forKey: "wiggle")
        let turn = SKAction.sequence([.rotate(toAngle: 0.1, duration: 0.04), .rotate(toAngle: -0.1, duration: 0.08), .rotate(toAngle: 0, duration: 0.04)])
        sprite.run(.repeat(turn, count: 3), withKey: "wiggle")
    }

    // MARK: - Each frame

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(0.05, max(0, currentTime - lastTime))
        lastTime = currentTime
        guard let body else { return }
        if let ends = pokeEnds, currentTime >= ends {
            body.release(SoftSquishyScene.pokeID)
            pokeEnds = nil
        }
        carried += dt
        var steps = 0
        while carried >= tuning.stepSeconds && steps < 8 {
            body.step(tuning.stepSeconds, world: world)
            carried -= tuning.stepSeconds
            steps += 1
        }
        if steps == 8 { carried = 0 }
        feedback(dt)
        // Untouched and settled, only the slow breath and the phone's lean are left to show:
        // a third of the frames is plenty for those, and easier on the battery.
        let m = body.metric
        if let onPulse {
            let c = body.centre(), held = !touchTimes.isEmpty
            // The moves are drawn from the middle of the picture, which is not the middle of the
            // body when the art is lopsided (Cream Puff's base is only its lower half).
            let ox: Double = (0.5 - body.c0.x) * side, oy: Double = (0.5 - body.c0.y) * side
            let ct: Double = cos(body.theta), st: Double = sin(body.theta)
            onPulse(SquishPulse(squeeze: min(1, max(m.D / 0.15, held ? 0.35 : 0)), held: held,
                                x: c.x + ct * ox - st * oy, y: c.y + st * ox + ct * oy, side: side, angle: body.theta))
        }
        let busy = !touchTimes.isEmpty || pokeEnds != nil || m.air || m.speed > 0.02 || m.Z > 0.01 || abs(m.rate) > 0.01
        stillFor = busy ? 0 : stillFor + dt
        drawTick &+= 1
        var sliding = false
        if comesHome, stillFor > 0.5, size.width > 0 {
            let off = Double(size.width) / 2 - body.centre().x
            if abs(off) > 1.5 {
                body.shift(dx: off * min(1, dt * 4))
                sliding = true
            }
        }
        if stillFor < 1 || sliding || drawTick % 3 == 0 { draw() }
    }

    private func feedback(_ dt: Double) {
        guard let body else { return }
        let metric = body.metric
        let rules = tuning.feel(feel)
        let frame = mixer.frame(dt: dt, metric: metric, feel: feel, rng: &rng)
        body.clearImpact()
        sounds?.play(frame, pan: pan, dt: dt, enabled: soundOn())
        guard let haptics, hapticsOn() else {
            haptics?.letGo()
            return
        }
        if touchTimes.isEmpty {
            haptics.letGo()
        } else {
            haptics.hold(intensity: mixer.hapticIntensity(metric: metric), sharpness: rules.hapticSharpness)
            if let set = rules.hapticGrainSet, frame.grains.contains(where: { $0.set == set }) {
                haptics.tap(intensity: 0.18, sharpness: 0.7, atMostPerSecond: tuning.hapticGrainsPerSecond)
            }
        }
        if frame.thud != nil {
            haptics.tap(intensity: min(1, tuning.hapticLandingGain * metric.impact), sharpness: 0.3)
        }
        // Jelly: one light tap as the let-go dent pops out past flat.
        if waitsForPop, metric.Z < 0.02 {
            waitsForPop = false
            haptics.tap(intensity: 0.35, sharpness: 0.5)
        }
    }

    private func draw() {
        guard let body, side > 0 else { return }
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
            surfaceUniform.textureValue = SKTexture(data: Data(body.surface()), size: CGSize(width: res, height: res))
            // The light stays put in the room when the toy turns. A tilt of the phone moves it, and the face, a little.
            let lean = reduceMotion ? (x: 0.0, y: 0.0) : motion.lean(limit: tuning.phoneTilt)
            let th = body.theta, c = cos(th), s = sin(th)
            let lx = tuning.light[0] + lean.x, ly = tuning.light[1] + lean.y
            lightUniform.vectorFloat3Value = SIMD3(Float(c * lx + s * ly), Float(-s * lx + c * ly), Float(tuning.light[2]))
            tiltUniform.vectorFloat2Value = reduceMotion
                ? SIMD2(0, 0)
                : SIMD2(Float(body.tilt.x + lean.x), Float(body.tilt.y + lean.y))
            let face = body.faceStretch(keep: tuning.faceKeep)
            faceUniform.vectorFloat3Value = SIMD3(Float(face.xx), Float(face.xy), Float(face.yy))
            centreUniform.vectorFloat2Value = SIMD2(Float(body.c0.x), Float(body.c0.y))
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
