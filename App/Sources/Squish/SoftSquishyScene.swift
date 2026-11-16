import SpriteKit
import UIKit
import SquishSoft

/// Where the art is, sampled from its transparency, so only the toy itself is soft.
struct SquishMask {
    private static let n = 64
    private let alpha: [UInt8]
    /// Where the art's lowest pixel sits, 0 (top) to 1 (bottom).
    let footV: Double

    init?(image: UIImage) {
        let n = SquishMask.n
        guard let cg = image.cgImage,
              let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        guard let raw = ctx.data else { return nil }
        let pixels = raw.bindMemory(to: UInt8.self, capacity: n * n * 4)
        var alpha = [UInt8](repeating: 0, count: n * n)
        // The first row in memory is the top of the picture.
        for i in 0..<(n * n) { alpha[i] = pixels[i * 4 + 3] }
        self.alpha = alpha
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

    private let tuning = SquishTuning.standard
    private var body: SquishBody?
    private var image: UIImage?
    private var mask: SquishMask?
    private var feel = SquishFeel.foam
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
        pokeEnds = nil
        carried = 0
        mixer.reset()
        shadow.isHidden = mode != .room
        draw()
    }

    // MARK: - Fingers

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
            guard body.grab(id, x: at.x, y: at.y) else { continue }
            touchTimes[id] = touch.timestamp
            onTouch?()
            if touch.tapCount == 2 { onDoubleTap?() }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let body, mode == .room else { return }
        for touch in touches {
            let id = ObjectIdentifier(touch).hashValue
            guard let last = touchTimes[id] else { continue }
            let at = point(touch)
            body.move(id, x: at.x, y: at.y, dt: touch.timestamp - last)
            touchTimes[id] = touch.timestamp
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        guard let body else { return }
        for touch in touches {
            let id = ObjectIdentifier(touch).hashValue
            guard touchTimes.removeValue(forKey: id) != nil else { continue }
            let depth = body.metric.D
            body.release(id)
            guard !body.isHeld else { continue }
            // Reduce Motion: let go without a throw.
            if reduceMotion { body.stop() }
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
        draw()
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
