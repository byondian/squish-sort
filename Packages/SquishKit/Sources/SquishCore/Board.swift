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
/// - A curtain jar (Starlight Stage) is closed: nothing goes in or comes out until a jar next to
///   it is finished. Then the curtain goes up for good and it is an ordinary jar.
/// - A vine jar (Jungle Jam) is tied shut with a tag showing a number. Nothing goes in or comes
///   out. Every jar finished anywhere lowers each tag by one; at zero the vine snaps and it is an
///   ordinary jar. A shut jar is not a finished jar.
public struct Board: Hashable, Sendable {
    public let capacity: Int
    public private(set) var jars: [[Piece]]
    /// Jar count the level started with. Adjacency for frozen pieces uses this,
    /// so an extra jar added mid-level never changes who thaws whom.
    public let layoutJarCount: Int
    /// Jars still behind a closed curtain, in order.
    public private(set) var curtains: [Int]
    /// The number on each jar's vine tag, one entry per jar; 0 means no vine.
    public private(set) var vines: [UInt8]

    public init(capacity: Int, jars: [[Piece]], curtains: [Int] = [], vines: [Int: Int] = [:]) {
        self.capacity = capacity
        self.jars = jars
        self.layoutJarCount = jars.count
        self.curtains = Set(curtains).filter { jars.indices.contains($0) }.sorted()
        var tags = [UInt8](repeating: 0, count: jars.count)
        for (j, n) in vines where jars.indices.contains(j) && n > 0 { tags[j] = UInt8(clamping: n) }
        self.vines = tags
        for j in self.jars.indices {
            revealTop(j)
            if isComplete(j) { settle(j) }
        }
    }

    public var jarCount: Int { jars.count }

    public func isCurtained(_ j: Int) -> Bool { curtains.contains(j) }

    /// The number left on jar `j`'s vine tag; 0 when it has no vine or the vine has snapped.
    public func vineTag(_ j: Int) -> Int { vines.indices.contains(j) ? Int(vines[j]) : 0 }
    public var hasVines: Bool { vines.contains { $0 > 0 } }
    /// Behind a curtain or tied by a vine: nothing goes in or comes out.
    public func isShut(_ j: Int) -> Bool { isCurtained(j) || vineTag(j) > 0 }

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
        guard let top = jar.last, !isComplete(j), !top.hidden, !top.isFrozen, !isShut(j) else { return 0 }
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
        guard n > 0, !isComplete(t), !isShut(t) else { return 0 }
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

    /// Moves are left, but none of them leads anywhere: every path from here runs out (or only goes
    /// round in circles) without a win. Only looked for when few moves are open, and only as far as
    /// `budget` positions; past that the board is taken to be alive.
    public func isDeadEnd(maxOpenMoves: Int = 4, budget: Int = 300) -> Bool {
        if isWon { return false }
        let open = legalMoves
        guard !open.isEmpty, open.count <= maxOpenMoves else { return false }
        // Only real level boards are judged: every kind there fills whole jars.
        var counts: [UInt8: Int] = [:]
        for jar in jars { for piece in jar { counts[piece.kind, default: 0] += 1 } }
        guard counts.values.allSatisfy({ $0 % capacity == 0 }) else { return false }
        var seen: Set<Board> = [self]
        var queue = [self]
        var at = 0
        while at < queue.count {
            let board = queue[at]
            at += 1
            for move in board.legalMoves {
                var next = board
                guard next.apply(move) != nil else { continue }
                if next.isWon { return false }
                if seen.insert(next).inserted {
                    if seen.count > budget { return false }
                    queue.append(next)
                }
            }
        }
        return true
    }

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
        var raised: [Int] = []
        var snapped: [Int] = []
        if completed {
            settle(t)
            // Every finished jar lowers each vine tag by one; at zero the vine snaps.
            for j in vines.indices where vines[j] > 0 {
                vines[j] -= 1
                if vines[j] == 0 {
                    revealTop(j)
                    snapped.append(j)
                }
            }
            // A finished jar raises the curtain on the jars next to it.
            if t < layoutJarCount {
                for nb in BoardLayout.neighbours(of: t, jarCount: layoutJarCount) where isCurtained(nb) {
                    curtains.removeAll { $0 == nb }
                    revealTop(nb)
                    raised.append(nb)
                }
            }
        }
        return MoveResult(move: move, count: k, revealedSourceTop: revealed,
                          completedJar: completed ? t : nil, thawedJars: thawed, duetLetGo: letGo,
                          raisedCurtains: raised, snappedVines: snapped)
    }

    /// Adds one empty jar (softening after fails). The rows shift to make room, so "next door"
    /// would no longer mean what it did: any curtain still closed goes up with it.
    public mutating func addEmptyJar() {
        jars.append([])
        vines.append(0)
        for j in curtains { revealTop(j) }
        curtains = []
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
    /// A jar behind a closed curtain or tied by a vine is left alone. The caller checks the result can still be solved.
    func shakenUp<R: RandomNumberGenerator>(using rng: inout R) -> Board {
        var next = jars
        let open = next.indices.filter { !isComplete($0) && !isShut($0) }
        var pool: [Piece] = []
        for j in open { for piece in next[j] { pool.append(Piece(kind: piece.kind)) } }
        pool.shuffle(using: &rng)
        for j in open {
            let n = next[j].count
            next[j] = Array(pool.prefix(n))
            pool.removeFirst(n)
        }
        var tags: [Int: Int] = [:]
        for j in vines.indices where vines[j] > 0 { tags[j] = Int(vines[j]) }
        return Board(capacity: capacity, jars: next, curtains: curtains, vines: tags)
    }
}
