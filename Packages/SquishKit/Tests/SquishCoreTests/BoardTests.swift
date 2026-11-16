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

    func testDuetsMoveTogetherAndNeedTwoSpaces() {
        // jar 0: B, A+A (duet at positions 1-2)
        var b = board(["BA+A", "CCA", "DDD", ""])
        XCTAssertEqual(b.runLength(at: 0), 2)
        XCTAssertFalse(b.isLegal(Move(from: 0, to: 1)), "only one space, a duet needs two")
        XCTAssertEqual(b.piecesToMove(Move(from: 0, to: 3)), 2)
        b.apply(Move(from: 0, to: 3))
        XCTAssertTrue(b.jars[3][0].bondedAbove)
        XCTAssertEqual(b.jars[0].count, 1)
    }

    func testCongaNeverSplitsADuet() {
        // A, A+A, A on top: room 2 moves only the top A (taking 2 would split the duet).
        let b = board(["CA+AA", "AA", "", "CCC"])
        XCTAssertEqual(b.runLength(at: 0), 3)
        XCTAssertEqual(b.piecesToMove(Move(from: 0, to: 1)), 1)
        XCTAssertEqual(b.piecesToMove(Move(from: 0, to: 2)), 3)
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

    func testLayoutRows() {
        XCTAssertEqual(BoardLayout.rows(jarCount: 5), [[0, 1, 2, 3, 4]])
        XCTAssertEqual(BoardLayout.rows(jarCount: 9), [[0, 1, 2, 3, 4], [5, 6, 7, 8]])
        XCTAssertEqual(BoardLayout.rows(jarCount: 12).map(\.count), [6, 6])
        XCTAssertEqual(BoardLayout.neighbours(of: 4, jarCount: 9), [3])
        XCTAssertEqual(BoardLayout.neighbours(of: 5, jarCount: 9), [6])
    }
}

final class SessionTests: XCTestCase {
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
        XCTAssertEqual(Stars.moveLimit(forStars: 2, par: 24, slack: 0), 28)
        XCTAssertEqual(Stars.rating(moves: 24, par: 24, slack: 0), 3)
        XCTAssertEqual(Stars.rating(moves: 25, par: 24, slack: 0), 2)
        XCTAssertEqual(Stars.rating(moves: 29, par: 24, slack: 0), 1)
        XCTAssertEqual(Stars.rating(moves: 9, par: 8, slack: 1), 3)
        XCTAssertEqual(Stars.rating(moves: 11, par: 8, slack: 1), 2)
        XCTAssertEqual(Stars.rating(moves: 12, par: 8, slack: 1), 1)
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
