/// The jars and the move rule. Pure value type, deterministic.
///
/// Rules (game design doc, 16 Nov 2026):
/// - A jar holds up to `capacity` pieces, listed bottom to top.
/// - A move takes the top piece and every same-kind piece directly under it
///   (the conga line) onto an empty jar or a jar whose top is the same kind,
///   as far as there is room.
/// - The conga line stops at a hidden or frozen piece, and never splits a duet.
/// - A full jar of one kind is complete: lidded and locked.
/// - Win when every jar is empty or complete.
public struct Board: Hashable, Sendable {
    public let capacity: Int
    public private(set) var jars: [[Piece]]
    /// Jar count the level started with. Adjacency for frozen pieces uses this,
    /// so an extra jar added mid-level never changes who thaws whom.
    public let layoutJarCount: Int

    public init(capacity: Int, jars: [[Piece]]) {
        self.capacity = capacity
        self.jars = jars
        self.layoutJarCount = jars.count
        for j in self.jars.indices {
            revealTop(j)
            if isComplete(j) { settle(j) }
        }
    }

    public var jarCount: Int { jars.count }

    public func isComplete(_ j: Int) -> Bool {
        let jar = jars[j]
        guard jar.count == capacity, let kind = jar.first?.kind else { return false }
        return jar.allSatisfy { $0.kind == kind }
    }

    public var isWon: Bool {
        jars.indices.allSatisfy { jars[$0].isEmpty || isComplete($0) }
    }

    /// Pieces that would leave jar `j` if there were unlimited room.
    public func runLength(at j: Int) -> Int {
        let jar = jars[j]
        guard let top = jar.last, !isComplete(j), !top.hidden, !top.isFrozen else { return 0 }
        if Board.duetOnTop(jar) {
            // A duet on top moves as a pair, and only as a pair.
            let low = jar[jar.count - 2]
            return low.hidden || low.isFrozen ? 0 : 2
        }
        var n = 1
        var i = jar.count - 2
        while i >= 0 {
            let p = jar[i]
            if p.kind != top.kind || p.hidden || p.isFrozen { break }
            n += 1
            i -= 1
        }
        while n > 0 && Board.splitsDuet(jar, movingTop: n) { n -= 1 }
        return n
    }

    /// Number of pieces `move` would carry; 0 means the move is illegal.
    public func piecesToMove(_ move: Move) -> Int {
        let (f, t) = (move.from, move.to)
        guard f != t, jars.indices.contains(f), jars.indices.contains(t) else { return 0 }
        let n = runLength(at: f)
        guard n > 0, !isComplete(t) else { return 0 }
        let dest = jars[t]
        let room = capacity - dest.count
        guard room > 0 else { return 0 }
        if Board.duetOnTop(jars[f]) {
            // A duet needs two spaces, and lands in an empty jar or on a squishy of its bottom member's kind.
            let low = jars[f][jars[f].count - 2]
            if room < 2 { return 0 }
            if let destTop = dest.last, destTop.kind != low.kind { return 0 }
            return 2
        }
        if let destTop = dest.last, let srcTop = jars[f].last, destTop.kind != srcTop.kind { return 0 }
        var k = Swift.min(n, room)
        while k > 0 && Board.splitsDuet(jars[f], movingTop: k) { k -= 1 }
        return k
    }

    public func isLegal(_ move: Move) -> Bool { piecesToMove(move) > 0 }

    public var legalMoves: [Move] {
        var out: [Move] = []
        for f in jars.indices where runLength(at: f) > 0 {
            for t in jars.indices {
                let m = Move(from: f, to: t)
                if piecesToMove(m) > 0 { out.append(m) }
            }
        }
        return out
    }

    /// No legal move left and not won: the board sighs and the fail screen shows.
    public var isStuck: Bool { !isWon && legalMoves.isEmpty }

    @discardableResult
    public mutating func apply(_ move: Move) -> MoveResult? {
        let k = piecesToMove(move)
        guard k > 0 else { return nil }
        let (f, t) = (move.from, move.to)
        var moved = Array(jars[f].suffix(k))
        // A duet that lands on its bottom member's kind lets go: the two become ordinary pieces.
        let letGo = k == 2 && moved[0].bondedAbove && !jars[t].isEmpty
        if letGo { moved[0].bondedAbove = false }
        jars[f].removeLast(k)
        jars[t].append(contentsOf: moved)
        let revealed = revealTop(f)

        // Thaw: every move that leaves or lands on a jar next to a frozen
        // piece counts once for that piece.
        var touched = Set<Int>()
        for j in [f, t] where j < layoutJarCount {
            for nb in BoardLayout.neighbours(of: j, jarCount: layoutJarCount) { touched.insert(nb) }
        }
        var thawed: [Int] = []
        for j in touched.sorted() {
            var hadFrozen = false
            for i in jars[j].indices where jars[j][i].frozen > 0 {
                hadFrozen = true
                jars[j][i].frozen -= 1
            }
            if hadFrozen && !jars[j].contains(where: { $0.isFrozen }) { thawed.append(j) }
        }

        let completed = isComplete(t)
        if completed { settle(t) }
        return MoveResult(move: move, count: k, revealedSourceTop: revealed,
                          completedJar: completed ? t : nil, thawedJars: thawed, duetLetGo: letGo)
    }

    /// Adds one empty jar (the Extra jar helper, or softening after fails).
    public mutating func addEmptyJar() {
        jars.append([])
    }

    // MARK: - Helpers

    /// The top two pieces of the jar are a duet: two different squishies holding hands.
    static func duetOnTop(_ jar: [Piece]) -> Bool {
        jar.count >= 2 && jar[jar.count - 2].bondedAbove
    }

    /// True if moving the top `k` pieces would leave half of a duet behind.
    static func splitsDuet(_ jar: [Piece], movingTop k: Int) -> Bool {
        let lowest = jar.count - k
        guard lowest > 0, lowest <= jar.count else { return false }
        return jar[lowest - 1].bondedAbove
    }

    @discardableResult
    private mutating func revealTop(_ j: Int) -> Bool {
        guard let last = jars[j].indices.last, jars[j][last].hidden else { return false }
        jars[j][last].hidden = false
        return true
    }

    /// A complete jar shows everything and nothing in it stays frozen.
    private mutating func settle(_ j: Int) {
        for i in jars[j].indices {
            jars[j][i].hidden = false
            jars[j][i].frozen = 0
        }
    }
}

public extension Board {
    /// Shake-up: every piece in an unfinished jar lands in a new spot. Finished jars stay as they
    /// are, each jar keeps the number of pieces it had, and wrappers, ice and duets fall away.
    /// The caller checks the result can still be solved.
    func shakenUp<R: RandomNumberGenerator>(using rng: inout R) -> Board {
        var next = jars
        let open = next.indices.filter { !isComplete($0) }
        var pool: [Piece] = []
        for j in open { for piece in next[j] { pool.append(Piece(kind: piece.kind)) } }
        pool.shuffle(using: &rng)
        for j in open {
            let n = next[j].count
            next[j] = Array(pool.prefix(n))
            pool.removeFirst(n)
        }
        return Board(capacity: capacity, jars: next)
    }
}
