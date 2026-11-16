import SquishCore

/// Finds the shortest solution (par) with A*.
///
/// Heuristic: total same-kind runs across all jars minus the number of runs a
/// solved board has. A move can remove at most one run, so the heuristic never
/// overestimates and the first solution found is optimal.
///
/// Without frozen pieces jar order doesn't matter to solvability, so states are
/// compared with jars sorted, which shrinks the search a lot.
public enum Solver {
    public struct Result: Sendable {
        public let moves: [Move]
        public let statesExplored: Int
    }

    /// Returns nil if the board can't be solved within `maxStates` expansions.
    public static func solve(_ start: Board, maxStates: Int = 3_000_000) -> Result? {
        let canonical = !start.jars.contains { jar in jar.contains { $0.isFrozen } }
        var counts: [UInt8: Int] = [:]
        for jar in start.jars { for p in jar { counts[p.kind, default: 0] += 1 } }
        let solvedRuns = counts.values.reduce(0) { $0 + ($1 + start.capacity - 1) / start.capacity }

        var boards: [Board] = [start]
        var parents: [Int32] = [-1]
        var moves: [Move] = [Move(from: -1, to: -1)]
        var best: [[UInt8]: Int] = [key(start, canonical: canonical): 0]
        var heap = MinHeap()
        heap.push(.init(f: heuristic(start, solvedRuns), g: 0, node: 0))
        var explored = 0

        while let entry = heap.pop() {
            let current = boards[entry.node]
            if let known = best[key(current, canonical: canonical)], known < entry.g { continue }
            if current.isWon {
                var path: [Move] = []
                var i = entry.node
                while i > 0 {
                    path.append(moves[i])
                    i = Int(parents[i])
                }
                return Result(moves: path.reversed(), statesExplored: explored)
            }
            explored += 1
            if explored > maxStates { return nil }
            for move in current.legalMoves {
                if canonical && current.jars[move.to].isEmpty
                    && current.runLength(at: move.from) == current.jars[move.from].count {
                    continue // pouring a whole jar into an empty one changes nothing
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
                heap.push(.init(f: g + heuristic(next, solvedRuns), g: g, node: boards.count - 1))
            }
        }
        return nil
    }

    /// First move of a shortest solution from here, for the Hint helper.
    /// Kept small so it answers in well under 200 ms on a phone.
    public static func hint(_ board: Board, maxStates: Int = 150_000) -> Move? {
        solve(board, maxStates: maxStates)?.moves.first
    }

    static func heuristic(_ b: Board, _ solvedRuns: Int) -> Int {
        var runs = 0
        for jar in b.jars {
            var previous: UInt8?
            for p in jar where p.kind != previous {
                runs += 1
                previous = p.kind
            }
        }
        return runs - solvedRuns
    }

    static func key(_ b: Board, canonical: Bool) -> [UInt8] {
        var parts = b.jars.map { jar in jar.map(\.code) }
        if canonical { parts.sort { $0.lexicographicallyPrecedes($1) } }
        var out: [UInt8] = []
        out.reserveCapacity(b.jars.count * (b.capacity + 1))
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
