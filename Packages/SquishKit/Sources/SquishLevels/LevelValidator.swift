import Foundation
import SquishCore

/// Gate 2 checks: decode, launch board limits, beat pattern, capsule schedule,
/// solvable, and the stored par and solution match the solver.
public enum LevelValidator {
    public static let launchCapacity = 4
    public static let kindRange = 2...8

    /// Everything that doesn't need the solver. Empty means OK.
    public static func structuralProblems(_ file: LevelFile) -> [String] {
        var p: [String] = []
        let id = file.id
        if file.schema != LevelFile.currentSchema { p.append("\(id): schema \(file.schema), expected \(LevelFile.currentSchema)") }
        let expectedID = file.world + "-" + String(format: "%02d", file.index)
        if file.id != expectedID { p.append("\(id): id should be \(expectedID)") }
        if !LevelCatalog.allWorlds.contains(file.world) { p.append("\(id): unknown world \(file.world)") }
        if !(1...LevelCatalog.levelCount(in: file.world)).contains(file.index) { p.append("\(id): index out of range") }
        if file.capacity != launchCapacity { p.append("\(id): capacity \(file.capacity), launch levels use \(launchCapacity)") }
        if !(2...BoardLayout.maxJars).contains(file.jars.count) { p.append("\(id): \(file.jars.count) jars, allowed 2 to \(BoardLayout.maxJars)") }
        if file.jars.contains(where: { $0.count > file.capacity }) { p.append("\(id): a jar is over capacity") }
        let beat = Beat.expected(forIndex: file.index, world: file.world)
        if file.beat != beat { p.append("\(id): beat \(file.beat.rawValue), the sawtooth expects \(beat.rawValue)") }
        let capsule = LevelCatalog.isCapsuleLevel(index: file.index, world: file.world)
        if file.capsule != capsule {
            p.append("\(id): capsule flag should be \(capsule)")
        }

        var counts: [String: Int] = [:]
        for jar in file.jars { for name in jar { counts[name, default: 0] += 1 } }
        if !kindRange.contains(counts.count) { p.append("\(id): \(counts.count) kinds, allowed \(kindRange)") }
        for (name, c) in counts.sorted(by: { $0.key < $1.key }) where c % file.capacity != 0 {
            p.append("\(id): \(c) × \(name), must be a multiple of \(file.capacity)")
        }

        let level: Level
        do { level = try Level(file: file) } catch { p.append("\(error)"); return p }
        let board = level.board
        if board.isWon { p.append("\(id): already solved at the start") }
        for j in board.jars.indices where board.isComplete(j) { p.append("\(id): jar \(j) starts complete") }
        for jar in board.jars {
            for i in jar.indices where jar[i].bondedAbove {
                if i + 1 >= jar.count { p.append("\(id): duet at the top of a jar has no partner"); continue }
                let a = jar[i], b = jar[i + 1]
                if a.kind != b.kind { p.append("\(id): duet pieces must be the same kind") }
                if a.hidden || b.hidden || a.isFrozen || b.isFrozen { p.append("\(id): duet pieces can't be hidden or frozen") }
                if b.bondedAbove { p.append("\(id): a piece can only be in one duet") }
            }
        }
        return p
    }

    /// Full check including the solver. Returns problems and the solver result.
    public static func check(_ file: LevelFile, maxStates: Int = 3_000_000) -> (problems: [String], solved: Solver.Result?) {
        var p = structuralProblems(file)
        guard p.isEmpty, let level = try? Level(file: file) else { return (p, nil) }
        guard let result = Solver.solve(level.board, maxStates: maxStates) else {
            p.append("\(file.id): no solution found within \(maxStates) states")
            return (p, nil)
        }
        if file.par != result.moves.count {
            p.append("\(file.id): par is \(file.par.map { String($0) } ?? "missing"), solver says \(result.moves.count)")
        }
        // The stored solution must replay to a win in exactly par moves.
        var board = level.board
        for move in level.solution {
            if board.apply(move) == nil {
                p.append("\(file.id): stored solution has an illegal move \(move)")
                break
            }
        }
        if !board.isWon { p.append("\(file.id): stored solution doesn't win") }
        if level.solution.count != result.moves.count {
            p.append("\(file.id): stored solution is \(level.solution.count) moves, par is \(result.moves.count)")
        }
        return (p, result)
    }
}
