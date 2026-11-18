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
    /// Boss levels: gold rims on the jars.
    var goldRims = false
    /// On a dark background the jars glow instead of having a plum outline.
    var darkBackground = false { didSet { if oldValue != darkBackground, size.width > 0, view != nil { rebuild() } } }
    /// The lid twists shut (a click and a tick).
    var onLidTwist: (() -> Void)?
    /// A finished jar's squishies do their signature move: the effect's name and its sound, if it has one.
    var onSignature: ((String, String?) -> Void)?
    /// A curtain is about to go up (the drumroll), and then goes up (the swish and the sting).
    var onCurtainDrum: (() -> Void)?
    var onCurtainUp: (() -> Void)?
    private var curtainNodes: [Int: CurtainNode] = [:]
    /// A vine has snapped (Jungle Jam): the jar it tied is open.
    var onVineSnap: (() -> Void)?
    private var vineNodes: [Int: VineNode] = [:]
    /// Starlight Stage: lamps along the top and a little crowd along the bottom.
    private var stage: StageShowNode?

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

    /// Replace the board without animation (undo, retry, extra jar). With `dropIn` the squishies
    /// of unfinished jars fall into their new places (shake-up).
    func reload(_ board: Board, dropIn: Bool = false) {
        removeAllActions()
        self.board = board
        lifted = nil
        busy = false
        rebuild()
        guard dropIn else { return }
        let calm = UIAccessibility.isReduceMotionEnabled
        for j in pieces.indices where !board.isComplete(j) {
            for (i, node) in pieces[j].enumerated() {
                let home = slot(j, i)
                node.alpha = 0
                if calm {
                    node.run(.fadeIn(withDuration: 0.3))
                    continue
                }
                node.position = CGPoint(x: home.x, y: home.y + geometry.piece * 1.6)
                let fall = SKAction.move(to: home, duration: 0.22)
                fall.timingMode = .easeIn
                node.run(.sequence([
                    .wait(forDuration: 0.03 * Double(j) + 0.04 * Double(i)),
                    .group([.fadeIn(withDuration: 0.1), fall]),
                    .run { [weak node] in node?.land(speed: 6) },
                ]), withKey: "travel")
            }
        }
    }

    /// Puts down anything held, without a move.
    func clearSelection() {
        if let l = lifted { putBack(l) }
        clearHint()
    }

    /// Shake-up is coming: every jar trembles and the squishies shake their heads.
    func tremble(seconds: Double) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        busy = true
        let steps = max(2, Int(seconds / 0.08))
        for (j, jar) in jarNodes.enumerated() where j < geometry.centers.count {
            let x = geometry.centers[j].x
            var moves: [SKAction] = []
            for s in 0..<steps {
                let reach = 1.5 + 3.5 * CGFloat(s) / CGFloat(steps)
                moves.append(.moveTo(x: x + (s % 2 == 0 ? reach : -reach), duration: 0.04))
            }
            moves.append(.moveTo(x: x, duration: 0.04))
            jar.run(.sequence(moves))
        }
        for node in pieces.joined() { node.shakeHead() }
        run(.sequence([.wait(forDuration: seconds), .run { [weak self] in self?.busy = false }]))
    }

    // MARK: - Squish Fever

    private(set) var feverOn = false

    /// A warm glow behind the jars that breathes slowly, with sparkles drifting up.
    /// Glow and shimmer only: nothing flashes.
    func setFever(_ on: Bool) {
        feverOn = on
        childNode(withName: "fever")?.removeFromParent()
        guard on, size.width > 0 else { return }
        let glow = SKSpriteNode(color: UIColor(hex: 0xFFD86B), size: size)
        glow.name = "fever"
        glow.position = CGPoint(x: size.width / 2, y: size.height / 2)
        glow.zPosition = -5
        glow.alpha = 0.16
        addChild(glow)
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.26, duration: 1.0), .fadeAlpha(to: 0.12, duration: 1.0)])))
        let w = size.width, h = size.height
        glow.run(.repeatForever(.sequence([.wait(forDuration: 0.22), .run { [weak glow] in
            guard let glow else { return }
            let spark = SKLabelNode(text: "✦")
            spark.fontSize = CGFloat.random(in: 12...22)
            spark.fontColor = .white
            spark.position = CGPoint(x: CGFloat.random(in: -w / 2...w / 2), y: CGFloat.random(in: -h / 2...h / 4))
            spark.alpha = 0
            glow.addChild(spark)
            spark.run(.sequence([
                .group([.fadeAlpha(to: 0.9, duration: 0.3), .moveBy(x: 0, y: 40, duration: 0.9)]),
                .fadeOut(withDuration: 0.3), .removeFromParent(),
            ]))
        }])))
    }

    // MARK: - Layout

    private func computeGeometry() -> Geometry {
        let rows = BoardLayout.rows(jarCount: board.jarCount)
        let perRow = CGFloat(max(rows.map(\.count).max() ?? 1, 3))
        let margin: CGFloat = 14
        let gap: CGFloat = size.width >= 700 ? 22 : 10
        let cap = CGFloat(board.capacity)
        let maxJarWidth = (size.width - 2 * margin - gap * (perRow - 1)) / perRow
        let rowUnits = cap + 1.7 // jar plus room to lift above it
        let byHeight = (size.height - 2 * margin) / (CGFloat(rows.count) * rowUnits)
        // An iPad has room for bigger squishies and wider gaps.
        let piece = max(16, min(maxJarWidth / 1.25, byHeight, size.width >= 700 ? 104 : 70))
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
            let jar = JarNode(size: geometry.jarSize, world: world, dark: darkBackground, gold: goldRims)
            jar.position = geometry.centers[j]
            addChild(jar)
            jarNodes.append(jar)
            var nodes: [PieceNode] = []
            for (i, piece) in board.jars[j].enumerated() {
                let node = PieceNode(kindID: kinds[Int(piece.kind)], diameter: geometry.piece * 0.86)
                node.position = slot(j, i)
                node.zPosition = 5
                node.isLucky = piece.kind == luckyKind
                if world == "bubblebath" { node.useBubble() }
                node.apply(piece)
                addChild(node)
                nodes.append(node)
            }
            pieces.append(nodes)
            if board.isComplete(j) { jar.putLid(animated: false, tint: nodes.first.map { SquishyStyle.forID($0.kindID).color }) }
        }
        stage = nil
        if world == "starlight" {
            let show = StageShowNode(size: size, calm: UIAccessibility.isReduceMotionEnabled)
            show.zPosition = -4
            addChild(show)
            stage = show
            for j in 0..<board.jarCount where board.isComplete(j) {
                show.lightLamp(pieces[j].first.map { SquishyStyle.forID($0.kindID).color } ?? .white, animated: false)
            }
        }
        // Curtain Call jars: a velvet curtain hangs in front of the jar and everything in it.
        curtainNodes = [:]
        for j in board.curtains where j < geometry.centers.count {
            let size = CGSize(width: geometry.jarSize.width + 8, height: geometry.jarSize.height + geometry.piece * 0.35)
            let curtain = CurtainNode(size: size)
            curtain.position = CGPoint(x: geometry.centers[j].x, y: geometry.centers[j].y + size.height / 2 + 1)
            curtain.zPosition = 8
            addChild(curtain)
            curtainNodes[j] = curtain
        }
        // Vine jars: tied shut until the number on the tag has been counted down.
        vineNodes = [:]
        for j in 0..<board.jarCount where board.vineTag(j) > 0 && j < geometry.centers.count {
            let vine = VineNode(size: geometry.jarSize, tag: board.vineTag(j))
            vine.position = geometry.centers[j]
            vine.zPosition = 8
            addChild(vine)
            vineNodes[j] = vine
        }
        if feverOn { setFever(true) }
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

    /// A magic move: the scene lifts and lands `move` by itself, just as two taps would.
    /// False when the board is busy and nothing was started.
    @discardableResult
    func playForPlayer(_ move: Move) -> Bool {
        guard !busy, board.isLegal(move) else { return false }
        endTutorial()
        clearHint()
        if lifted == move.from {
            tap(move.to)
            return true
        }
        if let up = lifted { putBack(up) }
        lift(move.from)
        run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in
            // Only if nothing else happened in between.
            guard let self, !self.busy, self.lifted == move.from else { return }
            self.tap(move.to)
        }]))
        return true
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
        // What is drawn must be what the board holds. If they ever part (Ian, 18 Nov: a lid on a
        // jar that showed three squishies), everything is drawn again from the board at once.
        if !busy, size.width > 0, !matchesBoard { rebuild() }
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

    /// Every jar shows the board's own pieces in order, and a lid exactly when the jar is complete.
    private var matchesBoard: Bool {
        guard pieces.count == board.jarCount, jarNodes.count == board.jarCount else { return false }
        for j in 0..<board.jarCount {
            let jar = board.jars[j]
            guard pieces[j].count == jar.count, jarNodes[j].hasLid == board.isComplete(j) else { return false }
            for (i, piece) in jar.enumerated() where pieces[j][i].kindID != kinds[Int(piece.kind)] { return false }
        }
        return true
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
            // Picked up while still dropping in after a shuffle: it must not stay faded.
            node.alpha = 1
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
        curtainNodes[j]?.ripple()
        vineNodes[j]?.wobble()
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
            }, onTwist: { [weak self] in
                self?.onLidTwist?()
                self?.signatureMove(jar: done)
            })
            sparkle(at: geometry.centers[done])
            stage?.lightLamp(tint ?? .white, animated: !calm)
            stage?.cheer()
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
        for (n, j) in result.raisedCurtains.enumerated() { raiseCurtain(j, after: 0.7 + 0.25 * Double(n)) }
        for (j, vine) in vineNodes where !result.snappedVines.contains(j) { vine.set(newBoard.vineTag(j)) }
        for (n, j) in result.snappedVines.enumerated() { snapVine(j, after: 0.5 + 0.25 * Double(n)) }
        busy = false
        onMoveFinished?(result)
    }

    /// The tag has reached zero: the vine snaps and what was tied in bounces once.
    private func snapVine(_ j: Int, after delay: Double) {
        guard let vine = vineNodes.removeValue(forKey: j) else { return }
        let calm = UIAccessibility.isReduceMotionEnabled
        vine.set(0)
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self, weak vine] in
                guard let self else { return }
                self.onVineSnap?()
                vine?.snap(calm: calm)
                guard !calm, j < self.pieces.count else { return }
                for node in self.pieces[j] { node.squeezeAndRelease() }
            },
        ]))
    }

    /// The jar next door is finished: a drumroll, the curtain lifts, a spotlight lands on the jar
    /// and what was hidden bounces once.
    private func raiseCurtain(_ j: Int, after delay: Double) {
        guard let curtain = curtainNodes.removeValue(forKey: j) else { return }
        let calm = UIAccessibility.isReduceMotionEnabled
        run(.sequence([
            .wait(forDuration: delay),
            .run { [weak self, weak curtain] in
                self?.onCurtainDrum?()
                if !calm { curtain?.tremble(seconds: 0.6) }
            },
            .wait(forDuration: 0.6),
            .run { [weak self, weak curtain] in
                guard let self else { return }
                self.onCurtainUp?()
                curtain?.rise(calm: calm)
                guard j < self.geometry.centers.count, j < self.pieces.count else { return }
                let centre = self.geometry.centers[j]
                let light = SKShapeNode(ellipseOf: CGSize(width: self.geometry.jarSize.width * 1.5, height: self.geometry.jarSize.height * 1.25))
                light.fillColor = UIColor(red: 1, green: 0.96, blue: 0.75, alpha: 0.5)
                light.strokeColor = .clear
                light.position = centre
                light.zPosition = -2
                light.alpha = 0
                self.addChild(light)
                light.run(.sequence([.fadeIn(withDuration: 0.25), .wait(forDuration: 0.7), .fadeOut(withDuration: 0.6), .removeFromParent()]))
                guard !calm else { return }
                self.run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in
                    guard let self, j < self.pieces.count else { return }
                    for node in self.pieces[j] { node.squeezeAndRelease() }
                }]))
            },
        ]))
    }

    /// The finished jar's squishies do their own thing for a beat (benchmark: the best clip moment
    /// belongs inside the puzzle). Under a second, for show only, and it never holds up the next move.
    private func signatureMove(jar j: Int) {
        guard j < pieces.count, j < geometry.centers.count, let first = pieces[j].first,
              let spec = SignatureMoves.shared.moves(for: first.kindID).first else { return }
        onSignature?(spec.effect, spec.str("sound"))
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let nodes = pieces[j]
        let side: CGFloat = geometry.piece
        let centre = geometry.centers[j]
        let tint: UIColor = SquishyStyle.forID(first.kindID).color
        func each(_ make: (Int) -> SKAction) {
            for (i, node) in nodes.enumerated() where node.action(forKey: "signature") == nil {
                node.run(.sequence([.wait(forDuration: 0.04 * Double(i)), make(i)]), withKey: "signature")
            }
        }
        func eased(_ action: SKAction) -> SKAction {
            action.timingMode = .easeInEaseOut
            return action
        }
        switch spec.effect {
        case "BURST", "VORTEX":
            // Its own little things fly out of the jar, in its own colours.
            let colors: [UIColor] = spec.strings("colors").compactMap { css in
                guard css.hasPrefix("#"), let v = UInt32(css.dropFirst(), radix: 16) else { return nil }
                return UIColor(hex: v)
            }
            let palette: [UIColor] = colors.isEmpty ? [tint, .white] : colors
            let count = 14
            for i in 0..<count {
                let dot = SKShapeNode(circleOfRadius: side * (i % 2 == 0 ? 0.07 : 0.05))
                dot.fillColor = palette[i % palette.count]
                dot.strokeColor = UIColor(hex: 0x3B2A4A).withAlphaComponent(0.5)
                dot.lineWidth = 1
                dot.position = CGPoint(x: centre.x, y: centre.y + geometry.jarSize.height * 0.15)
                dot.zPosition = 32
                addChild(dot)
                let angle: CGFloat = CGFloat(i) / CGFloat(count) * .pi * 2
                let reach: CGFloat = side * (1.1 + CGFloat(i % 3) * 0.35)
                let out = SKAction.moveBy(x: cos(angle) * reach, y: sin(angle) * reach + side * 0.4, duration: 0.32)
                out.timingMode = .easeOut
                let fall = SKAction.moveBy(x: cos(angle) * side * 0.2, y: -side * 0.9, duration: 0.4)
                fall.timingMode = .easeIn
                let spin = SKAction.rotate(byAngle: spec.effect == "VORTEX" ? .pi * 2 : .pi, duration: 0.7)
                dot.run(.sequence([.group([.sequence([out, .group([fall, .fadeOut(withDuration: 0.4)])]), spin]), .removeFromParent()]))
            }
        case "GLOW":
            let glow = SKShapeNode(ellipseOf: CGSize(width: geometry.jarSize.width * 1.6, height: geometry.jarSize.height * 1.2))
            var color: UIColor = tint
            if let css = spec.str("color"), css.hasPrefix("#"), let v = UInt32(css.dropFirst(), radix: 16) { color = UIColor(hex: v) }
            glow.fillColor = color.withAlphaComponent(0.55)
            glow.strokeColor = .clear
            glow.position = centre
            glow.zPosition = -1
            glow.alpha = 0
            glow.setScale(0.6)
            addChild(glow)
            let swell = SKAction.group([.fadeIn(withDuration: 0.18), eased(.scale(to: 1.1, duration: 0.3))])
            glow.run(.sequence([swell, .wait(forDuration: 0.15), .group([.fadeOut(withDuration: 0.4), .scale(to: 1.3, duration: 0.4)]),
                                .removeFromParent()]))
        case "PUFF":
            each { _ in .sequence([eased(.scale(to: 1.22, duration: 0.16)), eased(.scale(to: 0.94, duration: 0.14)), eased(.scale(to: 1, duration: 0.14))]) }
        case "MELT":
            each { _ in
                .sequence([eased(.group([.scaleX(to: 1.28, duration: 0.22), .scaleY(to: 0.62, duration: 0.22)])),
                           .wait(forDuration: 0.12),
                           eased(.group([.scaleX(to: 1, duration: 0.28), .scaleY(to: 1, duration: 0.28)]))])
            }
        case "LIFT", "SPLIT":
            // A hop with a twirl, top squishy highest.
            each { i in
                let rise: CGFloat = side * (0.18 + 0.05 * CGFloat(i))
                let up = SKAction.moveBy(x: 0, y: rise, duration: 0.16)
                up.timingMode = .easeOut
                let down = SKAction.moveBy(x: 0, y: -rise, duration: 0.18)
                down.timingMode = .easeIn
                return .sequence([up, down])
            }
            if let top = nodes.last {
                top.run(.sequence([eased(.rotate(byAngle: .pi * 2, duration: 0.42)), .rotate(toAngle: 0, duration: 0)]), withKey: "twirl")
            }
        case "LIMB", "ROPE":
            // A wag from side to side.
            each { i in
                let lean: CGFloat = (i % 2 == 0 ? 1 : -1) * 0.22
                return .sequence([eased(.rotate(toAngle: lean, duration: 0.12)), eased(.rotate(toAngle: -lean, duration: 0.18)),
                                  eased(.rotate(toAngle: lean * 0.5, duration: 0.14)), eased(.rotate(toAngle: 0, duration: 0.12))])
            }
        default:
            // TRICK, SOUND and the rest: a quick shimmy in time with the sound.
            each { _ in
                let step: CGFloat = side * 0.07
                return .sequence([.moveBy(x: step, y: 0, duration: 0.05), .moveBy(x: -step * 2, y: 0, duration: 0.09),
                                  .moveBy(x: step * 2, y: 0, duration: 0.09), .moveBy(x: -step, y: 0, duration: 0.05)])
            }
        }
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
