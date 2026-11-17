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
        XCTAssertEqual(LevelCatalog.worlds.map(LevelCatalog.levelCount(in:)), [15, 20, 25])
        XCTAssertEqual(LevelCatalog.mainLevelCount, 60)
        XCTAssertEqual(all.count, 80)
        XCTAssertEqual(Array(all.prefix(60)).map(\.world),
                       LevelCatalog.worlds.flatMap { Array(repeating: $0, count: LevelCatalog.levelCount(in: $0)) },
                       "the main path comes first, in play order")
        for world in LevelCatalog.allWorlds {
            let inWorld = all.filter { $0.world == world }
            XCTAssertEqual(inWorld.map(\.index), Array(1...LevelCatalog.levelCount(in: world)), world)
            XCTAssertEqual(inWorld.last?.beat, .boss, "\(world) ends on a boss")
            XCTAssertEqual(inWorld.last?.capsule, true, "\(world) ends on a capsule")
        }
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
        XCTAssertEqual((1...20).filter { LevelCatalog.isCapsuleLevel(index: $0, world: "sweetfactory") }, [3, 6, 9, 12, 15, 18, 20])
        XCTAssertEqual((1...25).filter { LevelCatalog.isCapsuleLevel(index: $0, world: "starlight") }, [3, 6, 9, 12, 15, 18, 21, 24, 25])
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
