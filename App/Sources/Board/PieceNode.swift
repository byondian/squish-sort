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
        duetMark = SKLabelNode(text: String(localized: "DUET"))
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

        duetMark.fontSize = d * 0.2
        duetMark.fontName = "AvenirNext-Heavy"
        duetMark.fontColor = UIColor(hex: 0xFF7EB6)
        duetMark.verticalAlignmentMode = .center
        duetMark.position = CGPoint(x: 0, y: d * 0.5)
        duetMark.zPosition = 2
        duetMark.isHidden = true
        // A white pill behind the word keeps it readable on any squishy.
        let tag = SKShapeNode(rectOf: CGSize(width: d * 0.62, height: d * 0.26), cornerRadius: d * 0.13)
        tag.fillColor = .white
        tag.strokeColor = UIColor(hex: 0xFF7EB6)
        tag.lineWidth = 1.5
        tag.zPosition = -1
        duetMark.addChild(tag)
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

    /// Bubble Bath: a floater. The squishy sits inside a big glossy soap bubble that covers all of it,
    /// so it can never be taken for part of the squishy's own picture. A golden bubble can ride.
    private var bubbleWorld = false
    private var golden = false
    private static let bubbleBlue = UIColor(hex: 0x3FB6F2)
    private static let bubbleGold = UIColor(hex: 0xFFB300)

    func useBubble() {
        bubbleWorld = true
        let d = diameter * 1.22
        ice.path = CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d), transform: nil)
        ice.zPosition = 4
        ice.lineWidth = max(3.5, diameter * 0.07)
        ice.removeAllChildren()
        // A long shine top left, a small one bottom right, and a rim of light inside the edge.
        let shine = SKShapeNode(ellipseOf: CGSize(width: d * 0.3, height: d * 0.12))
        shine.fillColor = UIColor.white.withAlphaComponent(0.95)
        shine.strokeColor = .clear
        shine.zRotation = 0.7
        shine.position = CGPoint(x: -d * 0.22, y: d * 0.27)
        ice.addChild(shine)
        let dot = SKShapeNode(circleOfRadius: d * 0.045)
        dot.fillColor = UIColor.white.withAlphaComponent(0.9)
        dot.strokeColor = .clear
        dot.position = CGPoint(x: d * 0.27, y: -d * 0.24)
        ice.addChild(dot)
        let rim = SKShapeNode(circleOfRadius: d * 0.44)
        rim.fillColor = .clear
        rim.strokeColor = UIColor.white.withAlphaComponent(0.55)
        rim.lineWidth = 2
        ice.addChild(rim)
        let star = SKLabelNode(text: "★")
        star.name = "ride-star"
        star.fontSize = d * 0.3
        star.fontColor = PieceNode.bubbleGold
        star.verticalAlignmentMode = .center
        star.position = CGPoint(x: d * 0.34, y: d * 0.34)
        star.isHidden = true
        ice.addChild(star)
        colourBubble()
    }

    private func colourBubble() {
        let colour = golden ? PieceNode.bubbleGold : PieceNode.bubbleBlue
        ice.strokeColor = colour
        ice.fillColor = (golden ? UIColor(hex: 0xFFE27A) : UIColor(hex: 0xBDEBFF)).withAlphaComponent(0.42)
        ice.childNode(withName: "ride-star")?.isHidden = !golden
    }

    /// In a bubble right now (Bubble Bath).
    var hasBubble: Bool { bubbleWorld && !ice.isHidden }
    /// In a golden bubble that can ride.
    var hasGoldenBubble: Bool { hasBubble && golden }
    /// Where the middle of the squishy is, in the parent's coordinates (the node's origin is its bottom).
    var middle: CGPoint { CGPoint(x: position.x, y: position.y + diameter / 2) }

    /// The bubble wobbles: "not here" on a sealed jar, and "tap me" on a golden one.
    func wobbleBubble() {
        guard hasBubble, !UIAccessibility.isReduceMotionEnabled else { return }
        ice.removeAction(forKey: "wobble")
        ice.run(.sequence([
            .scaleX(to: 1.12, y: 0.9, duration: 0.08), .scaleX(to: 0.92, y: 1.1, duration: 0.09),
            .scaleX(to: 1.05, y: 0.96, duration: 0.08), .scaleX(to: 1, y: 1, duration: 0.08),
        ]), withKey: "wobble")
    }

    /// The bubble bursts: a ring flies outwards and drops scatter.
    private func burstBubble() {
        let d = diameter * 1.22
        let colour = golden ? PieceNode.bubbleGold : PieceNode.bubbleBlue
        let ring = SKShapeNode(circleOfRadius: d / 2)
        ring.strokeColor = colour
        ring.lineWidth = 4
        ring.fillColor = .clear
        ring.zPosition = 6
        content.addChild(ring)
        if UIAccessibility.isReduceMotionEnabled {
            ring.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
            return
        }
        ring.run(.sequence([.group([.scale(to: 1.5, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
        for n in 0..<8 {
            let drop = SKShapeNode(circleOfRadius: d * 0.05)
            drop.fillColor = colour
            drop.strokeColor = .white
            drop.lineWidth = 1
            drop.zPosition = 6
            let angle = CGFloat(n) * .pi / 4 + 0.3
            drop.position = CGPoint(x: cos(angle) * d * 0.45, y: sin(angle) * d * 0.45)
            content.addChild(drop)
            let out = SKAction.moveBy(x: cos(angle) * d * 0.5, y: sin(angle) * d * 0.5 - d * 0.15, duration: 0.3)
            out.timingMode = .easeOut
            drop.run(.sequence([.group([out, .fadeOut(withDuration: 0.3), .scale(to: 0.4, duration: 0.3)]), .removeFromParent()]))
        }
        run(.sequence([.scale(to: 1.12, duration: 0.07), .scale(to: 1, duration: 0.12)]))
    }

    private var morphLook: SKNode?

    /// A morph piece is drawn split corner to corner: its own kind on top, the kind it turns into
    /// below, with a small white swirl badge. `other` nil takes the split away.
    func showMorph(other: String?) {
        morphLook?.removeFromParent()
        morphLook = nil
        guard let other else { return }
        let d = diameter
        let look = SKNode()
        look.zPosition = 2.5
        let half = CGMutablePath()
        half.move(to: CGPoint(x: -d * 0.62, y: -d * 0.62))
        half.addLine(to: CGPoint(x: d * 0.62, y: -d * 0.62))
        half.addLine(to: CGPoint(x: d * 0.62, y: d * 0.62))
        half.closeSubpath()
        let mask = SKShapeNode(path: half)
        mask.fillColor = .white
        mask.strokeColor = .clear
        let crop = SKCropNode()
        crop.maskNode = mask
        let otherStyle = SquishyStyle.forID(other)
        if UIImage(named: "squishy-\(other)") != nil {
            let sprite = SKSpriteNode(texture: SKTexture(imageNamed: "squishy-\(other)"))
            let box = SquishMask.opaqueBox(named: "squishy-\(other)")
            let side = min(d * 1.6, d * 0.96 / max(box.width, box.height, 0.4))
            sprite.size = CGSize(width: side, height: side)
            sprite.position = CGPoint(x: (0.5 - box.midX) * side, y: -d * 0.48 - (0.5 - box.maxY) * side)
            crop.addChild(sprite)
        } else {
            let blob = SKShapeNode(path: otherStyle.bodyPath(diameter: d))
            blob.fillColor = otherStyle.color
            blob.strokeColor = .plum
            blob.lineWidth = max(1.5, d * 0.04)
            crop.addChild(blob)
        }
        look.addChild(crop)
        let seamPath = CGMutablePath()
        seamPath.move(to: CGPoint(x: -d * 0.36, y: -d * 0.36))
        seamPath.addLine(to: CGPoint(x: d * 0.36, y: d * 0.36))
        let seam = SKShapeNode(path: seamPath)
        seam.strokeColor = .white
        seam.lineWidth = max(2, d * 0.05)
        seam.lineCap = .round
        look.addChild(seam)
        // The swirl badge, bottom left.
        let badge = SKShapeNode(circleOfRadius: d * 0.15)
        badge.fillColor = .white
        badge.strokeColor = .plum
        badge.lineWidth = max(1.5, d * 0.03)
        badge.position = CGPoint(x: -d * 0.3, y: -d * 0.3)
        let spiral = CGMutablePath()
        for n in 0...40 {
            let t = CGFloat(n) / 40
            let angle = t * 3.2 * .pi
            let r = d * 0.105 * t
            let point = CGPoint(x: cos(angle) * r, y: sin(angle) * r)
            if n == 0 { spiral.move(to: point) } else { spiral.addLine(to: point) }
        }
        let swirl = SKShapeNode(path: spiral)
        swirl.strokeColor = otherStyle.color
        swirl.lineWidth = max(1.5, d * 0.035)
        swirl.lineCap = .round
        swirl.fillColor = .clear
        badge.addChild(swirl)
        if !UIAccessibility.isReduceMotionEnabled {
            swirl.run(.repeatForever(.rotate(byAngle: -2 * CGFloat.pi, duration: 4)))
        }
        look.addChild(badge)
        content.addChild(look)
        morphLook = look
    }

    /// A morph piece flips: this node squashes flat and goes; `next`, the piece in its new kind, pops up in its place.
    func morph(into next: PieceNode, calm: Bool) {
        next.position = position
        next.zPosition = zPosition
        if calm {
            next.alpha = 0
            next.run(.fadeIn(withDuration: 0.25))
            run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
            return
        }
        next.setScale(0.2)
        next.alpha = 0
        next.run(.sequence([
            .wait(forDuration: 0.1),
            .group([.fadeIn(withDuration: 0.05), .scale(to: 1.18, duration: 0.12)]),
            .scale(to: 1, duration: 0.1),
        ]))
        run(.sequence([.scaleX(to: 1.3, y: 0.25, duration: 0.1), .removeFromParent()]))
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
        let hadBubble = hasBubble
        ice.isHidden = !piece.isFrozen
        if bubbleWorld {
            ice.alpha = 1
            if hadBubble && !piece.isFrozen { burstBubble() }
            if piece.isFrozen {
                golden = piece.frozen == 2
                colourBubble()
                if !hadBubble && !UIAccessibility.isReduceMotionEnabled {
                    // A bubble breathes a little, so it reads as a bubble and not as a drawn ring.
                    let slow = golden ? 0.5 : 0.9
                    ice.run(.repeatForever(.sequence([
                        .scaleX(to: 1.04, y: 0.97, duration: slow), .scaleX(to: 0.97, y: 1.04, duration: slow),
                    ])), withKey: "breathe")
                }
            } else {
                ice.removeAction(forKey: "breathe")
            }
        } else {
            ice.alpha = piece.frozen >= 2 ? 1 : 0.6
        }
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
    var hasLid: Bool { lid != nil }

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
    init(size: CGSize, world: String = "", dark: Bool = false, gold: Bool = false) {
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
        // The mouth of the jar: a ring seen a little from above, with the opening showing through,
        // so an empty or part-filled jar reads as open and never as lidded.
        let mouth = CGSize(width: size.width * 1.06, height: max(9, size.width * 0.2))
        let rim = SKShapeNode(ellipseOf: mouth)
        // A boss level's jars have gold rims.
        rim.fillColor = gold ? UIColor(hex: 0xFFC93C) : UIColor.white.withAlphaComponent(dark ? 0.55 : 0.95)
        rim.strokeColor = gold ? UIColor(hex: 0xC78A12) : UIColor(hex: 0x965A78).withAlphaComponent(0.28)
        rim.lineWidth = 1.5
        rim.position = CGPoint(x: 0, y: size.height / 2)
        rim.zPosition = 1
        addChild(rim)
        let opening = SKShapeNode(ellipseOf: CGSize(width: mouth.width - 9, height: max(3, mouth.height - 7)))
        opening.fillColor = dark ? UIColor(hex: 0x241A45).withAlphaComponent(0.55) : UIColor(hex: 0x965A78).withAlphaComponent(0.2)
        opening.strokeColor = gold ? UIColor(hex: 0xC78A12).withAlphaComponent(0.6) : UIColor(hex: 0x965A78).withAlphaComponent(0.22)
        opening.lineWidth = 1
        opening.zPosition = 1
        rim.addChild(opening)
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
        case "bubblebath": return String(localized: "Splash!")
        case "junglejam": return String(localized: "Wild!")
        case "spacestation": return String(localized: "Lift-off!")
        case "morphlab": return String(localized: "Eureka!")
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
        case "bubblebath":
            // A soap-bubble dome on a white rim.
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: -w * 0.46, y: h * 0.3))
            dome.addCurve(to: CGPoint(x: w * 0.46, y: h * 0.3), control1: CGPoint(x: -w * 0.46, y: h * 2.1),
                          control2: CGPoint(x: w * 0.46, y: h * 2.1))
            dome.closeSubpath()
            let bubble = SKShapeNode(path: dome)
            bubble.fillColor = UIColor(hex: 0xBFEFFF).withAlphaComponent(0.75)
            bubble.strokeColor = .plum
            bubble.lineWidth = 2.5
            node.addChild(bubble)
            node.addChild(cap(.white, height: h * 0.4))
            let shine = SKShapeNode(ellipseOf: CGSize(width: w * 0.2, height: h * 0.24))
            shine.fillColor = UIColor.white.withAlphaComponent(0.9)
            shine.strokeColor = .clear
            shine.zRotation = 0.5
            shine.position = CGPoint(x: -w * 0.18, y: h * 1.15)
            node.addChild(shine)
        case "junglejam":
            // A coconut-shell cap with a leaf on top.
            let shell = CGMutablePath()
            shell.move(to: CGPoint(x: -w / 2, y: 0))
            shell.addCurve(to: CGPoint(x: w / 2, y: 0), control1: CGPoint(x: -w / 2, y: h * 1.5),
                           control2: CGPoint(x: w / 2, y: h * 1.5))
            shell.closeSubpath()
            let coconut = SKShapeNode(path: shell)
            coconut.fillColor = UIColor(hex: 0x9C6E42)
            coconut.strokeColor = .plum
            coconut.lineWidth = 2.5
            node.addChild(coconut)
            for k in 0..<3 {
                let dot = SKShapeNode(circleOfRadius: h * 0.07)
                dot.fillColor = UIColor(hex: 0x5E3F22)
                dot.strokeColor = .clear
                dot.position = CGPoint(x: (CGFloat(k) - 1) * w * 0.12, y: h * (k == 1 ? 0.62 : 0.48))
                node.addChild(dot)
            }
            let leaf = SKShapeNode(ellipseOf: CGSize(width: w * 0.34, height: h * 0.3))
            leaf.fillColor = UIColor(hex: 0x7CCB6B)
            leaf.strokeColor = .plum
            leaf.lineWidth = 2
            leaf.zRotation = 0.5
            leaf.position = CGPoint(x: w * 0.1, y: h * 1.2)
            node.addChild(leaf)
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

/// The vine that ties a Jungle Jam jar shut: two leafy ropes across the glass and a tag with the
/// number of jars still to finish. Drawn about the jar's centre; what is inside stays in view.
final class VineNode: SKNode {
    private let ropes = SKNode()
    private let tag = SKNode()
    private let number = SKLabelNode(text: "")

    init(size: CGSize, tag count: Int) {
        super.init()
        let w = size.width, h = size.height
        let heights: [CGFloat] = [h * 0.24, -h * 0.2]
        for (k, y) in heights.enumerated() {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w / 2 - 5, y: y + 5))
            path.addQuadCurve(to: CGPoint(x: w / 2 + 5, y: y + 5), control: CGPoint(x: 0, y: y - 9))
            let rope = SKShapeNode(path: path)
            rope.strokeColor = UIColor(hex: 0x3F8F4C)
            rope.lineWidth = 6
            rope.lineCap = .round
            rope.fillColor = .clear
            ropes.addChild(rope)
            let side: CGFloat = k == 0 ? 1 : -1
            for x in [-w * 0.3, w * 0.26] {
                let leaf = SKShapeNode(ellipseOf: CGSize(width: 13, height: 7))
                leaf.fillColor = UIColor(hex: 0x7CCB6B)
                leaf.strokeColor = UIColor(hex: 0x3F8F4C)
                leaf.lineWidth = 1.5
                leaf.zRotation = x < 0 ? 0.7 : -0.7
                leaf.position = CGPoint(x: x * side, y: y + 6)
                ropes.addChild(leaf)
            }
        }
        addChild(ropes)
        let card = SKShapeNode(rect: CGRect(x: -15, y: -14, width: 30, height: 28), cornerRadius: 8)
        card.fillColor = UIColor(hex: 0xFFF4D6)
        card.strokeColor = .plum
        card.lineWidth = 2.5
        tag.addChild(card)
        number.fontName = "AvenirNext-Heavy"
        number.fontSize = 19
        number.fontColor = .plum
        number.verticalAlignmentMode = .center
        number.horizontalAlignmentMode = .center
        number.text = "\(count)"
        tag.addChild(number)
        tag.position = CGPoint(x: 0, y: h * 0.02)
        addChild(tag)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The tag counts down with a little pop.
    func set(_ count: Int) {
        let text = "\(count)"
        guard number.text != text else { return }
        number.text = text
        tag.run(.sequence([.scale(to: 1.35, duration: 0.1), .scale(to: 1, duration: 0.14)]))
    }

    /// A tap on a tied jar: the vine gives a little and holds.
    func wobble() {
        ropes.removeAction(forKey: "wobble")
        ropes.yScale = 1
        ropes.run(.sequence([.scaleY(to: 1.12, duration: 0.07), .scaleY(to: 0.94, duration: 0.09), .scaleY(to: 1, duration: 0.08)]), withKey: "wobble")
    }

    /// Snap: the ropes whip away to the sides and the tag drops. With Reduce Motion it fades.
    func snap(calm: Bool) {
        if calm {
            run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            return
        }
        let away = SKAction.group([.scaleX(to: 0.1, duration: 0.25), .fadeOut(withDuration: 0.25)])
        ropes.run(away)
        let fall = SKAction.group([.moveBy(x: 0, y: -46, duration: 0.4), .rotate(byAngle: 0.9, duration: 0.4), .fadeOut(withDuration: 0.4)])
        fall.timingMode = .easeIn
        tag.run(fall)
        run(.sequence([.wait(forDuration: 0.45), .removeFromParent()]))
    }
}

/// The padlock on a key jar: a bar across the jar's mouth and a padlock whose body is the colour of
/// the key squishy, with that squishy's picture on it. Drawn about the jar's centre.
final class LockNode: SKNode {
    private let shackle: SKShapeNode
    private let padlock = SKNode()
    private let bar: SKShapeNode

    init(size: CGSize, keyID: String) {
        let w = size.width, h = size.height
        let side = min(w * 0.62, 46)
        let arc = CGMutablePath()
        arc.move(to: CGPoint(x: -side * 0.26, y: side * 0.3))
        arc.addLine(to: CGPoint(x: -side * 0.26, y: side * 0.56))
        arc.addArc(center: CGPoint(x: 0, y: side * 0.56), radius: side * 0.26, startAngle: .pi, endAngle: 0, clockwise: true)
        arc.addLine(to: CGPoint(x: side * 0.26, y: side * 0.3))
        shackle = SKShapeNode(path: arc)
        bar = SKShapeNode(rect: CGRect(x: -w / 2 - 4, y: -4, width: w + 8, height: 8), cornerRadius: 4)
        super.init()
        let style = SquishyStyle.forID(keyID)
        bar.fillColor = UIColor(hex: 0xC9B8E8)
        bar.strokeColor = .plum
        bar.lineWidth = 2
        bar.position = CGPoint(x: 0, y: h / 2 - 2)
        addChild(bar)
        shackle.strokeColor = .plum
        shackle.lineWidth = max(4, side * 0.13)
        shackle.lineCap = .round
        shackle.fillColor = .clear
        padlock.addChild(shackle)
        let body = SKShapeNode(rect: CGRect(x: -side / 2, y: -side * 0.42, width: side, height: side * 0.84), cornerRadius: side * 0.2)
        body.fillColor = style.color
        body.strokeColor = .plum
        body.lineWidth = 2.5
        padlock.addChild(body)
        if UIImage(named: "squishy-\(keyID)") != nil {
            let face = SKSpriteNode(texture: SKTexture(imageNamed: "squishy-\(keyID)"))
            face.size = CGSize(width: side * 0.74, height: side * 0.74)
            face.zPosition = 1
            // A white disc behind it, so the squishy reads on a body of its own colour.
            let disc = SKShapeNode(circleOfRadius: side * 0.36)
            disc.fillColor = UIColor.white.withAlphaComponent(0.85)
            disc.strokeColor = .clear
            padlock.addChild(disc)
            padlock.addChild(face)
        } else {
            let dot = SKShapeNode(path: style.bodyPath(diameter: side * 0.5))
            dot.fillColor = .white
            dot.strokeColor = .plum
            dot.lineWidth = 1.5
            padlock.addChild(dot)
        }
        padlock.position = CGPoint(x: 0, y: h / 2 - 2)
        addChild(padlock)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A tap on a locked jar: the padlock rattles and holds.
    func rattle() {
        padlock.removeAction(forKey: "rattle")
        padlock.zRotation = 0
        padlock.run(.sequence([
            .rotate(toAngle: 0.22, duration: 0.05), .rotate(toAngle: -0.22, duration: 0.08),
            .rotate(toAngle: 0.1, duration: 0.06), .rotate(toAngle: 0, duration: 0.05),
        ]), withKey: "rattle")
    }

    /// Open: the padlock squishes, the shackle pops up, and it all drops away. With Reduce Motion it fades.
    func open(calm: Bool) {
        if calm {
            run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            return
        }
        shackle.run(.moveBy(x: 0, y: 9, duration: 0.12))
        padlock.run(.sequence([
            .scaleX(to: 1.25, y: 0.75, duration: 0.09), .scaleX(to: 0.92, y: 1.12, duration: 0.1), .scale(to: 1, duration: 0.08),
            .wait(forDuration: 0.12),
            .group([.moveBy(x: 0, y: -40, duration: 0.35), .rotate(byAngle: 0.8, duration: 0.35), .fadeOut(withDuration: 0.35)]),
        ]))
        bar.run(.sequence([.wait(forDuration: 0.3), .group([.scaleX(to: 0.1, duration: 0.2), .fadeOut(withDuration: 0.2)])]))
        run(.sequence([.wait(forDuration: 0.8), .removeFromParent()]))
    }
}

/// The zero gravity ring of a Space Station spin jar: a tilted hoop round the jar with a little moon
/// going round it, and a round button under the jar. A tap on the button turns the jar upside down.
final class SpinRingNode: SKNode {
    enum State { case ready, resting, gone }

    private let hoop = SKNode()
    private let button = SKNode()
    private let arrow = SKLabelNode(text: "↻")
    /// Where the button's middle is, measured from the jar's middle.
    let buttonOffset: CGPoint
    /// How far from the button's middle a tap still counts.
    let reach: CGFloat
    private(set) var state = State.ready

    init(size: CGSize, piece: CGFloat, calm: Bool) {
        let w = size.width, h = size.height
        let radius = max(11, min(piece * 0.3, 24))
        buttonOffset = CGPoint(x: 0, y: -h / 2 - radius * 0.15)
        reach = max(radius * 1.45, 22)
        super.init()
        let glow = UIColor(hex: 0x7CE8FF)
        // The hoop is an ellipse seen from a little above: the far half is faint, the near half bright.
        let rx = w * 0.66, squash: CGFloat = 0.3
        let flat = CGAffineTransform(scaleX: 1, y: squash)
        let far = CGMutablePath()
        far.addArc(center: .zero, radius: rx, startAngle: 0, endAngle: .pi, clockwise: false, transform: flat)
        let near = CGMutablePath()
        near.addArc(center: .zero, radius: rx, startAngle: .pi, endAngle: .pi * 2, clockwise: false, transform: flat)
        for (path, alpha, width) in [(far, CGFloat(0.35), CGFloat(2)), (near, CGFloat(0.95), CGFloat(3.5))] {
            let line = SKShapeNode(path: path)
            line.strokeColor = glow.withAlphaComponent(alpha)
            line.lineWidth = width
            line.lineCap = .round
            line.fillColor = .clear
            line.glowWidth = alpha > 0.5 ? 1.5 : 0
            hoop.addChild(line)
        }
        let moon = SKShapeNode(circleOfRadius: max(3, piece * 0.07))
        moon.fillColor = UIColor(hex: 0xFFF4D6)
        moon.strokeColor = glow
        moon.lineWidth = 1.5
        moon.position = CGPoint(x: -rx, y: 0)
        hoop.addChild(moon)
        if !calm {
            let orbit = CGMutablePath()
            orbit.addEllipse(in: CGRect(x: -rx, y: -rx * squash, width: rx * 2, height: rx * 2 * squash))
            moon.run(.repeatForever(.follow(orbit, asOffset: false, orientToPath: false, duration: 5)))
        }
        hoop.position = CGPoint(x: 0, y: -h * 0.2)
        addChild(hoop)

        let disc = SKShapeNode(circleOfRadius: radius)
        disc.fillColor = UIColor(hex: 0xFFD86B)
        disc.strokeColor = .plum
        disc.lineWidth = 2.5
        button.addChild(disc)
        arrow.fontName = "AvenirNext-Heavy"
        arrow.fontSize = radius * 1.5
        arrow.fontColor = .plum
        arrow.verticalAlignmentMode = .center
        arrow.horizontalAlignmentMode = .center
        arrow.zPosition = 1
        button.addChild(arrow)
        button.position = buttonOffset
        button.zPosition = 2
        addChild(button)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Ready: the jar can turn. Resting: a turn would change nothing right now. Gone: the jar is finished.
    func set(_ next: State, animated: Bool) {
        guard next != state else { return }
        state = next
        let (ring, knob): (CGFloat, CGFloat) = next == .ready ? (1, 1) : next == .resting ? (0.55, 0.4) : (0, 0)
        hoop.removeAction(forKey: "state")
        button.removeAction(forKey: "state")
        guard animated else {
            hoop.alpha = ring
            button.alpha = knob
            return
        }
        hoop.run(.fadeAlpha(to: ring, duration: 0.25), withKey: "state")
        button.run(.fadeAlpha(to: knob, duration: 0.25), withKey: "state")
    }

    /// The jar turns: the arrow goes round once and the button gives under the finger.
    func turn(duration: Double, calm: Bool) {
        button.removeAction(forKey: "press")
        button.setScale(1)
        button.run(.sequence([.scale(to: 0.82, duration: 0.06), .scale(to: 1.1, duration: 0.1), .scale(to: 1, duration: 0.08)]), withKey: "press")
        guard !calm else { return }
        arrow.removeAction(forKey: "turn")
        arrow.zRotation = 0
        let round = SKAction.rotate(byAngle: -.pi * 2, duration: duration)
        round.timingMode = .easeInEaseOut
        arrow.run(.sequence([round, .rotate(toAngle: 0, duration: 0)]), withKey: "turn")
    }

    /// A tap when the jar cannot turn: the button shakes its head.
    func refuse() {
        button.removeAction(forKey: "press")
        button.setScale(1)
        let x = buttonOffset.x
        button.run(.sequence([
            .moveTo(x: x - 4, duration: 0.05), .moveTo(x: x + 4, duration: 0.07), .moveTo(x: x - 2, duration: 0.05), .moveTo(x: x, duration: 0.05),
        ]), withKey: "press")
    }
}

/// The velvet stage curtain in front of a Curtain Call jar. It hangs from its top edge, so it
/// gathers upwards when it rises.
final class CurtainNode: SKNode {
    private let cloth = SKNode()

    init(size: CGSize) {
        super.init()
        let w = size.width, h = size.height
        // The cloth: a scalloped hem at the bottom.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -w / 2, y: 0))
        path.addLine(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: w / 2, y: -h + 6))
        let folds = 4
        let fold = w / CGFloat(folds)
        for i in 0..<folds {
            let x1 = w / 2 - fold * CGFloat(i + 1)
            path.addQuadCurve(to: CGPoint(x: x1, y: -h + 6), control: CGPoint(x: x1 + fold / 2, y: -h - 4))
        }
        path.closeSubpath()
        let velvet = SKShapeNode(path: path)
        velvet.fillColor = UIColor(red: 0.69, green: 0.13, blue: 0.33, alpha: 1)
        velvet.strokeColor = UIColor(red: 0.36, green: 0.07, blue: 0.22, alpha: 1)
        velvet.lineWidth = 2
        cloth.addChild(velvet)
        // Pleats: darker stripes down each fold.
        for i in 1..<folds {
            let pleat = SKShapeNode(rect: CGRect(x: -w / 2 + fold * CGFloat(i) - 1.5, y: -h + 8, width: 3, height: h - 12), cornerRadius: 1.5)
            pleat.fillColor = UIColor(red: 0.45, green: 0.08, blue: 0.25, alpha: 0.55)
            pleat.strokeColor = .clear
            cloth.addChild(pleat)
        }
        // A soft sheen and a gold rail with a star.
        let sheen = SKShapeNode(rect: CGRect(x: -w / 2 + 4, y: -h * 0.8, width: fold * 0.3, height: h * 0.66), cornerRadius: 3)
        sheen.fillColor = UIColor.white.withAlphaComponent(0.16)
        sheen.strokeColor = .clear
        cloth.addChild(sheen)
        addChild(cloth)
        let rail = SKShapeNode(rect: CGRect(x: -w / 2 - 3, y: -5, width: w + 6, height: 9), cornerRadius: 4.5)
        rail.fillColor = UIColor(red: 1, green: 0.82, blue: 0.36, alpha: 1)
        rail.strokeColor = UIColor(red: 0.72, green: 0.5, blue: 0.1, alpha: 1)
        rail.lineWidth = 1.5
        addChild(rail)
        let star = SKLabelNode(text: "★")
        star.fontSize = min(22, w * 0.42)
        star.fontColor = UIColor(red: 1, green: 0.86, blue: 0.45, alpha: 1)
        star.verticalAlignmentMode = .center
        star.position = CGPoint(x: 0, y: -h * 0.48)
        cloth.addChild(star)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A tap on a closed curtain: it sways and stays shut.
    func ripple() {
        cloth.removeAction(forKey: "ripple")
        cloth.xScale = 1
        cloth.run(.sequence([.scaleX(to: 0.92, duration: 0.07), .scaleX(to: 1.04, duration: 0.09), .scaleX(to: 1, duration: 0.08)]), withKey: "ripple")
    }

    func tremble(seconds: Double) {
        let step = SKAction.sequence([.moveBy(x: 1.5, y: 0, duration: 0.03), .moveBy(x: -3, y: 0, duration: 0.06), .moveBy(x: 1.5, y: 0, duration: 0.03)])
        cloth.run(.repeat(step, count: max(1, Int(seconds / 0.12))))
    }

    /// Up it goes, gathered to the rail, and away. With Reduce Motion it fades.
    func rise(calm: Bool) {
        if calm {
            run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            return
        }
        let up = SKAction.scaleY(to: 0.06, duration: 0.45)
        up.timingMode = .easeIn
        cloth.run(up)
        run(.sequence([.wait(forDuration: 0.45), .fadeOut(withDuration: 0.25), .removeFromParent()]))
    }
}

/// The show around a Starlight board: six stage lamps along the top, one switched on by each
/// finished jar in that jar's colour, and a front row of fans with lightsticks along the bottom
/// who sway all the time and cheer when a jar is finished. No flashing, and still with Reduce Motion.
final class StageShowNode: SKNode {
    private var lamps: [SKShapeNode] = []
    private var sticks: [SKShapeNode] = []
    private var lit = 0
    private let calm: Bool

    init(size: CGSize, calm: Bool) {
        self.calm = calm
        super.init()
        let count = 6
        for i in 0..<count {
            let lamp = SKShapeNode(circleOfRadius: 6)
            lamp.fillColor = UIColor.white.withAlphaComponent(0.18)
            lamp.strokeColor = UIColor.white.withAlphaComponent(0.35)
            lamp.lineWidth = 1.5
            lamp.position = CGPoint(x: size.width * (CGFloat(i) + 0.5) / CGFloat(count), y: size.height - 9)
            addChild(lamp)
            lamps.append(lamp)
        }
        let fans = 9
        let colours: [UIColor] = [UIColor(named: "Bubblegum"), UIColor(named: "Butter"), UIColor(named: "Mint"),
                                  UIColor(named: "Sky"), UIColor(named: "Grape")].map { $0 ?? .white }
        for i in 0..<fans {
            let x = size.width * (CGFloat(i) + 0.5) / CGFloat(fans)
            let fan = SKShapeNode(rect: CGRect(x: -9, y: -10, width: 18, height: 20), cornerRadius: 8)
            fan.fillColor = UIColor.black.withAlphaComponent(0.35)
            fan.strokeColor = .clear
            fan.position = CGPoint(x: x, y: 2)
            addChild(fan)
            let stick = SKShapeNode(rect: CGRect(x: -1.5, y: 0, width: 3, height: 11), cornerRadius: 1.5)
            stick.fillColor = colours[i % colours.count]
            stick.strokeColor = .clear
            stick.position = CGPoint(x: x + 7, y: 8)
            addChild(stick)
            sticks.append(stick)
            if !calm {
                let sway = SKAction.sequence([.rotate(toAngle: 0.22, duration: 0.7), .rotate(toAngle: -0.22, duration: 0.7)])
                stick.run(.sequence([.wait(forDuration: 0.11 * Double(i)), .repeatForever(sway)]), withKey: "sway")
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The next lamp comes on in the finished jar's colour.
    func lightLamp(_ colour: UIColor, animated: Bool) {
        guard lit < lamps.count else { return }
        let lamp = lamps[lit]
        lit += 1
        lamp.fillColor = colour
        lamp.strokeColor = .white
        lamp.glowWidth = 3
        guard animated else { return }
        lamp.setScale(0.4)
        lamp.run(.sequence([.scale(to: 1.5, duration: 0.2), .scale(to: 1, duration: 0.2)]))
    }

    /// Lightsticks up!
    func cheer() {
        guard !calm else { return }
        for (i, stick) in sticks.enumerated() {
            let up = SKAction.moveBy(x: 0, y: 7, duration: 0.12)
            up.timingMode = .easeOut
            stick.run(.sequence([.wait(forDuration: 0.03 * Double(i)), up, up.reversed(), up, up.reversed()]), withKey: "cheer")
        }
    }
}
