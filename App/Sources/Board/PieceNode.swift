import SpriteKit
import SquishCore
import SquishSoft

/// One squishy on the board: body, face, and overlays for wrapped, frozen and duet.
final class PieceNode: SKNode {
    let kindID: String
    let diameter: CGFloat
    private let style: SquishyStyle
    private let body: SKShapeNode
    private let face = SKNode()
    private let question: SKLabelNode
    private let ice: SKShapeNode
    private let duetMark: SKLabelNode
    /// Everything is drawn centred in here; the node's own origin is the
    /// bottom centre, so squash and stretch are anchored at the bottom.
    private let content = SKNode()
    /// Squash and lean act here, anchored at the bottom centre (squish motion spec, section 8).
    private let soft = SKNode()
    private var squashSpring = PieceSpring()
    private var leanSpring = PieceSpring()
    /// Jar complete: squeezed down by hand, not by the spring, until it is let go.
    private var squeeze: (elapsed: Double, duration: Double)?
    private var lastX: CGFloat?
    private var settled = true
    private var art: SKSpriteNode?
    private let glitter = SKLabelNode(text: "✨")
    /// The level's lucky squishy glitters (unless it is still wrapped).
    var isLucky = false

    init(kindID: String, diameter d: CGFloat) {
        self.kindID = kindID
        self.diameter = d
        style = SquishyStyle.forID(kindID)
        body = SKShapeNode(path: style.bodyPath(diameter: d))
        question = SKLabelNode(text: "?")
        ice = SKShapeNode(path: style.bodyPath(diameter: d * 1.06))
        duetMark = SKLabelNode(text: "♥")
        super.init()
        content.position = CGPoint(x: 0, y: d / 2)
        soft.addChild(content)
        addChild(soft)

        if UIImage(named: "squishy-\(kindID)") != nil {
            // Launch art from the design thread.
            let sprite = SKSpriteNode(texture: SKTexture(imageNamed: "squishy-\(kindID)"))
            // Pictures come with different margins. Each toy fills its place by the part that is
            // not see-through and sits on the bottom of it, so a stack is evenly spaced.
            let box = SquishMask.opaqueBox(named: "squishy-\(kindID)")
            let side = min(d * 1.6, d * 0.96 / max(box.width, box.height, 0.4))
            sprite.size = CGSize(width: side, height: side)
            sprite.position = CGPoint(x: (0.5 - box.midX) * side, y: -d * 0.48 - (0.5 - box.maxY) * side)
            sprite.zPosition = 1
            content.addChild(sprite)
            art = sprite
        }

        for path in style.featurePaths(diameter: d) where art == nil {
            let f = SKShapeNode(path: path)
            f.fillColor = style.featureColor
            f.strokeColor = .plum
            f.lineWidth = max(1.5, d * 0.035)
            f.zPosition = -1
            content.addChild(f)
        }
        body.fillColor = style.color
        body.isHidden = art != nil
        body.zPosition = 2
        body.strokeColor = .plum
        body.lineWidth = max(1.5, d * 0.04)
        content.addChild(body)

        // Gloss highlight, top left.
        let gloss = SKShapeNode(ellipseOf: CGSize(width: d * 0.22, height: d * 0.13))
        gloss.fillColor = UIColor.white.withAlphaComponent(0.55)
        gloss.strokeColor = .clear
        gloss.position = CGPoint(x: -d * 0.2, y: d * 0.2)
        gloss.zRotation = 0.5
        body.addChild(gloss)

        buildFace(d)
        body.addChild(face)

        question.fontName = "AvenirNext-Heavy"
        question.fontSize = d * 0.5
        question.fontColor = .plum
        question.verticalAlignmentMode = .center
        question.isHidden = true
        content.addChild(question)

        ice.fillColor = UIColor.ice.withAlphaComponent(0.55)
        ice.strokeColor = UIColor.white
        ice.lineWidth = 2
        ice.isHidden = true
        let flake = SKLabelNode(text: "❄︎")
        flake.fontSize = d * 0.32
        flake.fontColor = .white
        flake.verticalAlignmentMode = .center
        flake.position = CGPoint(x: d * 0.28, y: d * 0.28)
        ice.addChild(flake)
        content.addChild(ice)

        duetMark.fontSize = d * 0.3
        duetMark.fontColor = UIColor(hex: 0xFF7EB6)
        duetMark.verticalAlignmentMode = .center
        duetMark.position = CGPoint(x: 0, y: d * 0.5)
        duetMark.zPosition = 2
        duetMark.isHidden = true
        content.addChild(duetMark)

        glitter.fontSize = d * 0.42
        glitter.verticalAlignmentMode = .center
        glitter.position = CGPoint(x: d * 0.3, y: d * 0.3)
        glitter.zPosition = 3
        glitter.isHidden = true
        glitter.run(.repeatForever(.sequence([
            .group([.scale(to: 1.25, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)]),
            .group([.scale(to: 0.8, duration: 0.5), .fadeAlpha(to: 0.55, duration: 0.5)]),
        ])))
        content.addChild(glitter)

        startBreathing()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func buildFace(_ d: CGFloat) {
        for side: CGFloat in [-1, 1] {
            let eye = SKShapeNode(circleOfRadius: d * 0.065)
            eye.fillColor = .plum
            eye.strokeColor = .clear
            eye.position = CGPoint(x: side * d * 0.17, y: d * 0.04)
            let shine = SKShapeNode(circleOfRadius: d * 0.022)
            shine.fillColor = .white
            shine.strokeColor = .clear
            shine.position = CGPoint(x: -d * 0.02, y: d * 0.025)
            eye.addChild(shine)
            face.addChild(eye)

            let blush = SKShapeNode(ellipseOf: CGSize(width: d * 0.16, height: d * 0.07))
            blush.fillColor = UIColor(hex: 0xFF9EB5).withAlphaComponent(0.7)
            blush.strokeColor = .clear
            blush.position = CGPoint(x: side * d * 0.29, y: -d * 0.08)
            face.addChild(blush)
        }
        let mouth = CGMutablePath()
        mouth.addArc(center: CGPoint(x: 0, y: -d * 0.04), radius: d * 0.06, startAngle: .pi * 1.15,
                     endAngle: .pi * 1.85, clockwise: false)
        let m = SKShapeNode(path: mouth)
        m.strokeColor = .plum
        m.lineWidth = max(1.2, d * 0.03)
        m.lineCap = .round
        face.addChild(m)
        blinkForever()
    }

    // MARK: - Springs

    /// Lift: a quick stretch upwards, then it rings.
    func stretchUp() {
        squashSpring.velocity = PieceSpring.liftKick
        settled = false
    }

    /// Landing at `speed` piece heights a second. Returns how far it will squash.
    @discardableResult
    func land(speed: Double) -> Double {
        let kick = PieceSpring.landingKick(speed: speed)
        squashSpring.velocity += kick
        settled = false
        return PieceSpring.peak(forKick: kick)
    }

    /// The stack gives: a squash of about `peak` passed down from the piece above.
    func ripple(peak: Double, after delay: Double) {
        run(.sequence([.wait(forDuration: delay), .run { [weak self] in
            self?.squashSpring.velocity += PieceSpring.kick(forPeak: peak)
            self?.settled = false
        }]))
    }

    /// Jar complete: squash right down, then let go so it overshoots.
    func squeezeAndRelease() {
        squeeze = (0, PieceSpring.completeSqueezeSeconds)
        settled = false
    }

    /// Rejected move: the lean kicks one way, then the other. No squash.
    func shakeHead() {
        let kick = PieceSpring.kick(forPeak: PieceSpring.rejectLean)
        leanSpring.velocity += kick
        settled = false
        run(.sequence([.wait(forDuration: 0.1), .run { [weak self] in
            self?.leanSpring.velocity -= kick * 1.3
            self?.settled = false
        }]))
    }

    /// Once a frame from the board.
    func advance(_ dt: Double) {
        // The lean trails behind sideways movement.
        let x = position.x
        let speed = lastX.map { Double(x - $0) / max(dt, 1.0 / 240) / Double(max(diameter, 1)) } ?? 0
        lastX = x
        leanSpring.target = max(-PieceSpring.maxLean, min(PieceSpring.maxLean, -PieceSpring.leanPerSpeed * speed))
        if speed != 0 { settled = false }
        guard !settled else { return }
        if var held = squeeze {
            held.elapsed += dt
            let t = min(1, held.elapsed / held.duration)
            squashSpring.value += (PieceSpring.maxSquash - squashSpring.value) * t
            squashSpring.velocity = 0
            squeeze = t >= 1 ? nil : held
        } else {
            squashSpring.advance(dt)
        }
        leanSpring.advance(dt)
        let s = min(PieceSpring.maxSquash, squashSpring.value)
        soft.yScale = CGFloat(1 - s)
        soft.xScale = CGFloat(1 + 0.8 * s)
        // The spec counts a lean clockwise; SpriteKit turns the other way.
        soft.zRotation = CGFloat(-leanSpring.value)
        if squeeze == nil, squashSpring.isResting, leanSpring.isResting {
            soft.setScale(1)
            soft.zRotation = 0
            settled = true
        }
    }

    func apply(_ piece: Piece) {
        let wasHidden = !question.isHidden
        question.isHidden = !piece.hidden
        face.isHidden = piece.hidden
        body.fillColor = piece.hidden ? .wrapper : style.color
        if let art {
            art.isHidden = piece.hidden
            body.isHidden = !piece.hidden
        }
        ice.isHidden = !piece.isFrozen
        ice.alpha = piece.frozen >= 2 ? 1 : 0.6
        duetMark.isHidden = !piece.bondedAbove
        glitter.isHidden = !isLucky || piece.hidden
        if wasHidden && !piece.hidden {
            // Unwrap: a little pop.
            run(.sequence([.scale(to: 1.15, duration: 0.08), .scale(to: 1, duration: 0.12)]))
        }
    }

    private func startBreathing() {
        let breathe = SKAction.sequence([
            .scaleX(to: 1.0, y: 1.02, duration: 1.1),
            .scaleX(to: 1.0, y: 1.0, duration: 1.1),
        ])
        (art ?? body).run(.repeatForever(breathe), withKey: "breathe")
    }

    private func blinkForever() {
        let blink = SKAction.sequence([
            .wait(forDuration: 2.5, withRange: 3),
            .scaleX(to: 1, y: 0.1, duration: 0.06),
            .scaleX(to: 1, y: 1, duration: 0.08),
        ])
        face.run(.repeatForever(blink))
    }
}

/// A clear glass jar. Every world has the same jar and its own lid (level screen spec).
final class JarNode: SKNode {
    let size: CGSize
    private let world: String
    private let dark: Bool
    private let glass: SKShapeNode
    private let outline: SKShapeNode
    private var lid: SKNode?

    /// Rounded more at the bottom than at the top, like a jam jar.
    private static func jarPath(_ size: CGSize, inset: CGFloat = 0) -> CGPath {
        let w = size.width - inset * 2, h = size.height - inset * 2
        let top = max(2, w * 0.24 - inset), bottom = max(2, min(w * 0.45, h / 2) - inset)
        let x0 = -w / 2, x1 = w / 2, y0 = -h / 2, y1 = h / 2
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0 + bottom, y: y0))
        p.addLine(to: CGPoint(x: x1 - bottom, y: y0))
        p.addQuadCurve(to: CGPoint(x: x1, y: y0 + bottom), control: CGPoint(x: x1, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y1 - top))
        p.addQuadCurve(to: CGPoint(x: x1 - top, y: y1), control: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x0 + top, y: y1))
        p.addQuadCurve(to: CGPoint(x: x0, y: y1 - top), control: CGPoint(x: x0, y: y1))
        p.addLine(to: CGPoint(x: x0, y: y0 + bottom))
        p.addQuadCurve(to: CGPoint(x: x0 + bottom, y: y0), control: CGPoint(x: x0, y: y0))
        p.closeSubpath()
        return p
    }

    /// - Parameters:
    ///   - world: picks the lid.
    ///   - dark: on a dark background the outline becomes a soft glow so the jar still reads.
    init(size: CGSize, world: String = "", dark: Bool = false) {
        self.size = size
        self.world = world
        self.dark = dark
        glass = SKShapeNode(path: JarNode.jarPath(size))
        outline = SKShapeNode(path: JarNode.jarPath(size))
        super.init()
        glass.fillColor = UIColor.white.withAlphaComponent(dark ? 0.16 : 0.42)
        glass.strokeColor = .clear
        addChild(glass)
        // A white inner edge, like thick glass.
        let inner = SKShapeNode(path: JarNode.jarPath(size, inset: 2.5))
        inner.fillColor = .clear
        inner.strokeColor = UIColor.white.withAlphaComponent(dark ? 0.45 : 0.85)
        inner.lineWidth = 3
        addChild(inner)
        outline.fillColor = .clear
        outline.lineWidth = dark ? 2.5 : 2
        outline.glowWidth = dark ? 3 : 0
        addChild(outline)
        setHighlighted(false)
        // The shine stripe down the left.
        let shine = SKShapeNode(rectOf: CGSize(width: size.width * 0.1, height: size.height * 0.62),
                                cornerRadius: size.width * 0.05)
        shine.fillColor = UIColor.white.withAlphaComponent(dark ? 0.3 : 0.65)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -size.width * 0.31, y: size.height * 0.04)
        addChild(shine)
        // A slightly wider rim on top.
        let rim = SKShapeNode(rectOf: CGSize(width: size.width * 1.06, height: max(5, size.width * 0.09)),
                              cornerRadius: max(2.5, size.width * 0.045))
        rim.fillColor = UIColor.white.withAlphaComponent(dark ? 0.55 : 0.95)
        rim.strokeColor = UIColor(hex: 0x965A78).withAlphaComponent(0.28)
        rim.lineWidth = 1.5
        rim.position = CGPoint(x: 0, y: size.height / 2)
        rim.zPosition = 1
        addChild(rim)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var restingStroke: UIColor {
        dark ? UIColor(hex: lid == nil ? 0xA9D8FF : 0xFF9CCB).withAlphaComponent(0.9)
             : UIColor(hex: 0x965A78).withAlphaComponent(0.28 + 0.2)
    }

    func setHighlighted(_ on: Bool) {
        outline.strokeColor = on ? UIColor(hex: 0xFF7EB6) : restingStroke
        outline.lineWidth = on ? 5 : (dark ? 2.5 : 2)
    }

    /// The word that pops up when a jar is finished in this world.
    static func word(for world: String) -> String {
        switch world {
        case "sweetfactory": return String(localized: "Yum!")
        case "starlight": return String(localized: "Encore!")
        case "christmas": return String(localized: "Ho ho!")
        default: return String(localized: "Sorted!")
        }
    }

    /// One lid per world, drawn about its bottom centre.
    private func makeLid() -> SKNode {
        let w = size.width * 1.1, h = size.width * 0.34
        let node = SKNode()
        func cap(_ fill: UIColor, height: CGFloat = h, radius: CGFloat? = nil) -> SKShapeNode {
            let c = SKShapeNode(rect: CGRect(x: -w / 2, y: 0, width: w, height: height), cornerRadius: radius ?? height * 0.42)
            c.fillColor = fill
            c.strokeColor = .plum
            c.lineWidth = 2.5
            return c
        }
        switch world {
        case "sweetfactory":
            // A candy-striped screw cap with a round sweet on top.
            let c = cap(.white)
            node.addChild(c)
            let stripes = SKCropNode()
            let mask = SKShapeNode(rect: CGRect(x: -w / 2 + 2, y: 2, width: w - 4, height: h - 4), cornerRadius: h * 0.36)
            mask.fillColor = .white
            mask.strokeColor = .clear
            stripes.maskNode = mask
            for i in -4...4 {
                let stripe = SKShapeNode(rectOf: CGSize(width: w * 0.09, height: h * 2))
                stripe.fillColor = UIColor(hex: 0xFF8FBE)
                stripe.strokeColor = .clear
                stripe.zRotation = -0.45
                stripe.position = CGPoint(x: CGFloat(i) * w * 0.18, y: h / 2)
                stripes.addChild(stripe)
            }
            node.addChild(stripes)
            let sweet = SKShapeNode(circleOfRadius: h * 0.34)
            sweet.fillColor = UIColor(hex: 0x7FE0C4)
            sweet.strokeColor = .plum
            sweet.lineWidth = 2.5
            sweet.position = CGPoint(x: 0, y: h + h * 0.26)
            node.addChild(sweet)
        case "starlight":
            // A glowing lilac cap with a gold star on top.
            let c = cap(UIColor(hex: 0xC9A8FF))
            c.glowWidth = 2
            node.addChild(c)
            let star = SKLabelNode(text: "★")
            star.fontSize = h * 1.25
            star.fontColor = UIColor(hex: 0xFFD86B)
            star.verticalAlignmentMode = .center
            star.position = CGPoint(x: 0, y: h * 1.25)
            node.addChild(star)
        case "christmas":
            // A red cap with a white snow rim and a small bow.
            node.addChild(cap(UIColor(hex: 0xE5484D)))
            let snow = SKShapeNode(rect: CGRect(x: -w * 0.53, y: -h * 0.08, width: w * 1.06, height: h * 0.42), cornerRadius: h * 0.2)
            snow.fillColor = .white
            snow.strokeColor = .plum
            snow.lineWidth = 2
            node.addChild(snow)
            let bow = SKLabelNode(text: "🎀")
            bow.fontSize = h * 0.8
            bow.verticalAlignmentMode = .center
            bow.position = CGPoint(x: 0, y: h * 1.2)
            node.addChild(bow)
        default:
            // Toy Shop: a glossy pink capsule dome with a darker band and a shine spot.
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: -w / 2, y: 0))
            dome.addLine(to: CGPoint(x: -w / 2, y: h * 0.35))
            dome.addCurve(to: CGPoint(x: w / 2, y: h * 0.35), control1: CGPoint(x: -w / 2, y: h * 1.75),
                          control2: CGPoint(x: w / 2, y: h * 1.75))
            dome.addLine(to: CGPoint(x: w / 2, y: 0))
            dome.closeSubpath()
            let d = SKShapeNode(path: dome)
            d.fillColor = UIColor(hex: 0xFF8FBE)
            d.strokeColor = .plum
            d.lineWidth = 2.5
            node.addChild(d)
            let band = SKShapeNode(rect: CGRect(x: -w / 2, y: 0, width: w, height: h * 0.34), cornerRadius: h * 0.1)
            band.fillColor = UIColor(hex: 0xE5609B)
            band.strokeColor = .plum
            band.lineWidth = 2.5
            node.addChild(band)
            let spot = SKShapeNode(ellipseOf: CGSize(width: w * 0.2, height: h * 0.26))
            spot.fillColor = UIColor.white.withAlphaComponent(0.75)
            spot.strokeColor = .clear
            spot.zRotation = 0.5
            spot.position = CGPoint(x: -w * 0.22, y: h * 0.88)
            node.addChild(spot)
        }
        return node
    }

    /// The lid moment, under a second: the lid drops, lands and squashes wide with the jar, wobbles
    /// twice, twists shut with a click, and gold rays burst behind it. The glass takes a soft tint
    /// of its squishy's colour. `onLand` and `onTwist` are for the sounds and haptics.
    func putLid(animated: Bool, tint: UIColor? = nil, reduceMotion: Bool = false,
                onLand: (() -> Void)? = nil, onTwist: (() -> Void)? = nil) {
        guard lid == nil else { return }
        let l = makeLid()
        l.zPosition = 20
        addChild(l)
        lid = l
        let warm = (tint ?? UIColor(hex: 0x7FE0C4)).withAlphaComponent(dark ? 0.3 : 0.28)
        setHighlighted(false)
        let rest = CGPoint(x: 0, y: size.height / 2 + max(2.5, size.width * 0.045))
        guard animated else {
            glass.fillColor = warm
            l.position = rest
            return
        }
        glass.run(.customAction(withDuration: 0.25) { [weak glass] _, _ in glass?.fillColor = warm })
        if reduceMotion {
            l.position = rest
            l.alpha = 0
            l.run(.fadeIn(withDuration: 0.25))
            onLand?()
            return
        }
        l.position = CGPoint(x: 0, y: rest.y + size.height * 0.55)
        let drop = SKAction.move(to: rest, duration: 0.18)
        drop.timingMode = .easeIn
        let squash = SKAction.sequence([
            .scaleX(to: 1.16, y: 0.72, duration: 0.05),
            .scaleX(to: 0.95, y: 1.08, duration: 0.05),
            .scaleX(to: 1.04, y: 0.96, duration: 0.04),
            .scaleX(to: 1, y: 1, duration: 0.04),
        ])
        // A quarter twist: the lid narrows and comes back, as if turning.
        let twist = SKAction.sequence([
            .scaleX(to: 0.8, duration: 0.07), .scaleX(to: 1, duration: 0.08),
        ])
        l.run(.sequence([
            .wait(forDuration: 0.12), drop,
            .run { onLand?() },
            squash,
            .run { onTwist?() },
            twist,
            .run { [weak self] in self?.rays() },
        ]))
        // The jar gives with the lid.
        run(.sequence([
            .wait(forDuration: 0.3),
            .scaleX(to: 1.05, y: 0.96, duration: 0.05),
            .scaleX(to: 1, y: 1, duration: 0.1),
        ]))
    }

    /// Gold rays and sparkles behind the lid.
    private func rays() {
        let center = CGPoint(x: 0, y: size.height / 2 + size.width * 0.2)
        for i in 0..<10 {
            let ray = SKShapeNode(rectOf: CGSize(width: 3, height: size.width * 0.32), cornerRadius: 1.5)
            ray.fillColor = UIColor(hex: i % 2 == 0 ? 0xFFD86B : 0xFFFFFF)
            ray.strokeColor = .clear
            // A fan over the top half.
            let a = CGFloat.pi * (0.05 + 0.9 * CGFloat(i) / 9)
            ray.zRotation = a - .pi / 2
            ray.position = CGPoint(x: center.x + cos(a) * size.width * 0.35, y: center.y + sin(a) * size.width * 0.35)
            ray.zPosition = 15
            ray.alpha = 0.95
            addChild(ray)
            ray.run(.sequence([
                .group([.moveBy(x: cos(a) * size.width * 0.5, y: sin(a) * size.width * 0.5, duration: 0.3),
                        .fadeOut(withDuration: 0.3), .scaleY(to: 1.6, duration: 0.3)]),
                .removeFromParent(),
            ]))
        }
    }
}
