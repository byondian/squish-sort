import XCTest
@testable import SquishCore

/// Builds a board from letters, bottom to top. Lowercase = hidden,
/// "*" after a letter = frozen (2), "+" after a letter = bonded with the next.
func board(_ jars: [String], capacity: Int = 4) -> Board {
    var parsed: [[Piece]] = []
    for jar in jars {
        var pieces: [Piece] = []
        for ch in jar {
            switch ch {
            case "*": pieces[pieces.count - 1].frozen = 2
            case "+": pieces[pieces.count - 1].bondedAbove = true
            default:
                let upper = Character(ch.uppercased())
                let kind = UInt8(upper.asciiValue! - Character("A").asciiValue!)
                pieces.append(Piece(kind: kind, hidden: ch.isLowercase))
            }
        }
        parsed.append(pieces)
    }
    return Board(capacity: capacity, jars: parsed)
}

final class BoardTests: XCTestCase {
    func testLevelOneHasOnlyTheTaughtMoves() {
        // [R R R] [B B B R] [B] from the game design doc
        var b = board(["AAA", "BBBA", "B"])
        XCTAssertEqual(b.legalMoves, [Move(from: 1, to: 0)])
        XCTAssertEqual(b.apply(Move(from: 1, to: 0))?.completedJar, 0)
        XCTAssertEqual(Set(b.legalMoves), [Move(from: 1, to: 2), Move(from: 2, to: 1)])
        b.apply(Move(from: 1, to: 2))
        XCTAssertTrue(b.isWon)
    }

    func testCongaLineMovesTogetherAsFarAsThereIsRoom() {
        var b = board(["BAAA", "", "CCA"])
        XCTAssertEqual(b.piecesToMove(Move(from: 0, to: 1)), 3)
        XCTAssertEqual(b.piecesToMove(Move(from: 0, to: 2)), 1)
        b.apply(Move(from: 0, to: 2))
        XCTAssertEqual(b.jars[0].count, 3)
        XCTAssertEqual(b.jars[2].map(\.kind), [2, 2, 0, 0])
    }

    func testIllegalMoves() {
        let b = board(["AB", "AAAA", "BBBA", "C"])
        XCTAssertFalse(b.isLegal(Move(from: 0, to: 3)), "different kind")
        XCTAssertFalse(b.isLegal(Move(from: 1, to: 0)), "complete jars are locked")
        XCTAssertFalse(b.isLegal(Move(from: 2, to: 1)), "can't land on a full jar")
        XCTAssertFalse(b.isLegal(Move(from: 0, to: 0)))
        XCTAssertFalse(b.isLegal(Move(from: 0, to: 9)))
        var copy = b
        XCTAssertNil(copy.apply(Move(from: 0, to: 3)))
    }

    func testHiddenPiecesStopTheCongaAndRevealWhenOnTop() {
        // jar 0: A(hidden) A A — only the top two move
        var b = board(["aAA", ""])
        XCTAssertEqual(b.runLength(at: 0), 2)
        let r = b.apply(Move(from: 0, to: 1))
        XCTAssertEqual(r?.revealedSourceTop, true)
        XCTAssertFalse(b.jars[0][0].hidden)
    }

    func testTopPieceIsNeverHiddenAtStart() {
        let b = board(["Ba"])
        XCTAssertFalse(b.jars[0][1].hidden)
    }

    func testADuetMovesTogetherAndNeedsTwoSpaces() {
        // jar 0: C, then the duet A (bottom) holding B (top).
        var b = board(["CA+B", "CCA", "DDD", ""])
        XCTAssertEqual(b.runLength(at: 0), 2)
        XCTAssertFalse(b.isLegal(Move(from: 0, to: 1)), "only one space, a duet needs two")
        XCTAssertFalse(b.isLegal(Move(from: 0, to: 2)), "one space and the wrong kind")
        XCTAssertEqual(b.piecesToMove(Move(from: 0, to: 3)), 2)
        let r = b.apply(Move(from: 0, to: 3))
        XCTAssertEqual(r?.duetLetGo, false)
        XCTAssertTrue(b.jars[3][0].bondedAbove, "in an empty jar the two stay together")
        XCTAssertEqual(b.jars[0].count, 1)
    }

    func testADuetLetsGoOnItsBottomMembersKind() {
        var b = board(["CA+B", "AA", "B", ""])
        XCTAssertFalse(b.isLegal(Move(from: 0, to: 2)), "the top member's kind is not enough")
        let r = b.apply(Move(from: 0, to: 1))
        XCTAssertEqual(r?.duetLetGo, true)
        XCTAssertFalse(b.jars[1].contains { $0.bondedAbove }, "they are ordinary pieces now")
        XCTAssertEqual(b.jars[1].map(\.kind), [0, 0, 0, 1])
        // The freed top member moves on by itself.
        XCTAssertEqual(b.piecesToMove(Move(from: 1, to: 2)), 1)
    }

    func testARunAboveADuetStopsAtTheDuet() {
        // C, the duet A+B, then a loose B on top: only the loose B moves.
        let b = board(["CA+BB", "B", "", "CCC"])
        XCTAssertEqual(b.runLength(at: 0), 1)
        XCTAssertEqual(b.piecesToMove(Move(from: 0, to: 1)), 1)
    }

    func testFrozenPiecesThawAfterTwoNeighbourMoves() {
        // jars in one row: 0 1 2 3. Jar 1's top is frozen.
        var b = board(["AB", "CA*", "B", ""])
        XCTAssertEqual(b.runLength(at: 1), 0)
        XCTAssertFalse(b.isLegal(Move(from: 1, to: 3)))
        b.apply(Move(from: 0, to: 2))           // leaves jar 0, a neighbour: 2 → 1
        XCTAssertEqual(b.jars[1][1].frozen, 1)
        let r = b.apply(Move(from: 0, to: 3))   // leaves jar 0 again: 1 → 0, thawed
        XCTAssertEqual(r?.thawedJars, [1])
        XCTAssertEqual(b.jars[1][1].frozen, 0)
        XCTAssertTrue(b.isLegal(Move(from: 1, to: 3)))
    }

    func testFrozenPiecesIgnoreMovesFarAway() {
        var b = board(["A*B", "C", "", "B"])
        b.apply(Move(from: 3, to: 2)) // jars 2 and 3 aren't next to jar 0
        XCTAssertEqual(b.jars[0][0].frozen, 2)
    }

    func testExtraJarHasNoNeighbours() {
        var b = board(["A*B", "C", "B"])
        b.addEmptyJar()
        b.apply(Move(from: 2, to: 3)) // jar 2 is not next to jar 0 in a 3-jar row
        XCTAssertEqual(b.jars[0][0].frozen, 2)
    }

    func testCompletingAJarLocksAndSettlesIt() {
        var b = board(["A*AA", "A", "B"])
        // jar 0's pieces are frozen at the bottom; the top two still move, but here we pour into jar 0
        b.apply(Move(from: 1, to: 0))
        XCTAssertTrue(b.isComplete(0))
        XCTAssertFalse(b.jars[0].contains { $0.isFrozen })
        XCTAssertEqual(b.runLength(at: 0), 0)
    }

    func testStuck() {
        let b = board(["ABAB", "BABA"])
        XCTAssertTrue(b.isStuck)
        XCTAssertFalse(board(["ABAB", "BABA", ""]).isStuck)
    }

    func testCurtainJarIsShutUntilTheJarNextDoorIsFinished() {
        let open = board(["A", "BC", "A", "CB", ""], capacity: 2)
        var b = Board(capacity: 2, jars: open.jars, curtains: [1])
        XCTAssertTrue(b.isCurtained(1))
        XCTAssertEqual(b.runLength(at: 1), 0)
        XCTAssertFalse(b.isLegal(Move(from: 1, to: 4)))
        // Nothing goes in either.
        var filler = Board(capacity: 2, jars: board(["C", "", "A", "A"], capacity: 2).jars, curtains: [1])
        XCTAssertFalse(filler.isLegal(Move(from: 0, to: 1)))
        XCTAssertEqual(filler.apply(Move(from: 2, to: 3))?.raisedCurtains, [])
        // Finishing the jar next door raises it for good.
        let result = b.apply(Move(from: 0, to: 2))
        XCTAssertEqual(result?.completedJar, 2)
        XCTAssertEqual(result?.raisedCurtains, [1])
        XCTAssertFalse(b.isCurtained(1))
        XCTAssertTrue(b.isLegal(Move(from: 1, to: 4)))
    }

    func testVineJarIsShutUntilItsTagIsCountedDown() {
        // Jar 1 is tied with a 2 on its tag; jar 4 is spare room.
        let jars = board(["A", "BC", "A", "CB", ""], capacity: 2).jars
        var b = Board(capacity: 2, jars: jars, vines: [1: 2])
        XCTAssertEqual(b.vineTag(1), 2)
        XCTAssertTrue(b.isShut(1))
        XCTAssertFalse(b.isComplete(1), "a tied jar is not a finished jar")
        XCTAssertEqual(b.runLength(at: 1), 0)
        XCTAssertFalse(b.isLegal(Move(from: 1, to: 4)), "nothing comes out")
        XCTAssertFalse(b.isLegal(Move(from: 3, to: 1)), "nothing goes in")
        XCTAssertFalse(b.isStuck, "a tied jar does not make the board stuck while another move is open")
        // The first finished jar counts the tag down to 1: still shut.
        let first = b.apply(Move(from: 0, to: 2))
        XCTAssertEqual(first?.completedJar, 2)
        XCTAssertEqual(first?.snappedVines, [])
        XCTAssertEqual(b.vineTag(1), 1)
        XCTAssertTrue(b.isShut(1))
        // A move that finishes nothing leaves the tag alone.
        XCTAssertEqual(b.apply(Move(from: 3, to: 4))?.snappedVines, [])
        XCTAssertEqual(b.vineTag(1), 1)
    }

    func testVineSnapsAtZeroAndTheJarIsOrdinaryAgain() {
        let jars = board(["A", "BC", "A", "CB", ""], capacity: 2).jars
        var b = Board(capacity: 2, jars: jars, vines: [1: 1])
        XCTAssertTrue(b.hasVines)
        let result = b.apply(Move(from: 0, to: 2))
        XCTAssertEqual(result?.snappedVines, [1])
        XCTAssertEqual(b.vineTag(1), 0)
        XCTAssertFalse(b.hasVines)
        XCTAssertFalse(b.isShut(1))
        XCTAssertTrue(b.isLegal(Move(from: 1, to: 4)))
    }

    func testAnEmptyVineJarIsRoomThatArrivesLater() {
        let jars = board(["AB", "BA", "", "C", "C"], capacity: 2).jars
        var b = Board(capacity: 2, jars: jars, vines: [2: 1])
        XCTAssertFalse(b.isLegal(Move(from: 0, to: 2)), "the spare jar is tied")
        XCTAssertEqual(b.apply(Move(from: 3, to: 4))?.snappedVines, [2])
        XCTAssertTrue(b.isLegal(Move(from: 0, to: 2)))
    }

    func testShakeUpLeavesAClosedCurtainAlone() {
        let jars = board(["AB", "BC", "CA", "", ""], capacity: 2).jars
        let b = Board(capacity: 2, jars: jars, curtains: [1])
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<10 {
            let next = b.shakenUp(using: &rng)
            XCTAssertEqual(next.jars[1], b.jars[1])
            XCTAssertEqual(next.curtains, [1])
        }
    }

    func testDeadEndIsSeenBeforeTheLastMove() {
        // The only move passes one B back and forth for ever: no jar can ever be freed.
        let dead = board(["AB", "ABB", "A"], capacity: 3)
        XCTAssertFalse(dead.isStuck)
        XCTAssertTrue(dead.isDeadEnd())
        // Moves are left, so it is not called stuck: the level only points the dead end out.
        var session = GameSession(board: dead, par: 5)
        XCTAssertEqual(session.status, .playing)
        XCTAssertTrue(session.isDeadEnd)
        XCTAssertNotNil(session.play(dead.legalMoves[0]))
        // Few moves open, but they lead to a win: alive.
        let alive = board(["AB", "B", "A"], capacity: 2)
        XCTAssertFalse(alive.isDeadEnd())
        XCTAssertEqual(GameSession(board: alive, par: 2).status, .playing)
        XCTAssertFalse(GameSession(board: alive, par: 2).isDeadEnd)
        // Won boards and boards with no move at all are not this.
        XCTAssertFalse(board(["AAAA", ""]).isDeadEnd())
        XCTAssertFalse(board(["ABAB", "BABA"]).isDeadEnd())
    }

    func testLayoutRows() {
        XCTAssertEqual(BoardLayout.rows(jarCount: 5), [[0, 1, 2, 3, 4]])
        XCTAssertEqual(BoardLayout.rows(jarCount: 9), [[0, 1, 2, 3, 4], [5, 6, 7, 8]])
        XCTAssertEqual(BoardLayout.rows(jarCount: 12).map(\.count), [6, 6])
        XCTAssertEqual(BoardLayout.neighbours(of: 4, jarCount: 9), [3])
        XCTAssertEqual(BoardLayout.neighbours(of: 5, jarCount: 9), [6])
    }
}

final class SessionTests: XCTestCase {
    func testFreeMovesAreNotCountedAndUndoGivesThemBack() {
        let board = Board(capacity: 2, jars: [[Piece(kind: 0), Piece(kind: 1)], [Piece(kind: 1), Piece(kind: 0)], []])
        var s = GameSession(board: board, par: 3)
        XCTAssertNotNil(s.play(Move(from: 0, to: 2)))
        XCTAssertNotNil(s.play(Move(from: 1, to: 0), free: true))
        XCTAssertEqual(s.moveCount, 1, "a free move is not counted")
        XCTAssertTrue(s.undo())
        XCTAssertEqual(s.moveCount, 1)
        XCTAssertTrue(s.undo())
        XCTAssertEqual(s.moveCount, 0)
    }

    func testShakeUpKeepsMovesResetsParAndBlocksUndo() {
        let board = Board(capacity: 2, jars: [[Piece(kind: 0), Piece(kind: 1)], [Piece(kind: 1), Piece(kind: 0)], []])
        var s = GameSession(board: board, par: 3)
        XCTAssertNotNil(s.play(Move(from: 0, to: 2)))
        var rng = SystemRandomNumberGenerator()
        let shaken = s.board.shakenUp(using: &rng)
        XCTAssertEqual(shaken.jars.map(\.count), s.board.jars.map(\.count), "every jar keeps its number of pieces")
        XCTAssertEqual(shaken.jars.joined().map(\.kind).sorted(), s.board.jars.joined().map(\.kind).sorted())
        s.shakeUp(to: shaken, bestFromHere: 4)
        XCTAssertEqual(s.moveCount, 1)
        XCTAssertEqual(s.par, 5)
        XCTAssertFalse(s.canUndo, "undo cannot go back past a shake-up")
    }

    func testAShuffleKeepsMovesAndTheStarLimitAndBlocksUndo() {
        let board = Board(capacity: 2, jars: [[Piece(kind: 0), Piece(kind: 1)], [Piece(kind: 1), Piece(kind: 0)], []])
        var s = GameSession(board: board, par: 3)
        XCTAssertNotNil(s.play(Move(from: 0, to: 2)))
        var rng = SystemRandomNumberGenerator()
        s.shuffle(to: s.board.shakenUp(using: &rng))
        XCTAssertEqual(s.moveCount, 1)
        XCTAssertEqual(s.par, 3, "a shuffle is not a way to three stars")
        XCTAssertFalse(s.canUndo, "undo cannot go back past a shuffle")
    }

    func testShakeUpLeavesFinishedJarsAlone() {
        let done = [Piece(kind: 2), Piece(kind: 2)]
        let board = Board(capacity: 2, jars: [done, [Piece(kind: 0), Piece(kind: 1)], [Piece(kind: 1), Piece(kind: 0)], []])
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<10 {
            let shaken = board.shakenUp(using: &rng)
            XCTAssertEqual(shaken.jars[0].map(\.kind), [2, 2])
            XCTAssertTrue(shaken.jars[3].isEmpty)
        }
    }

    func testUndoIsLimitedToFivePerAttempt() {
        var s = GameSession(board: board(["AB", "BA", "", ""]), par: 4)
        XCTAssertNotNil(s.play(Move(from: 0, to: 2)))
        for _ in 0..<6 {
            s.play(Move(from: 2, to: 3))
            s.play(Move(from: 3, to: 2))
        }
        XCTAssertEqual(s.moveCount, 13)
        var undone = 0
        while s.undo() { undone += 1 }
        XCTAssertEqual(undone, 5)
        XCTAssertEqual(s.undosLeft, 0)
    }

    func testUnlimitedUndoForRemoveAds() {
        var s = GameSession(board: board(["AB", "BA", "", ""]), par: 4, undoLimit: nil)
        s.play(Move(from: 0, to: 2))
        for _ in 0..<10 { s.play(Move(from: 2, to: 3)); s.play(Move(from: 3, to: 2)) }
        var undone = 0
        while s.undo() { undone += 1 }
        XCTAssertEqual(undone, 21)
    }

    func testExtraJarSurvivesUndo() {
        var s = GameSession(board: board(["AB", "BA", ""]), par: 4)
        s.play(Move(from: 0, to: 2))
        s.addExtraJar()
        XCTAssertEqual(s.board.jarCount, 4)
        s.undo()
        XCTAssertEqual(s.board.jarCount, 4)
    }

    func testStarLimitsMatchTheRating() {
        for par in 2...40 {
            let three = Stars.moveLimit(forStars: 3, par: par)!
            let two = Stars.moveLimit(forStars: 2, par: par)!
            XCTAssertEqual(Stars.rating(moves: three, par: par), 3)
            XCTAssertEqual(Stars.rating(moves: two, par: par), two == three ? 3 : 2)
            XCTAssertLessThan(Stars.rating(moves: two + 1, par: par), 3)
            XCTAssertEqual(Stars.rating(moves: two + 1, par: par), 1)
        }
        XCTAssertNil(Stars.moveLimit(forStars: 1, par: 10))
        // Later levels set their own slack, down to none.
        XCTAssertEqual(Stars.moveLimit(forStars: 3, par: 24, slack: 0), 24)
        XCTAssertEqual(Stars.moveLimit(forStars: 2, par: 24, slack: 0), 30)
        XCTAssertEqual(Stars.rating(moves: 24, par: 24, slack: 0), 3)
        XCTAssertEqual(Stars.rating(moves: 25, par: 24, slack: 0), 2)
        XCTAssertEqual(Stars.rating(moves: 31, par: 24, slack: 0), 1)
        XCTAssertEqual(Stars.rating(moves: 9, par: 8, slack: 1), 3)
        XCTAssertEqual(Stars.rating(moves: 12, par: 8, slack: 1), 2)
        XCTAssertEqual(Stars.rating(moves: 13, par: 8, slack: 1), 1)
    }

    func testStarsAgainstPar() {
        // Par is a perfect game, so three stars leave a little room.
        XCTAssertEqual(Stars.rating(moves: 10, par: 10), 3)
        XCTAssertEqual(Stars.rating(moves: 12, par: 10), 3)
        XCTAssertEqual(Stars.rating(moves: 13, par: 10), 2)
        XCTAssertEqual(Stars.rating(moves: 14, par: 10), 2)
        XCTAssertEqual(Stars.rating(moves: 15, par: 10), 1, "a win over the two-star limit is one star")
        XCTAssertEqual(Stars.rating(moves: 32, par: 24), 2)
        XCTAssertEqual(Stars.rating(moves: 33, par: 24), 1)
        XCTAssertEqual(Stars.rating(moves: 5, par: 3), 3)
        XCTAssertEqual(Stars.rating(moves: 29, par: 24), 2)
        XCTAssertEqual(Stars.rating(moves: 28, par: 24), 3)
    }

    func testWinAndStatus() {
        var s = GameSession(board: board(["AAA", "BBBA", "B"]), par: 2)
        XCTAssertEqual(s.status, .playing)
        s.play(Move(from: 1, to: 0))
        s.play(Move(from: 1, to: 2))
        XCTAssertEqual(s.status, .won(stars: 3))
        XCTAssertNil(s.play(Move(from: 0, to: 1)), "no moves after a win")
    }
}
