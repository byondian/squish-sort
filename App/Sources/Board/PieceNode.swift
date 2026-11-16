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

/// A clear jelly jar.
final class JarNode: SKNode {
    let size: CGSize
    private let glass: SKShapeNode
    private var lid: SKShapeNode?

    init(size: CGSize) {
        self.size = size
        glass = SKShapeNode(rectOf: size, cornerRadius: size.width * 0.3)
        super.init()
        glass.fillColor = UIColor.white.withAlphaComponent(0.45)
        glass.strokeColor = UIColor.plum.withAlphaComponent(0.55)
        glass.lineWidth = 3
        addChild(glass)
        let rim = SKShapeNode(rectOf: CGSize(width: size.width * 0.12, height: size.height * 0.6),
                              cornerRadius: size.width * 0.06)
        rim.fillColor = UIColor.white.withAlphaComponent(0.6)
        rim.strokeColor = .clear
        rim.position = CGPoint(x: -size.width * 0.3, y: size.height * 0.05)
        addChild(rim)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setHighlighted(_ on: Bool) {
        glass.strokeColor = on ? UIColor(hex: 0xFF7EB6) : UIColor.plum.withAlphaComponent(0.55)
        glass.lineWidth = on ? 5 : 3
    }

    /// Lid plops down and bounces; the jar glows mint.
    func putLid(animated: Bool) {
        guard lid == nil else { return }
        let l = SKShapeNode(rectOf: CGSize(width: size.width * 1.08, height: size.width * 0.28),
                            cornerRadius: size.width * 0.12)
        l.fillColor = UIColor(hex: 0x7FE0C4)
        l.strokeColor = .plum
        l.lineWidth = 3
        l.zPosition = 20
        addChild(l)
        lid = l
        glass.fillColor = UIColor(hex: 0x7FE0C4).withAlphaComponent(0.25)
        let rest = CGPoint(x: 0, y: size.height / 2 + size.width * 0.1)
        if animated {
            l.position = CGPoint(x: 0, y: rest.y + size.height * 0.5)
            l.run(.sequence([
                .move(to: rest, duration: 0.18),
                .moveBy(x: 0, y: size.width * 0.12, duration: 0.08),
                .move(to: rest, duration: 0.1),
            ]))
        } else {
            l.position = rest
        }
    }
}
