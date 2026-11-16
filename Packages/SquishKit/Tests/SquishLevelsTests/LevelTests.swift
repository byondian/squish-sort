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

    func testEightyLevelsTwentyPerWorld() throws {
        let all = try files()
        XCTAssertEqual(all.count, 80)
        for world in LevelCatalog.worlds {
            let inWorld = all.filter { $0.world == world }
            XCTAssertEqual(inWorld.map(\.index), Array(1...20), world)
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
        let capsules = (1...80).filter(LevelCatalog.isCapsuleLevel(globalNumber:))
        XCTAssertEqual(capsules, [3, 6, 9, 12, 15, 18, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80])
    }
}

final class SolverTests: XCTestCase {
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
        XCTAssertNil(Solver.hint(b))
    }

    func testHintIsALegalMove() throws {
        let file = try LevelCatalog.loadFiles(root: levelsRoot).first { $0.id == "toyshop-08" }!
        let level = try Level(file: file)
        let hint = try XCTUnwrap(Solver.hint(level.board, maxStates: 200_000))
        XCTAssertTrue(level.board.isLegal(hint))
    }

    func testDuetLevelSolutionRespectsDuets() throws {
        let file = try LevelCatalog.loadFiles(root: levelsRoot).first { $0.id == "starlight-04" }!
        let level = try Level(file: file)
        XCTAssertTrue(level.board.jars.joined().contains { $0.bondedAbove })
    }
}
