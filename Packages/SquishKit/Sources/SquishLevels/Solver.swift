import SquishCore

/// Finds the shortest solution (par) with A*.
///
/// Heuristic: total same-kind runs across all jars minus the number of runs a
/// solved board has. A move can remove at most one run, so the heuristic never
/// overestimates and the first solution found is optimal.
/// (Bubble Bath boards need a little more care: see `heuristic`.)
///
/// Without frozen pieces jar order doesn't matter to solvability, so states are
/// compared with jars sorted, which shrinks the search a lot. While a curtain is closed, which
/// jar stands next to which matters again, so those positions are compared as they stand.
public enum Solver {
    public struct Result: Sendable {
        public let moves: [Move]
        public let statesExplored: Int
    }

    /// Returns nil if the board can't be solved within `maxStates` expansions.
    public static func solve(_ start: Board, maxStates: Int = 3_000_000) -> Result? {
        if case .solved(let result) = search(start, maxStates: maxStates, maxNodes: .max, weight: 1) { return result }
        return nil
    }

    enum Outcome {
        case solved(Result)
        /// Every reachable position was tried: there is no way to win from here.
        case unwinnable
        /// The search hit a limit before it found an answer either way.
        case gaveUp
    }

    /// `weight` 1 is plain A* (shortest solution). A larger weight leans on the
    /// heuristic: far fewer positions, a good solution, not always the shortest.
    /// `maxNodes` bounds how many positions are kept in memory.
    static func search(_ start: Board, maxStates: Int, maxNodes: Int, weight: Int) -> Outcome {
        // Floaters do not care which jar stands next to which, so those boards are compared sorted too.
        let canonical = start.floats || !start.jars.contains { jar in jar.contains { $0.isFrozen } }
        var counts: [UInt8: Int] = [:]
        for jar in start.jars { for p in jar { counts[p.kind, default: 0] += 1 } }
        var solvedRuns = counts.values.reduce(0) { $0 + ($1 + start.capacity - 1) / start.capacity }
        // Morph pieces change how many there are of each kind; a won board is still this many full jars.
        if start.hasMorphs { solvedRuns = counts.values.reduce(0, +) / start.capacity }

        var boards: [Board] = [start]
        var parents: [Int32] = [-1]
        var moves: [Move] = [Move(from: -1, to: -1)]
        var best: [[UInt8]: Int] = [key(start, canonical: canonical): 0]
        var heap = MinHeap()
        heap.push(.init(f: weight * heuristic(start, solvedRuns), g: 0, node: 0))
        var explored = 0

        while let entry = heap.pop() {
            let current = boards[entry.node]
            let free = canonical && current.curtains.isEmpty && !current.hasVines && !current.hasKeys
            if let known = best[key(current, canonical: canonical)], known < entry.g { continue }
            if current.isWon {
                var path: [Move] = []
                var i = entry.node
                while i > 0 {
                    path.append(moves[i])
                    i = Int(parents[i])
                }
                return .solved(Result(moves: path.reversed(), statesExplored: explored))
            }
            explored += 1
            if explored > maxStates || boards.count > maxNodes { return .gaveUp }
            for move in current.legalMoves {
                if free && !move.isRide && !move.isSpin && current.jars[move.to].isEmpty
                    && current.isSpinJar(move.from) == current.isSpinJar(move.to)
                    && current.runLength(at: move.from) == current.jars[move.from].count
                    && !current.jars[move.from].contains(where: \.isMorph) {
                    continue // pouring a whole jar into an empty one changes nothing (unless a morph piece flips on the way)
                }
                var next = current
                next.apply(move)
                let k = key(next, canonical: canonical)
                let g = entry.g + 1
                if let known = best[k], known <= g { continue }
                best[k] = g
                boards.append(next)
                parents.append(Int32(entry.node))
                moves.append(move)
                heap.push(.init(f: g + weight * heuristic(next, solvedRuns), g: g, node: boards.count - 1))
            }
        }
        return .unwinnable
    }

    public enum Hint: Equatable, Sendable {
        case move(Move)
        /// There is no way to win from this position: undo is the only way on.
        case unwinnable
        /// The search ran out of room before it knew. Never shown as "no way to win".
        case gaveUp
    }

    /// The first move of the shortest solution from here, for the Hint helper, so a player who takes
    /// every hint still earns three stars. When the shortest one cannot be found within the limits,
    /// the search leans on the heuristic instead: a good solution, not always the shortest.
    /// Either way at most `maxNodes` positions are kept (a few tens of MB at worst), so it is quick
    /// and safe on older phones.
    public static func hint(_ board: Board, maxStates: Int = 30_000, maxNodes: Int = 60_000) -> Hint {
        for weight in [1, 2] {
            switch search(board, maxStates: maxStates, maxNodes: maxNodes, weight: weight) {
            case .solved(let result):
                guard let first = result.moves.first else { return .unwinnable }
                return .move(first)
            case .unwinnable: return .unwinnable
            case .gaveUp: continue
            }
        }
        return .gaveUp
    }

    /// Runs still to remove. On a Bubble Bath board one move can remove two runs (a squishy taken from
    /// between a floater and its twin), so there it is the larger of: the runs without the floaters
    /// (a move removes at most one of those), and half of all the runs. Both never overestimate.
    static func heuristic(_ b: Board, _ solvedRuns: Int) -> Int {
        var runs = 0
        var solid = 0
        for jar in b.jars {
            var previous: UInt8?
            var under: UInt8?
            for p in jar {
                if p.kind != previous {
                    runs += 1
                    previous = p.kind
                }
                if !(b.floats && p.isFrozen) && p.kind != under {
                    solid += 1
                    under = p.kind
                }
            }
        }
        guard b.floats else { return runs - solvedRuns }
        return max(solid - solvedRuns, (runs - solvedRuns + 1) / 2)
    }

    static func key(_ b: Board, canonical: Bool) -> [UInt8] {
        // A morph piece is told apart by its other kind too.
        let morphs = b.hasMorphs
        var parts: [[UInt8]] = b.jars.map { jar in
            morphs ? jar.flatMap { [$0.code, $0.morph] } : jar.map(\.code)
        }
        // A spin jar is not the same place as an ordinary jar: each part says which it is.
        if b.hasSpins { for j in parts.indices { parts[j].insert(b.isSpinJar(j) ? 1 : 0, at: 0) } }
        // While a curtain is closed, a vine is tied or a padlock is shut, which jar is which matters.
        let tied = b.hasVines || b.hasKeys
        if canonical && b.curtains.isEmpty && !tied { parts.sort { $0.lexicographicallyPrecedes($1) } }
        var out: [UInt8] = []
        out.reserveCapacity(b.jars.count * (b.capacity + 1) + 3)
        out.append(UInt8(b.curtains.count))
        for j in b.curtains { out.append(UInt8(j)) }
        if tied {
            out.append(contentsOf: b.vines)
            out.append(contentsOf: b.keys)
        }
        for p in parts {
            out.append(UInt8(p.count))
            out.append(contentsOf: p)
        }
        return out
    }
}

/// Binary heap ordered by f, then larger g first (dives toward solutions).
struct MinHeap {
    struct Entry {
        let f: Int
        let g: Int
        let node: Int
    }

    private var items: [Entry] = []

    private static func less(_ a: Entry, _ b: Entry) -> Bool {
        a.f != b.f ? a.f < b.f : a.g > b.g
    }

    mutating func push(_ e: Entry) {
        items.append(e)
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) / 2
            guard MinHeap.less(items[i], items[parent]) else { break }
            items.swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> Entry? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var smallest = i
            if l < items.count && MinHeap.less(items[l], items[smallest]) { smallest = l }
            if r < items.count && MinHeap.less(items[r], items[smallest]) { smallest = r }
            if smallest == i { break }
            items.swapAt(i, smallest)
            i = smallest
        }
        return top
    }
}
