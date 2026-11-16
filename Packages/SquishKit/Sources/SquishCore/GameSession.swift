/// One attempt at a level: the board, undo history, helpers and result.
public struct GameSession: Sendable {
    public enum Status: Equatable, Sendable {
        case playing
        case won(stars: Int)
        case stuck
    }

    public let initialBoard: Board
    public let par: Int
    public private(set) var board: Board
    public private(set) var history: [Board] = []
    /// Undos left this attempt; nil means unlimited (Remove Ads).
    public private(set) var undosLeft: Int?
    public private(set) var extraJarsAdded = 0

    public init(board: Board, par: Int, undoLimit: Int? = 5) {
        self.initialBoard = board
        self.board = board
        self.par = par
        self.undosLeft = undoLimit
    }

    /// Moves made, net of undos. Stars are judged on this.
    public var moveCount: Int { history.count }

    public var status: Status {
        if board.isWon { return .won(stars: Stars.rating(moves: moveCount, par: par)) }
        if board.isStuck { return .stuck }
        return .playing
    }

    @discardableResult
    public mutating func play(_ move: Move) -> MoveResult? {
        guard status == .playing else { return nil }
        let before = board
        guard let result = board.apply(move) else { return nil }
        history.append(before)
        return result
    }

    public var canUndo: Bool {
        guard !history.isEmpty else { return false }
        if let left = undosLeft { return left > 0 }
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard canUndo, let previous = history.popLast() else { return false }
        board = previous
        if let left = undosLeft { undosLeft = left - 1 }
        return true
    }

    /// Extra jar helper: one empty jar for the rest of this attempt.
    public mutating func addExtraJar() {
        guard board.jarCount < BoardLayout.maxJars + 1 else { return }
        board.addEmptyJar()
        // Keep the jar through undo as well.
        history = history.map { previous in
            var b = previous
            b.addEmptyJar()
            return b
        }
        extraJarsAdded += 1
    }
}
