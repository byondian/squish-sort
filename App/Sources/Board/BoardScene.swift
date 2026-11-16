import SpriteKit
import UIKit
import SquishCore

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
        guard size.width > 0 else { return }
        geometry = computeGeometry()
        jarNodes = []
        pieces = []
        for j in 0..<board.jarCount {
            let jar = JarNode(size: geometry.jarSize)
            jar.position = geometry.centers[j]
            addChild(jar)
            jarNodes.append(jar)
            var nodes: [PieceNode] = []
            for (i, piece) in board.jars[j].enumerated() {
                let node = PieceNode(kindID: kinds[Int(piece.kind)], diameter: geometry.piece * 0.86)
                node.position = slot(j, i)
                node.zPosition = 5
                node.apply(piece)
                addChild(node)
                nodes.append(node)
            }
            pieces.append(nodes)
            if board.isComplete(j) { jar.putLid(animated: false) }
        }
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
        guard j < board.jarCount else { return }
        clearHint()
        tap(j)
    }

    // MARK: - Motion

    /// Stretch up to 115% tall and 90% wide, rise above the jar, hang with a wobble.
    private func lift(_ j: Int) {
        lifted = j
        jarNodes[j].setHighlighted(true)
        let n = board.runLength(at: j)
        for (k, node) in pieces[j].suffix(n).enumerated() {
            node.removeAction(forKey: "wobble")
            node.zPosition = 10
            let rise = SKAction.group([
                .move(to: liftPoint(j, k), duration: 0.12),
                .sequence([.scaleX(to: 0.9, y: 1.15, duration: 0.08), .scaleX(to: 1, y: 1, duration: 0.1)]),
            ])
            rise.timingMode = .easeOut
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
            node.run(.sequence([.move(to: slot(j, i), duration: 0.12), squash()]))
        }
    }

    private func shake(_ j: Int) {
        let jar = jarNodes[j]
        let x = geometry.centers[j].x
        jar.run(.sequence([
            .moveTo(x: x - 6, duration: 0.05), .moveTo(x: x + 6, duration: 0.07),
            .moveTo(x: x - 3, duration: 0.05), .moveTo(x: x, duration: 0.05),
        ]))
    }

    /// Squash to 80% tall and 120% wide, then spring back with two overshoots.
    private func squash() -> SKAction {
        .sequence([
            .scaleX(to: 1.2, y: 0.8, duration: 0.06),
            .scaleX(to: 0.92, y: 1.08, duration: 0.08),
            .scaleX(to: 1.04, y: 0.97, duration: 0.06),
            .scaleX(to: 1, y: 1, duration: 0.05),
        ])
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
            node.run(.move(to: slot(from, i), duration: 0.12))
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
            let stretch = SKAction.sequence([.scaleX(to: 1.1, y: 0.92, duration: hop / 2), .scaleX(to: 1, y: 1, duration: hop / 2)])
            node.run(.sequence([
                .wait(forDuration: stagger * Double(i)),
                .group([arc, spin, stretch]),
                squash(),
                .run { node.zPosition = 5 },
            ]))
        }
        pieces[to].append(contentsOf: moving)
        run(.sequence([
            .wait(forDuration: hop + spread),
            .run { [weak self] in self?.onLand?(result) },
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
            jarNodes[done].putLid(animated: true)
            sparkle(at: geometry.centers[done])
            for node in pieces[done] {
                node.run(.sequence([.scaleX(to: 1.15, y: 0.75, duration: 0.15), .scaleX(to: 1, y: 1, duration: 0.25)]))
            }
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

    /// Every jar bounces in turn, left to right.
    func celebrate() {
        for (j, jar) in jarNodes.enumerated() {
            let lift = geometry.piece * 0.5
            let wait = SKAction.wait(forDuration: 0.08 * Double(j))
            let bounce = SKAction.sequence([.moveBy(x: 0, y: lift, duration: 0.15), .moveBy(x: 0, y: -lift, duration: 0.15)])
            jar.run(.sequence([wait, bounce]))
            for node in pieces[j] { node.run(.sequence([wait, bounce])) }
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
