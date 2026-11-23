import Foundation
import XCTest
import SquishCore
@testable import SquishLevels
import SquishPolicy

/// Repo root, found from this file's path (Packages/SquishKit/Tests/SquishLevelsTests/).
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let levelsRoot = repoRoot.appendingPathComponent("Levels", isDirectory: true)

final class LevelTests: XCTestCase {
    func files() throws -> [LevelFile] { try LevelCatalog.loadFiles(root: levelsRoot) }

    func testWorldsGrowAndEveryLevelIsThere() throws {
        let all = try files()
        XCTAssertEqual(LevelCatalog.worlds.map(LevelCatalog.levelCount(in:)), [15, 20, 25, 30, 35])
        XCTAssertEqual(LevelCatalog.mainLevelCount, 125)
        XCTAssertEqual(all.count, 385)
        XCTAssertEqual(Array(all.prefix(125)).map(\.world),
                       LevelCatalog.worlds.flatMap { Array(repeating: $0, count: LevelCatalog.levelCount(in: $0)) },
                       "the main path comes first, in play order")
        XCTAssertEqual(Array(all[125..<365]).map(\.world), Array(repeating: LevelCatalog.endless, count: 240),
                       "Keep Squishing follows the story worlds")
        XCTAssertEqual(LevelCatalog.look(world: LevelCatalog.endless, index: 1), "toyshop")
        XCTAssertEqual(LevelCatalog.look(world: LevelCatalog.endless, index: 11), "sweetfactory")
        XCTAssertEqual(LevelCatalog.look(world: LevelCatalog.endless, index: 31), "bubblebath")
        XCTAssertEqual(LevelCatalog.endlessLooks.count * 10, LevelCatalog.levelCount(in: LevelCatalog.endless))
        XCTAssertEqual(LevelCatalog.look(world: "toyshop", index: 11), "toyshop")
        XCTAssertEqual((1...20).filter { LevelCatalog.isCapsuleLevel(index: $0, world: LevelCatalog.endless) }, [5, 10, 15, 20])
        for world in LevelCatalog.fileWorlds {
            let inWorld = all.filter { $0.world == world }
            XCTAssertEqual(inWorld.map(\.index), Array(1...LevelCatalog.levelCount(in: world)), world)
            XCTAssertEqual(inWorld.last?.beat, .boss, "\(world) ends on a boss")
            XCTAssertEqual(inWorld.last?.capsule, true, "\(world) ends on a capsule")
        }
    }

    func testJungleJamHasVineJarsAndBubbleBathHasBubbles() throws {
        let all = try files()
        let jungle = all.filter { $0.world == "junglejam" }
        XCTAssertTrue(jungle.contains { !($0.mechanics?.vines ?? []).isEmpty }, "Jungle Jam has vine jars")
        XCTAssertFalse(all.contains { $0.world != "junglejam" && !($0.mechanics?.vines ?? []).isEmpty }, "vines stay in Jungle Jam")
        for file in jungle {
            let board = try Level(file: file).board
            let tied = (0..<board.jarCount).filter { board.vineTag($0) > 0 }
            XCTAssertLessThanOrEqual(tied.count, 2, file.id)
            for j in tied {
                XCTAssertLessThanOrEqual(board.vineTag(j), 2, file.id)
                XCTAssertFalse(board.isComplete(j), "\(file.id): a tied jar never starts finished")
            }
        }
        let bath = try all.filter { $0.world == "bubblebath" }.map { try Level(file: $0).board }
        // Every Bubble Bath level has a floater or a golden bubble, each on top of its jar and never one
        // that would pop before the first move. The first level has one floater; rides start at level 4.
        for (n, board) in bath.enumerated() {
            XCTAssertTrue(board.floats)
            let bubbles = board.jars.joined().filter { $0.isFrozen }
            XCTAssertFalse(bubbles.isEmpty, "bubblebath-\(n + 1) has a bubble")
            for jar in board.jars {
                XCTAssertLessThanOrEqual(jar.filter { $0.isFrozen }.count, 1)
                if let i = jar.firstIndex(where: { $0.isFrozen }) {
                    XCTAssertEqual(i, jar.count - 1)
                    XCTAssertTrue(i > 0 && jar[i - 1].kind != jar[i].kind)
                }
            }
            if n < 3 { XCTAssertFalse(bubbles.contains { $0.frozen == 2 }, "no ride before level 4") }
        }
        XCTAssertEqual(bath.first?.jars.joined().filter { $0.isFrozen }.count, 1)
        XCTAssertTrue(bath.count > 3 && bath[3].jars.joined().contains { $0.frozen == 2 }, "level 4 teaches the ride")
        XCTAssertTrue(try all.filter { $0.world != "bubblebath" && $0.mechanics?.floats != true }.allSatisfy { try !Level(file: $0).board.floats })
    }

    func testStructureBeatAndCapsules() throws {
        for file in try files() {
            let problems = LevelValidator.structuralProblems(file)
            XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
        }
    }

    func testStoredSolutionsReplayToAWinInParMoves() throws {
        for file in try files() {
            let level = try Level(file: file)
            var b = level.board
            for move in level.solution {
                XCTAssertNotNil(b.apply(move), "\(file.id): illegal move \(move)")
            }
            XCTAssertTrue(b.isWon, "\(file.id) solution doesn't win")
            XCTAssertEqual(level.solution.count, file.par, file.id)
        }
    }

    func testSolverAgreesWithParOnTheSmallLevels() throws {
        // The full re-solve of every level runs in the release-built CLI on CI.
        for file in try files() where (file.par ?? 99) <= 10 {
            let (problems, _) = LevelValidator.check(file)
            XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
        }
    }

    func testEveryPieceIsACommonSquishy() throws {
        let roster = try Roster.decode(Data(contentsOf: repoRoot.appendingPathComponent("Content/roster.json")))
        let commons = Set(roster.collectibles.filter { $0.rarity == .common }.map(\.id))
        for file in try files() {
            for name in file.jars.joined() {
                XCTAssertTrue(commons.contains(name), "\(file.id): \(name) isn't a common squishy")
            }
        }
    }

    func testOpeningLevelsMatchTheDesignDoc() throws {
        let all = try files()
        XCTAssertEqual(all[0].par, 2)
        XCTAssertEqual(all[1].par, 3)
        XCTAssertEqual(all[2].par, 7)
        XCTAssertEqual(all[0].jars, [["strawbie", "strawbie", "strawbie"], ["tango", "tango", "tango", "strawbie"], ["tango"]])
        XCTAssertTrue(all[2].capsule, "first capsule after level 3")
    }

    func testCapsuleSchedule() {
        XCTAssertEqual((1...20).filter { LevelCatalog.isCapsuleLevel(index: $0, world: "sweetfactory") }, [3, 6, 9, 10, 12, 15, 18, 20])
        XCTAssertEqual((1...25).filter { LevelCatalog.isCapsuleLevel(index: $0, world: "starlight") }, [3, 6, 9, 10, 12, 15, 18, 20, 21, 24, 25])
        XCTAssertEqual(Beat.expected(forIndex: 15, world: "toyshop"), .boss)
        XCTAssertEqual(Beat.expected(forIndex: 15, world: "sweetfactory"), .showpiece)
    }
}

final class SolverTests: XCTestCase {
    func testSolverWaitsForTheCurtain() {
        // A | curtain(B C) | A | C B | empty: the curtain jar opens once the A jar next to it is finished.
        func jar(_ kinds: [UInt8]) -> [Piece] { kinds.map { Piece(kind: $0) } }
        let jars = [jar([0]), jar([1, 2]), jar([0]), jar([2, 1]), jar([])]
        let closed = Board(capacity: 2, jars: jars, curtains: [1])
        let result = Solver.solve(closed)
        XCTAssertEqual(result?.moves.count, 4)
        XCTAssertEqual(result?.moves.first.map { Set([$0.from, $0.to]) }, [0, 2])
        // The hint never points into or out of a closed curtain.
        if case .move(let move) = Solver.hint(closed) {
            XCTAssertFalse(move.from == 1 || move.to == 1)
        } else {
            XCTFail("a hint was expected")
        }
        // A curtain with no jar beside it that can ever be finished cannot be won.
        let shut = Board(capacity: 2, jars: [jar([1, 2]), jar([2, 1]), jar([])], curtains: [0])
        XCTAssertNil(Solver.solve(shut))
    }

    func testLevelThreeSolvesInSeven() throws {
        let file = LevelFile(schema: 1, id: "toyshop-03", world: "toyshop", index: 3, beat: .easy, capacity: 4,
                             jars: [["r", "y", "y", "b"], ["y", "b", "b", "r"], ["b", "r", "r", "y"], [], []],
                             mechanics: nil, par: nil, solution: nil, capsule: true, softenAfterFails: nil)
        let level = try Level(file: file)
        XCTAssertEqual(Solver.solve(level.board)?.moves.count, 7)
    }

    func testUnsolvableBoardReturnsNil() {
        let b = Board(capacity: 4, jars: [[Piece(kind: 0), Piece(kind: 1), Piece(kind: 0), Piece(kind: 1)],
                                          [Piece(kind: 1), Piece(kind: 0), Piece(kind: 1), Piece(kind: 0)]])
        XCTAssertNil(Solver.solve(b))
    }

    func testNoHintFromADeadEnd() {
        // Not stuck yet (moves exist) but unwinnable: the hint must be nil so nothing is charged.
        let b = Board(capacity: 4, jars: [[Piece(kind: 0), Piece(kind: 1), Piece(kind: 0), Piece(kind: 1)],
                                          [Piece(kind: 1), Piece(kind: 0), Piece(kind: 1), Piece(kind: 0)]])
        XCTAssertEqual(Solver.hint(b), .unwinnable)
    }

    func testHintIsALegalMove() throws {
        let file = try LevelCatalog.loadFiles(root: levelsRoot).first { $0.id == "toyshop-08" }!
        let level = try Level(file: file)
        guard case .move(let hint) = Solver.hint(level.board) else { return XCTFail("no hint for toyshop-08") }
        XCTAssertTrue(level.board.isLegal(hint))
    }

    func testAHintIsFoundOnEveryLevelWithinTheMemoryLimit() throws {
        for file in try LevelCatalog.loadFiles(root: levelsRoot) {
            let level = try Level(file: file)
            guard case .move(let hint) = Solver.hint(level.board) else { XCTFail("no hint for \(file.id)"); continue }
            XCTAssertTrue(level.board.isLegal(hint), file.id)
        }
    }

    func testNoBoardOnTheWayToAWinIsCalledADeadEnd() throws {
        // Every level, every board along its answer: a win is still ahead, so none is a dead end.
        for file in try LevelCatalog.loadFiles(root: levelsRoot) {
            let level = try Level(file: file)
            var session = GameSession(board: level.board, par: level.solution.count)
            XCTAssertFalse(session.isDeadEnd, "\(file.id) start")
            for (n, move) in level.solution.enumerated() {
                XCTAssertNotNil(session.play(move), "\(file.id) move \(n + 1)")
                XCTAssertFalse(session.isDeadEnd, "\(file.id) after move \(n + 1)")
                XCTAssertNotEqual(session.status, .stuck, "\(file.id) after move \(n + 1)")
            }
            XCTAssertTrue(session.board.isWon, file.id)
        }
    }

    func testADeadEndReallyHasNoWayToWin() throws {
        // Wander off the answer on every level. Wherever the dead end note would show, the full
        // search must agree that no win is left.
        var rng = SystemRandomNumberGenerator()
        var seen = 0
        for file in try LevelCatalog.loadFiles(root: levelsRoot) {
            let start = try Level(file: file).board
            for _ in 0..<6 {
                var board = start
                for _ in 0..<60 {
                    guard let move = board.legalMoves.randomElement(using: &rng), board.apply(move) != nil else { break }
                    if board.isWon { break }
                    if board.isDeadEnd() {
                        seen += 1
                        XCTAssertNil(Solver.solve(board, maxStates: 200_000), "\(file.id): called a dead end, but it can be won")
                        break
                    }
                }
            }
        }
        XCTAssertGreaterThan(seen, 0)
    }

    func testTakingEveryHintWinsInTheFewestMoves() throws {
        // Three stars leave no move to spare on hard levels, so hints must not wander.
        for file in try LevelCatalog.loadFiles(root: levelsRoot) {
            let level = try Level(file: file)
            var board = level.board
            var moves = 0
            while !board.isWon, moves <= level.par {
                guard case .move(let hint) = level.hint(for: board), board.apply(hint) != nil else { break }
                moves += 1
            }
            XCTAssertTrue(board.isWon, file.id)
            XCTAssertEqual(moves, level.par, file.id)
        }
        // Off the level's own answer the search itself finds the shortest way (Sweet Factory 13 took 16, not 14).
        let level = try Level(file: try LevelCatalog.loadFiles(root: levelsRoot).first { $0.id == "sweetfactory-13" }!)
        var board = level.board
        var moves = 0
        while !board.isWon, moves < 40 {
            guard case .move(let hint) = Solver.hint(board), board.apply(hint) != nil else { break }
            moves += 1
        }
        XCTAssertEqual(moves, level.par)
    }

    func testRunningOutOfRoomIsNotCalledUnwinnable() throws {
        let file = try LevelCatalog.loadFiles(root: levelsRoot).first { $0.id == "toyshop-08" }!
        XCTAssertEqual(Solver.hint(try Level(file: file).board, maxStates: 1, maxNodes: 1), .gaveUp)
    }

    func testDuetLevelSolutionRespectsDuets() throws {
        let file = try LevelCatalog.loadFiles(root: levelsRoot).first { $0.id == "starlight-04" }!
        let level = try Level(file: file)
        XCTAssertTrue(level.board.jars.joined().contains { $0.bondedAbove })
    }
}
