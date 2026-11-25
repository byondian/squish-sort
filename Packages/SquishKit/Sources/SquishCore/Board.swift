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
/// - Bubble Bath boards (`floats`): a piece with `frozen` above zero is a floater, a squishy in a
///   bubble. It floats on top of its jar. It cannot be picked up and nothing can be poured into its
///   jar, but the squishies under it can be taken out. It pops when the piece right under it is its
///   own kind, or when nothing is left under it. A golden bubble (`frozen` 2) may ride once to any
///   other jar with room (`Move.ride`); it lands on top and is an ordinary floater from then on.
/// - A spin jar (Space Station) sits in a zero gravity ring. Tapping the ring turns the jar upside
///   down, so its squishies are in the opposite order (`Move.spin`). It is a move of its own. A
///   finished or shut jar does not spin, nor does one holding a duet, and a spin that would change
///   nothing is no move.
/// - A key jar (Keep Squishing) has a padlock showing a kind. Nothing goes in or comes out until a
///   jar of that kind is finished anywhere; then the padlock opens for good.
/// - A morph piece (Keep Squishing) shows two kinds and counts as the one in front. Each time it is
///   itself poured it flips to its other kind as it lands.
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
    /// Each jar's padlock, one entry per jar: 0 for none, else the key kind + 1.
    public private(set) var keys: [UInt8]
    /// Space Station: one entry per jar, true for a jar that can be turned upside down.
    public private(set) var spins: [Bool]
    /// Bubble Bath: frozen pieces are floaters, not ice.
    public let floats: Bool

    /// `keys` maps a jar to the kind its padlock shows. `spins` lists the spin jars.
    public init(capacity: Int, jars: [[Piece]], curtains: [Int] = [], vines: [Int: Int] = [:], floats: Bool = false,
                keys: [Int: Int] = [:], spins: [Int] = []) {
        var rings = [Bool](repeating: false, count: jars.count)
        for j in spins where jars.indices.contains(j) { rings[j] = true }
        self.spins = rings
        self.capacity = capacity
        self.jars = jars
        self.floats = floats
        self.layoutJarCount = jars.count
        self.curtains = Set(curtains).filter { jars.indices.contains($0) }.sorted()
        var tags = [UInt8](repeating: 0, count: jars.count)
        for (j, n) in vines where jars.indices.contains(j) && n > 0 { tags[j] = UInt8(clamping: n) }
        self.vines = tags
        var locks = [UInt8](repeating: 0, count: jars.count)
        for (j, kind) in keys where jars.indices.contains(j) && kind >= 0 { locks[j] = UInt8(clamping: kind + 1) }
        self.keys = locks
        for j in self.jars.indices {
            settleFloaters(j)
            revealTop(j)
            if isComplete(j) { settle(j) }
        }
    }

    /// How many pieces of jar `j` are under its floaters (all of them on a board without floaters).
    public func base(_ j: Int) -> Int {
        var n = jars[j].count
        if floats { while n > 0 && jars[j][n - 1].isFrozen { n -= 1 } }
        return n
    }

    /// Jar `j` has a floater on top: nothing can be poured in.
    public func isSealed(_ j: Int) -> Bool { floats && base(j) < jars[j].count }

    /// The top piece of jar `from` is a golden bubble and can ride to jar `to`.
    public func canRide(from f: Int, to t: Int) -> Bool {
        guard floats, f != t, jars.indices.contains(f), jars.indices.contains(t) else { return false }
        guard let top = jars[f].last, top.frozen == 2, !isShut(f), !isShut(t), !isComplete(t) else { return false }
        return jars[t].count < capacity
    }

    /// Jars whose top piece is a golden bubble that still has somewhere to go.
    public var rideJars: [Int] {
        guard floats else { return [] }
        return jars.indices.filter { f in jars.indices.contains { canRide(from: f, to: $0) } }
    }

    public var jarCount: Int { jars.count }

    public func isCurtained(_ j: Int) -> Bool { curtains.contains(j) }

    /// The number left on jar `j`'s vine tag; 0 when it has no vine or the vine has snapped.
    public func vineTag(_ j: Int) -> Int { vines.indices.contains(j) ? Int(vines[j]) : 0 }
    public var hasVines: Bool { vines.contains { $0 > 0 } }
    /// The kind on jar `j`'s padlock; nil when it has none or it has opened.
    public func keyKind(_ j: Int) -> UInt8? { keys.indices.contains(j) && keys[j] > 0 ? keys[j] - 1 : nil }
    public var hasKeys: Bool { keys.contains { $0 > 0 } }
    public var hasMorphs: Bool { jars.contains { $0.contains { $0.isMorph } } }
    /// Jar `j` sits in a zero gravity ring.
    public func isSpinJar(_ j: Int) -> Bool { spins.indices.contains(j) && spins[j] }
    public var hasSpins: Bool { spins.contains(true) }
    /// The spin jars, in order.
    public var spinJars: [Int] { spins.indices.filter { spins[$0] } }

    /// Jar `j` as it would stand upside down. Its new top squishy is never wrapped.
    private func spun(_ j: Int) -> [Piece] {
        var jar = Array(jars[j].reversed())
        if !jar.isEmpty { jar[jar.count - 1].hidden = false }
        return jar
    }

    /// Jar `j` can be turned upside down now, and turning it changes something.
    public func canSpin(_ j: Int) -> Bool {
        guard isSpinJar(j), !floats, !isComplete(j), !isShut(j) else { return false }
        let jar = jars[j]
        guard jar.count >= 2, !jar.contains(where: \.bondedAbove) else { return false }
        return spun(j) != jar
    }
    /// Behind a curtain, tied by a vine or padlocked: nothing goes in or comes out.
    public func isShut(_ j: Int) -> Bool { isCurtained(j) || vineTag(j) > 0 || keyKind(j) != nil }

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
        let jar = Array(jars[j].prefix(base(j)))
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
        guard n > 0, !isComplete(t), !isShut(t), !isSealed(t) else { return 0 }
        let dest = jars[t]
        let room = capacity - dest.count
        guard room > 0 else { return 0 }
        let src = Array(jars[f].prefix(base(f)))
        if Board.duetOnTop(src) {
            // A duet needs two spaces, and lands in an empty jar or on a squishy of its bottom member's kind.
            let low = src[src.count - 2]
            if room < 2 { return 0 }
            if let destTop = dest.last, destTop.kind != low.kind { return 0 }
            return 2
        }
        if let destTop = dest.last, let srcTop = src.last, destTop.kind != srcTop.kind { return 0 }
        var k = Swift.min(n, room)
        while k > 0 && Board.splitsDuet(src, movingTop: k) { k -= 1 }
        return k
    }

    public func isLegal(_ move: Move) -> Bool {
        if move.isSpin { return canSpin(move.from) }
        if let t = move.rideTarget { return canRide(from: move.from, to: t) }
        return piecesToMove(move) > 0
    }

    public var legalMoves: [Move] {
        var out: [Move] = []
        for f in jars.indices where runLength(at: f) > 0 {
            for t in jars.indices {
                let m = Move(from: f, to: t)
                if piecesToMove(m) > 0 { out.append(m) }
            }
        }
        if floats {
            for f in jars.indices where jars[f].last?.frozen == 2 {
                for t in jars.indices where canRide(from: f, to: t) { out.append(Move.ride(from: f, to: t)) }
            }
        }
        for j in spins.indices where spins[j] && canSpin(j) { out.append(Move.spin(j)) }
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
        // (Morph pieces change the counts as they flip, so a board with one is judged as it stands.)
        guard hasMorphs || counts.values.allSatisfy({ $0 % capacity == 0 }) else { return false }
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
        if move.isSpin {
            // The jar turns upside down. Nothing leaves or lands, so no ice thaws next door.
            let j = move.from
            guard jars.indices.contains(j), canSpin(j) else { return nil }
            let revealed = jars[j][0].hidden
            jars[j] = spun(j)
            return MoveResult(move: move, count: jars[j].count, revealedSourceTop: revealed,
                              completedJar: nil, thawedJars: [])
        }
        if let t = move.rideTarget { return applyRide(from: move.from, to: t) }
        let k = piecesToMove(move)
        guard k > 0 else { return nil }
        let (f, t) = (move.from, move.to)
        // The squishies leave from under any floaters, which sink down with them.
        let low = base(f)
        var moved = Array(jars[f][(low - k)..<low])
        // A duet that lands on its bottom member's kind lets go: the two become ordinary pieces.
        let letGo = k == 2 && moved[0].bondedAbove && !jars[t].isEmpty
        if letGo { moved[0].bondedAbove = false }
        // A morph piece that is poured flips to its other kind as it lands.
        var flipped: [Int] = []
        for i in moved.indices {
            if moved[i].flip() { flipped.append(jars[t].count + i) }
        }
        jars[f].removeSubrange((low - k)..<low)
        jars[t].append(contentsOf: moved)
        let revealed = revealTop(f)
        let popped = settleFloaters(f)

        // Thaw: every move that leaves or lands on a jar next to a frozen
        // piece counts once for that piece. Floaters are not ice: nothing next door changes them.
        var touched = Set<Int>()
        for j in [f, t] where j < layoutJarCount && !floats {
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
        var opened: [Int] = []
        if completed {
            (snapped, opened) = finished(t)
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
                          raisedCurtains: raised, snappedVines: snapped, poppedJars: popped ? [f] : [],
                          openedLocks: opened, flipped: flipped)
    }

    /// Jar `t` has just been finished: it settles, every vine tag drops by one (at zero the vine
    /// snaps) and every padlock that shows its kind opens.
    private mutating func finished(_ t: Int) -> (snapped: [Int], opened: [Int]) {
        settle(t)
        var snapped: [Int] = []
        for j in vines.indices where vines[j] > 0 {
            vines[j] -= 1
            if vines[j] == 0 {
                revealTop(j)
                snapped.append(j)
            }
        }
        var opened: [Int] = []
        if let kind = jars[t].first?.kind {
            for j in keys.indices where keys[j] == kind + 1 {
                keys[j] = 0
                revealTop(j)
                opened.append(j)
            }
        }
        return (snapped, opened)
    }

    /// A golden bubble rides from the top of jar `f` to the top of jar `t`.
    private mutating func applyRide(from f: Int, to t: Int) -> MoveResult? {
        guard canRide(from: f, to: t) else { return nil }
        var rider = jars[f].removeLast()
        rider.frozen = 1
        jars[t].append(rider)
        let popped = settleFloaters(t)
        var snapped: [Int] = []
        var opened: [Int] = []
        let completed = isComplete(t)
        if completed { (snapped, opened) = finished(t) }
        return MoveResult(move: Move.ride(from: f, to: t), count: 1, revealedSourceTop: false,
                          completedJar: completed ? t : nil, thawedJars: [], snappedVines: snapped,
                          poppedJars: popped ? [t] : [], openedLocks: opened)
    }

    /// Adds one empty jar (softening after fails). The rows shift to make room, so "next door"
    /// would no longer mean what it did: any curtain still closed goes up with it.
    public mutating func addEmptyJar() {
        jars.append([])
        vines.append(0)
        keys.append(0)
        spins.append(false)
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

    /// The top squishy of a jar (the one under any floaters) is never wrapped.
    @discardableResult
    private mutating func revealTop(_ j: Int) -> Bool {
        let last = base(j) - 1
        guard last >= 0, jars[j][last].hidden else { return false }
        jars[j][last].hidden = false
        return true
    }

    /// Pops every floater in jar `j` that sits on its own kind or on nothing, from the lowest up.
    /// True if any popped.
    @discardableResult
    private mutating func settleFloaters(_ j: Int) -> Bool {
        guard floats else { return false }
        var popped = false
        for i in jars[j].indices where jars[j][i].isFrozen && (i == 0 || jars[j][i - 1].kind == jars[j][i].kind) {
            jars[j][i].frozen = 0
            popped = true
        }
        return popped
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
    /// are, each jar keeps the number of pieces it had, and wrappers, ice, bubbles and duets fall away.
    /// A morph piece stays a morph piece, showing the kind it showed.
    /// A jar behind a closed curtain, tied by a vine or padlocked is left alone. The caller checks the result can still be solved.
    func shakenUp<R: RandomNumberGenerator>(using rng: inout R) -> Board {
        var next = jars
        let open = next.indices.filter { !isComplete($0) && !isShut($0) }
        var pool: [Piece] = []
        for j in open { for piece in next[j] { pool.append(Piece(kind: piece.kind, morph: piece.morph)) } }
        pool.shuffle(using: &rng)
        for j in open {
            let n = next[j].count
            next[j] = Array(pool.prefix(n))
            pool.removeFirst(n)
        }
        var tags: [Int: Int] = [:]
        for j in vines.indices where vines[j] > 0 { tags[j] = Int(vines[j]) }
        var locks: [Int: Int] = [:]
        for j in keys.indices where keys[j] > 0 { locks[j] = Int(keys[j]) - 1 }
        return Board(capacity: capacity, jars: next, curtains: curtains, vines: tags, floats: floats, keys: locks,
                     spins: spinJars)
    }
}
