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
        XCTAssertEqual(LevelCatalog.endlessBlocks.count, LevelCatalog.endlessLooks.count)
        XCTAssertEqual(LevelCatalog.endlessBlock(index: 60), "grand-mix")
        XCTAssertEqual(LevelCatalog.endlessBlock(index: 91), "star-splash")
        // The three Keep Squishing twists come in on blocks 2, 3 and 4.
        XCTAssertEqual((1...4).map { LevelCatalog.endlessBlock(index: $0 * 10) }, ["toy-freeze", "space-locks", "morph-mayhem", "mega-jars"])
        XCTAssertTrue(LevelCatalog.isExpert(world: LevelCatalog.endless, index: 5))
        XCTAssertFalse(LevelCatalog.isExpert(world: "toyshop", index: 5))
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
        // Keep Squishing comes after Jungle Jam, so it may borrow vines; no earlier world does.
        XCTAssertFalse(all.contains { !["junglejam", LevelCatalog.endless].contains($0.world) && !($0.mechanics?.vines ?? []).isEmpty },
                       "vines stay in Jungle Jam and Keep Squishing")
        // Keep Squishing mixes every world's rule, and wrapped squishies are no longer on every level.
        let keep = all.filter { $0.world == LevelCatalog.endless }
        XCTAssertTrue(keep.contains { !($0.mechanics?.vines ?? []).isEmpty })
        XCTAssertTrue(keep.contains { $0.mechanics?.floats == true })
        XCTAssertTrue(keep.contains { !($0.mechanics?.sticky ?? []).isEmpty })
        XCTAssertTrue(keep.contains { !($0.mechanics?.curtains ?? []).isEmpty })
        XCTAssertLessThan(keep.filter { !($0.mechanics?.hidden ?? []).isEmpty }.count, keep.count / 3)
        // Its own three twists: key jars, morph pieces (never more than two) and jars of five. No story world has them.
        XCTAssertGreaterThanOrEqual(keep.filter { !($0.mechanics?.keys ?? []).isEmpty }.count, 20)
        XCTAssertGreaterThanOrEqual(keep.filter { !($0.mechanics?.morph ?? []).isEmpty }.count, 20)
        XCTAssertGreaterThanOrEqual(keep.filter { $0.capacity == 5 }.count, 20)
        XCTAssertFalse(keep.contains { ($0.mechanics?.morph ?? []).count > LevelValidator.maxMorphs })
        XCTAssertFalse(all.contains { $0.world != LevelCatalog.endless
            && ($0.capacity != 4 || !($0.mechanics?.keys ?? []).isEmpty || !($0.mechanics?.morph ?? []).isEmpty) })
        // The first board of each twist's first block shows that twist alone.
        for (index, rule) in [(11, "keys"), (21, "morph"), (31, "big")] {
            let file = try XCTUnwrap(keep.first { $0.index == index })
            let m = file.mechanics
            XCTAssertEqual(!(m?.keys ?? []).isEmpty, rule == "keys", file.id)
            XCTAssertEqual(!(m?.morph ?? []).isEmpty, rule == "morph", file.id)
            XCTAssertEqual(file.capacity == 5, rule == "big", file.id)
            XCTAssertTrue((m?.hidden ?? []).isEmpty && (m?.sticky ?? []).isEmpty && (m?.frozen ?? []).isEmpty, file.id)
        }
        XCTAssertGreaterThanOrEqual(keep.filter { $0.index % 5 == 0 && $0.jars.filter(\.isEmpty).count == 1 }.count, 15,
                                    "Expert boards with one spare jar")
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

    func testSolverPlansAroundAKeyJar() throws {
        // Jar 1 is padlocked until the jar of A is finished.
        let pieces: ([UInt8]) -> [Piece] = { $0.map { Piece(kind: $0) } }
        let jars = [pieces([0]), pieces([1, 2]), pieces([0]), pieces([2, 1]), pieces([])]
        let locked = Board(capacity: 2, jars: jars, keys: [1: 0])
        let result = try XCTUnwrap(Solver.solve(locked))
        XCTAssertEqual(result.moves.count, 4)
        var b = locked
        for move in result.moves { XCTAssertNotNil(b.apply(move)) }
        XCTAssertTrue(b.isWon)
        // A padlock whose key kind is locked inside it can never open.
        let stuck = Board(capacity: 2, jars: [pieces([0, 1]), pieces([1, 0]), pieces([])], keys: [0: 0])
        XCTAssertNil(Solver.solve(stuck))
    }

    func testSolverPlansAroundAMorphPiece() throws {
        // The morph piece shows B and turns into A. Poured once it is an A, and the board comes out as two jars of A.
        let start = Board(capacity: 2, jars: [[Piece(kind: 0), Piece(kind: 1, morph: 1)], [Piece(kind: 1), Piece(kind: 0)], [], []])
        let result = try XCTUnwrap(Solver.solve(start))
        XCTAssertEqual(result.moves.count, 4)
        var b = start
        for move in result.moves { XCTAssertNotNil(b.apply(move)) }
        XCTAssertTrue(b.isWon)
        if case .move = Solver.hint(start) {} else { XCTFail("a hint is found on a morph board") }
        // Pouring a lone morph piece into an empty jar is a real move: it flips. Here it is the only way to win.
        let flip = Board(capacity: 2, jars: [[Piece(kind: 0, morph: 2)], [Piece(kind: 1)], [Piece(kind: 0), Piece(kind: 0)], []])
        XCTAssertEqual(Solver.solve(flip)?.moves.count, 2, "into the empty jar to become a B, then onto the B")
    }

    func testKeyJarsAndMorphPiecesReadFromALevelFile() throws {
        let json = """
        {"schema": 1, "id": "endless-11", "world": "endless", "index": 11, "beat": "intro", "capacity": 4,
         "jars": [["a", "a", "b", "b"], ["b", "b", "a", "a"], [], []],
         "mechanics": {"hidden": [], "sticky": [], "frozen": [],
                       "keys": [{"jar": 1, "kind": "a"}], "morph": [{"jar": 0, "at": 3, "kind": "a"}]},
         "par": 1, "solution": [], "capsule": false, "softenAfterFails": null}
        """
        let file = try LevelFile.decode(Data(json.utf8))
        let level = try Level(file: file)
        XCTAssertEqual(level.board.keyKind(1), 0)
        XCTAssertEqual(level.board.jars[0][3].otherKind, 0)
        XCTAssertEqual(level.board.jars[0][3].kind, 1)
        // The validator turns down a key jar that holds its own key kind, and either twist in a story world.
        XCTAssertTrue(LevelValidator.structuralProblems(file).contains { $0.contains("holds its own key kind") })
        var story = file
        story.world = "toyshop"
        story.id = "toyshop-11"
        XCTAssertTrue(LevelValidator.structuralProblems(story).contains { $0.contains("Keep Squishing only") })
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
