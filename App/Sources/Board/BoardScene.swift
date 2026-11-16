import SpriteKit
import UIKit
import SquishCore
import SquishSoft

/// The board: jars, squishies and the squish motion (game design doc, game feel).
/// Rules live in SquishCore; this scene only draws and animates.
final class BoardScene: SKScene {
    struct Geometry {
        var jarSize = CGSize.zero
        var piece: CGFloat = 0
        var centers: [CGPoint] = []
    }

    /// Ask the game to play a move. Returns the result and the new board, or nil if refused.
    var onPlay: ((Move) -> (MoveResult, Board)?)?
    /// Feedback hooks for haptics and sound.
    var onLift: (() -> Void)?
    var onReject: (() -> Void)?
    var onLand: ((MoveResult) -> Void)?
    /// Called after a move's animation finishes.
    var onMoveFinished: ((MoveResult) -> Void)?

    private(set) var board: Board
    private let kinds: [String]
    private var geometry = Geometry()
    private var jarNodes: [JarNode] = []
    private var pieces: [[PieceNode]] = []
    private var lifted: Int?
    private var busy = false
    /// First-ever board: this move's squishy starts lifted with a hand on the target jar.
    var tutorialMove: Move?
    /// The kind that glitters on this level (the lucky squishy), if any.
    var luckyKind: UInt8?
    /// The level's world: it picks the lid and the word for a finished jar.
    var world = ""
    /// On a dark background the jars glow instead of having a plum outline.
    var darkBackground = false { didSet { if oldValue != darkBackground, size.width > 0, view != nil { rebuild() } } }
    /// The lid twists shut (a click and a tick).
    var onLidTwist: (() -> Void)?

    init(board: Board, kinds: [String]) {
        self.board = board
        self.kinds = kinds
        super.init(size: CGSize(width: 390, height: 520))
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        rebuild()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if oldSize != size && size.width > 0 { rebuild() }
    }

    /// Replace the board without animation (undo, retry, extra jar).
    func reload(_ board: Board) {
        removeAllActions()
        self.board = board
        lifted = nil
        busy = false
        rebuild()
    }

    // MARK: - Layout

    private func computeGeometry() -> Geometry {
        let rows = BoardLayout.rows(jarCount: board.jarCount)
        let perRow = CGFloat(max(rows.map(\.count).max() ?? 1, 3))
        let margin: CGFloat = 14
        let gap: CGFloat = 10
        let cap = CGFloat(board.capacity)
        let maxJarWidth = (size.width - 2 * margin - gap * (perRow - 1)) / perRow
        let rowUnits = cap + 1.7 // jar plus room to lift above it
        let byHeight = (size.height - 2 * margin) / (CGFloat(rows.count) * rowUnits)
        let piece = max(16, min(maxJarWidth / 1.25, byHeight, 70))
        let jarSize = CGSize(width: piece * 1.25, height: piece * (cap + 0.4))
        let rowHeight = piece * rowUnits
        var centers = Array(repeating: CGPoint.zero, count: board.jarCount)
        let top = size.height / 2 + rowHeight * CGFloat(rows.count) / 2
        for (r, row) in rows.enumerated() {
            let width = CGFloat(row.count) * jarSize.width + CGFloat(row.count - 1) * gap
            let y = top - rowHeight * CGFloat(r) - piece * 1.3 - jarSize.height / 2
            for (i, j) in row.enumerated() {
                let x = size.width / 2 - width / 2 + jarSize.width / 2 + CGFloat(i) * (jarSize.width + gap)
                centers[j] = CGPoint(x: x, y: y)
            }
        }
        return Geometry(jarSize: jarSize, piece: piece, centers: centers)
    }

    private func slot(_ jar: Int, _ index: Int) -> CGPoint {
        let c = geometry.centers[jar]
        // Piece nodes have their origin at the bottom centre (squash anchors there).
        return CGPoint(x: c.x, y: c.y - geometry.jarSize.height / 2 + geometry.piece * (0.2 + CGFloat(index) + 0.07))
    }

    private func liftPoint(_ jar: Int, _ k: Int) -> CGPoint {
        let c = geometry.centers[jar]
        return CGPoint(x: c.x, y: c.y + geometry.jarSize.height / 2 + geometry.piece * (0.22 + CGFloat(k) * 0.9))
    }

    private func rebuild() {
        removeAllChildren()
        // Everything is drawn at rest, so nothing is lifted any more.
        lifted = nil
        guard size.width > 0 else { return }
        geometry = computeGeometry()
        jarNodes = []
        pieces = []
        for j in 0..<board.jarCount {
            let jar = JarNode(size: geometry.jarSize, world: world, dark: darkBackground)
            jar.position = geometry.centers[j]
            addChild(jar)
            jarNodes.append(jar)
            var nodes: [PieceNode] = []
            for (i, piece) in board.jars[j].enumerated() {
                let node = PieceNode(kindID: kinds[Int(piece.kind)], diameter: geometry.piece * 0.86)
                node.position = slot(j, i)
                node.zPosition = 5
                node.isLucky = piece.kind == luckyKind
                node.apply(piece)
                addChild(node)
                nodes.append(node)
            }
            pieces.append(nodes)
            if board.isComplete(j) { jar.putLid(animated: false, tint: nodes.first.map { SquishyStyle.forID($0.kindID).color }) }
        }
        showTutorialIfNeeded()
    }

    private func showTutorialIfNeeded() {
        guard let move = tutorialMove, lifted == nil, board.isLegal(move),
              move.from < board.jarCount, move.to < board.jarCount else { return }
        lift(move.from)
        let hand = SKLabelNode(text: "👆")
        hand.name = "tutorial-hand"
        hand.fontSize = geometry.piece * 0.9
        hand.verticalAlignmentMode = .center
        hand.position = CGPoint(x: geometry.centers[move.to].x + geometry.piece * 0.25,
                                y: geometry.centers[move.to].y - geometry.jarSize.height * 0.1)
        hand.zPosition = 40
        addChild(hand)
        let pulse = SKAction.sequence([
            .group([.scale(to: 1.25, duration: 0.45), .moveBy(x: 0, y: geometry.piece * 0.18, duration: 0.45)]),
            .group([.scale(to: 1, duration: 0.45), .moveBy(x: 0, y: -geometry.piece * 0.18, duration: 0.45)]),
        ])
        hand.run(.repeatForever(pulse))
    }

    private func endTutorial() {
        tutorialMove = nil
        enumerateChildNodes(withName: "tutorial-hand") { node, _ in node.removeFromParent() }
    }

    /// "x3!" pops up where a run of three or more lands.
    private func showCombo(_ count: Int, at jar: Int) {
        guard count >= 3 else { return }
        let label = SKLabelNode(text: "x\(count)!")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = geometry.piece * 0.7
        label.fontColor = UIColor(hex: 0xFF7EB6)
        label.position = CGPoint(x: geometry.centers[jar].x, y: geometry.centers[jar].y + geometry.jarSize.height * 0.55)
        label.zPosition = 35
        label.setScale(0.3)
        addChild(label)
        label.run(.sequence([
            .scale(to: 1.25, duration: 0.12), .scale(to: 1, duration: 0.08),
            .group([.moveBy(x: 0, y: geometry.piece * 0.8, duration: 0.5), .fadeOut(withDuration: 0.5)]),
            .removeFromParent(),
        ]))
    }

    /// Coins burst out of a finished jar and fly up to the level pot.
    func throwCoins(fromJar j: Int, count: Int) {
        guard j < geometry.centers.count, count > 0 else { return }
        let start = CGPoint(x: geometry.centers[j].x, y: geometry.centers[j].y + geometry.jarSize.height * 0.5)
        let target = CGPoint(x: size.width / 2, y: size.height - geometry.piece * 0.2)
        for i in 0..<count {
            let coin = SKShapeNode(circleOfRadius: geometry.piece * 0.15)
            coin.fillColor = UIColor(hex: 0xFFD86B)
            coin.strokeColor = .plum
            coin.lineWidth = 1.5
            coin.position = start
            coin.zPosition = 45
            addChild(coin)
            let burst = CGPoint(x: start.x + CGFloat.random(in: -1...1) * geometry.piece * 0.8,
                                y: start.y + CGFloat.random(in: 0.2...1) * geometry.piece)
            let fly = SKAction.move(to: target, duration: 0.35)
            fly.timingMode = .easeIn
            coin.run(.sequence([
                .wait(forDuration: 0.04 * Double(i)),
                .move(to: burst, duration: 0.15),
                fly,
                .group([.scale(to: 0.3, duration: 0.08), .fadeOut(withDuration: 0.08)]),
                .removeFromParent(),
            ]))
        }
    }

    /// A short word that pops above a jar ("Double pop!", "Lucky!").
    /// A big bouncy word over the middle of the board for about a second (squishy streak).
    func popWord(_ text: String, size scale: CGFloat) {
        guard size.width > 0 else { return }
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = min(geometry.piece * scale, size.width / CGFloat(max(6, text.count)) * 1.5)
        label.fontColor = UIColor(hex: 0xFF7EB6)
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.62)
        label.zPosition = 48
        label.zRotation = -0.08
        label.setScale(0.2)
        // A white copy behind, a little bigger, so the word reads on any board.
        let back = SKLabelNode(text: text)
        back.fontName = label.fontName
        back.fontSize = label.fontSize
        back.fontColor = .white
        back.verticalAlignmentMode = .center
        back.position = CGPoint(x: 0, y: -label.fontSize * 0.06)
        back.zPosition = -1
        label.addChild(back)
        addChild(label)
        label.run(.sequence([
            .scale(to: 1.3, duration: 0.14), .scale(to: 0.95, duration: 0.08), .scale(to: 1.05, duration: 0.07),
            .wait(forDuration: 0.5),
            .group([.moveBy(x: 0, y: geometry.piece * 0.7, duration: 0.3), .fadeOut(withDuration: 0.3)]),
            .removeFromParent(),
        ]))
    }

    func popLabel(_ text: String, atJar j: Int) {
        guard j < geometry.centers.count else { return }
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = geometry.piece * 0.5
        label.fontColor = UIColor(hex: 0xFF7EB6)
        let x = min(max(geometry.centers[j].x, geometry.piece * 2), size.width - geometry.piece * 2)
        label.position = CGPoint(x: x, y: geometry.centers[j].y + geometry.jarSize.height * 0.75)
        label.zPosition = 46
        label.setScale(0.3)
        addChild(label)
        label.run(.sequence([
            .scale(to: 1.2, duration: 0.12), .scale(to: 1, duration: 0.08), .wait(forDuration: 0.5),
            .group([.moveBy(x: 0, y: geometry.piece * 0.6, duration: 0.4), .fadeOut(withDuration: 0.4)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Input

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        clearHint()
        if let j = jarIndex(at: point) {
            tap(j)
        } else if let l = lifted {
            putBack(l)
        }
    }

    private func jarIndex(at p: CGPoint) -> Int? {
        let w = geometry.jarSize.width, h = geometry.jarSize.height
        for (j, c) in geometry.centers.enumerated() {
            let rect = CGRect(x: c.x - w / 2 - 5, y: c.y - h / 2 - 8, width: w + 10, height: h + geometry.piece * 1.4)
            if rect.contains(p) { return j }
        }
        return nil
    }

    private func tap(_ j: Int) {
        guard !busy else { return }
        endTutorial()
        if let from = lifted {
            if from == j {
                putBack(from)
                return
            }
            let move = Move(from: from, to: j)
            if board.isLegal(move), let played = onPlay?(move) {
                lifted = nil
                jarNodes[from].setHighlighted(false)
                animate(played.0, newBoard: played.1)
            } else {
                shake(j)
                putBack(from)
                onReject?()
            }
        } else if board.runLength(at: j) > 0 {
            lift(j)
        } else {
            shake(j)
            onReject?()
        }
    }

    /// Same as a finger tap on jar `j` (used by UI tests and accessibility).
    func tapJar(_ j: Int) {
        taps += 1
        guard j < board.jarCount else { return }
        clearHint()
        tap(j)
    }

    private var taps = 0
    /// One line for UI test failure logs.
    var debugState: String {
        "taps=\(taps) lifted=\(lifted.map(String.init) ?? "-") busy=\(busy) paused=\(isPaused) view=\(view != nil)"
    }

    // MARK: - Motion

    private var lastUpdate: TimeInterval = 0

    /// Every piece has two springs (squash and lean) that run here.
    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 60 : min(0.05, max(0, currentTime - lastUpdate))
        lastUpdate = currentTime
        for (j, jar) in pieces.enumerated() {
            for (i, node) in jar.enumerated() {
                node.advance(dt)
                // A squishy that is not travelling, held up or hopping sits exactly in its place.
                // Whatever interrupted it, it can never be left part way.
                if node.action(forKey: "travel") == nil, node.action(forKey: "wobble") == nil,
                   node.action(forKey: "hop") == nil, j < geometry.centers.count {
                    let home = slot(j, i)
                    if node.position != home { node.position = home }
                    if node.zRotation != 0 { node.zRotation = 0 }
                }
            }
        }
    }

    /// A piece has landed in `jar` at `index`: it squashes, and the whole stack under it gives a little.
    private func land(_ node: PieceNode, jar: Int, index: Int, speed: Double) {
        var peak = node.land(speed: speed)
        var below = index - 1
        var delay = PieceSpring.rippleDelay
        while below >= 0, below < pieces[jar].count, peak > 0.01 {
            peak *= PieceSpring.rippleShare
            pieces[jar][below].ripple(peak: peak, after: delay)
            delay += PieceSpring.rippleDelay
            below -= 1
        }
    }

    /// A quick stretch upwards, rise above the jar, hang with a wobble.
    private func lift(_ j: Int) {
        lifted = j
        jarNodes[j].setHighlighted(true)
        let n = board.runLength(at: j)
        for (k, node) in pieces[j].suffix(n).enumerated() {
            node.removeAction(forKey: "wobble")
            node.removeAction(forKey: "travel")
            node.zPosition = 10
            let rise = SKAction.move(to: liftPoint(j, k), duration: 0.12)
            rise.timingMode = .easeOut
            node.stretchUp()
            let wobble = SKAction.repeatForever(.sequence([
                .rotate(toAngle: 0.06, duration: 0.35),
                .rotate(toAngle: -0.06, duration: 0.35),
            ]))
            node.run(.sequence([rise, wobble]), withKey: "wobble")
        }
        onLift?()
    }

    private func putBack(_ j: Int) {
        lifted = nil
        jarNodes[j].setHighlighted(false)
        for (i, node) in pieces[j].enumerated() {
            node.removeAction(forKey: "wobble")
            node.zRotation = 0
            node.zPosition = 5
            let target = slot(j, i)
            let drop = Double(node.position.y - target.y) / Double(max(geometry.piece, 1))
            guard drop > 0.05 else {
                // Already home, or as good as: make sure it sits exactly in its slot.
                node.removeAction(forKey: "travel")
                node.position = target
                continue
            }
            node.run(.sequence([.move(to: target, duration: 0.12), .run { [weak self, weak node] in
                guard let self, let node else { return }
                node.position = target
                self.land(node, jar: j, index: i, speed: drop / 0.12)
            }]), withKey: "travel")
        }
    }

    private func shake(_ j: Int) {
        let jar = jarNodes[j]
        let x = geometry.centers[j].x
        jar.run(.sequence([
            .moveTo(x: x - 6, duration: 0.05), .moveTo(x: x + 6, duration: 0.07),
            .moveTo(x: x - 3, duration: 0.05), .moveTo(x: x, duration: 0.05),
        ]))
        // The squishies that can't go there shake their heads.
        let unhappy = lifted.map { from in Array(pieces[from].suffix(board.runLength(at: from))) } ?? pieces[j]
        for node in unhappy { node.shakeHead() }
    }

    private func animate(_ result: MoveResult, newBoard: Board) {
        busy = true
        let from = result.move.from, to = result.move.to, k = result.count
        let moving = Array(pieces[from].suffix(k))
        pieces[from].removeLast(k)
        let base = pieces[to].count
        // Pieces of a lifted run that couldn't fit drop back.
        for (i, node) in pieces[from].enumerated() {
            node.removeAction(forKey: "wobble")
            node.zRotation = 0
            node.zPosition = 5
            node.run(.move(to: slot(from, i), duration: 0.12), withKey: "travel")
        }
        let hop = 0.18, stagger = 0.04
        let spread = stagger * Double(max(0, k - 1))
        for (i, node) in moving.enumerated() {
            node.removeAction(forKey: "wobble")
            node.zRotation = 0
            node.zPosition = 12
            let start = node.position
            let target = slot(to, base + i)
            let path = CGMutablePath()
            path.move(to: start)
            path.addQuadCurve(to: target, control: CGPoint(x: (start.x + target.x) / 2,
                                                           y: max(start.y, target.y) + geometry.piece * 1.2))
            let arc = SKAction.follow(path, asOffset: false, orientToPath: false, duration: hop)
            arc.timingMode = .easeInEaseOut
            let spin: SKAction = k >= 3 ? .rotate(byAngle: .pi * 2, duration: hop) : .wait(forDuration: 0)
            // It falls from the top of the arc in half the hop.
            let fall = Double(max(start.y, target.y) + geometry.piece * 0.6 - target.y) / Double(max(geometry.piece, 1))
            let index = base + i
            node.run(.sequence([
                .wait(forDuration: stagger * Double(i)),
                .group([arc, spin]),
                .run { [weak self, weak node] in
                    guard let self, let node else { return }
                    node.zPosition = 5
                    node.position = target
                    self.land(node, jar: to, index: index, speed: fall / (hop / 2))
                },
            ]), withKey: "travel")
        }
        pieces[to].append(contentsOf: moving)
        run(.sequence([
            .wait(forDuration: hop + spread),
            .run { [weak self] in
                self?.onLand?(result)
                self?.showCombo(result.count, at: result.move.to)
            },
            .wait(forDuration: 0.25),
            .run { [weak self] in self?.finish(result, newBoard: newBoard) },
        ]))
    }

    private func finish(_ result: MoveResult, newBoard: Board) {
        board = newBoard
        for j in 0..<min(pieces.count, board.jarCount) {
            for (i, node) in pieces[j].enumerated() where i < board.jars[j].count {
                node.apply(board.jars[j][i])
            }
        }
        if let done = result.completedJar {
            // All four squash down together, let go at once, and the lid drops as they spring past their shape.
            // Then the lid moment: drop, squash, twist, rays, the squishies hop in turn and the world's word pops.
            let jar = jarNodes[done]
            let calm = UIAccessibility.isReduceMotionEnabled
            let tint = pieces[done].first.map { SquishyStyle.forID($0.kindID).color }
            jar.putLid(animated: true, tint: tint, reduceMotion: calm, onLand: { [weak self] in
                guard let self, done < self.pieces.count else { return }
                for node in self.pieces[done] { node.squeezeAndRelease() }
            }, onTwist: { [weak self] in self?.onLidTwist?() })
            sparkle(at: geometry.centers[done])
            let word = JarNode.word(for: world)
            run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in
                guard let self, done < self.pieces.count, done < self.geometry.centers.count else { return }
                self.popLabel(word, atJar: done)
                guard !calm else { return }
                let hop = self.geometry.piece * 0.14
                for (i, node) in self.pieces[done].enumerated() where node.action(forKey: "hop") == nil {
                    let up = SKAction.moveBy(x: 0, y: hop, duration: 0.09)
                    up.timingMode = .easeOut
                    let down = SKAction.moveBy(x: 0, y: -hop, duration: 0.09)
                    down.timingMode = .easeIn
                    node.run(.sequence([.wait(forDuration: 0.05 * Double(i)), up, down]), withKey: "hop")
                }
            }]))
        }
        busy = false
        onMoveFinished?(result)
    }

    private func sparkle(at p: CGPoint) {
        let colors: [UIColor] = [UIColor(hex: 0xFFD86B), UIColor(hex: 0xFF7EB6), UIColor(hex: 0x7CC8FF), .white]
        for i in 0..<10 {
            let dot = SKShapeNode(circleOfRadius: geometry.piece * 0.09)
            dot.fillColor = colors[i % colors.count]
            dot.strokeColor = .clear
            dot.position = CGPoint(x: p.x, y: p.y + geometry.jarSize.height * 0.3)
            dot.zPosition = 30
            addChild(dot)
            let angle = CGFloat(i) / 10 * .pi * 2
            let dist = geometry.piece * 1.3
            dot.run(.sequence([
                .group([.moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: 0.4), .fadeOut(withDuration: 0.4),
                        .scale(to: 0.3, duration: 0.4)]),
                .removeFromParent(),
            ]))
        }
    }

    /// Every jar bounces in turn, left to right. Then the sorted squishies keep
    /// hopping in their jars for as long as the win card is up.
    func celebrate() {
        for (j, jar) in jarNodes.enumerated() {
            let lift = geometry.piece * 0.5
            let wait = SKAction.wait(forDuration: 0.08 * Double(j))
            let bounce = SKAction.sequence([.moveBy(x: 0, y: lift, duration: 0.15), .moveBy(x: 0, y: -lift, duration: 0.15)])
            jar.run(.sequence([wait, bounce]))
            let hop = geometry.piece * 0.16
            for (i, node) in pieces[j].enumerated() {
                let up = SKAction.moveBy(x: 0, y: hop, duration: 0.13)
                up.timingMode = .easeOut
                let down = SKAction.moveBy(x: 0, y: -hop, duration: 0.13)
                down.timingMode = .easeIn
                let rest = SKAction.wait(forDuration: 0.45)
                let hops = SKAction.repeatForever(.sequence([up, down, rest]))
                let stagger = SKAction.wait(forDuration: 0.25 + 0.07 * Double(i))
                node.run(UIAccessibility.isReduceMotionEnabled ? .sequence([wait, bounce]) : .sequence([wait, bounce, stagger, hops]), withKey: "hop")
            }
        }
    }

    /// The board sighs when no move is left.
    func sigh() {
        for node in pieces.joined() {
            node.run(.sequence([.scaleX(to: 1.08, y: 0.9, duration: 0.3), .scaleX(to: 1, y: 1, duration: 0.4)]))
        }
    }

    // MARK: - Hint

    func showHint(_ move: Move) {
        clearHint()
        for (j, delay) in [(move.from, 0.0), (move.to, 0.35)] where j < geometry.centers.count {
            let ring = SKShapeNode(rectOf: CGSize(width: geometry.jarSize.width + 10, height: geometry.jarSize.height + 10),
                                   cornerRadius: geometry.jarSize.width * 0.35)
            ring.strokeColor = UIColor(hex: 0xFFD86B)
            ring.lineWidth = 5
            ring.fillColor = .clear
            ring.position = geometry.centers[j]
            ring.zPosition = 25
            ring.name = "hint"
            ring.alpha = 0
            addChild(ring)
            let pulse = SKAction.repeatForever(.sequence([.fadeIn(withDuration: 0.35), .fadeAlpha(to: 0.3, duration: 0.35)]))
            ring.run(.sequence([.wait(forDuration: delay), pulse]))
        }
    }

    private func clearHint() {
        enumerateChildNodes(withName: "hint") { node, _ in node.removeFromParent() }
    }
}
