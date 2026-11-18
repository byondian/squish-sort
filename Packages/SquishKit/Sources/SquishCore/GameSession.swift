/// One attempt at a level: the board, undo history, helpers and result.
public struct GameSession: Sendable {
    public enum Status: Equatable, Sendable {
        case playing
        case won(stars: Int)
        case stuck
    }

    public let initialBoard: Board
    /// The best possible number of moves. A shake-up works it out again from the new layout.
    public private(set) var par: Int
    /// Moves over the best answer that still earn three stars (nil: the roomy early rule).
    public let starSlack: Int?
    public private(set) var board: Board { didSet { deadEnd = board.isDeadEnd() } }
    /// Worked out once each time the board changes, not on every read of `status`.
    private var deadEnd = false
    public private(set) var history: [Board] = []
    /// Undos left this attempt; nil means unlimited (Remove Ads).
    public private(set) var undosLeft: Int?
    public private(set) var extraJarsAdded = 0
    /// One flag per move in `history`: a free move (Squish Fever) is not counted.
    private var free: [Bool] = []
    /// Moves counted before the last shake-up, which undo cannot go back past.
    private var movesBefore = 0

    public init(board: Board, par: Int, undoLimit: Int? = 5, starSlack: Int? = nil) {
        self.initialBoard = board
        self.board = board
        self.par = par
        self.starSlack = starSlack
        self.undosLeft = undoLimit
        self.deadEnd = board.isDeadEnd()
    }

    /// Moves made, net of undos. Stars are judged on this.
    public var moveCount: Int { movesBefore + free.reduce(0) { $0 + ($1 ? 0 : 1) } }

    public var status: Status {
        if board.isWon { return .won(stars: Stars.rating(moves: moveCount, par: par, slack: starSlack)) }
        // Stuck means no move at all. A board with moves left is never called stuck, even when
        // none of them can win: the player can see those moves, so the game only points it out.
        if board.isStuck { return .stuck }
        return .playing
    }

    /// Moves are left but none of them leads to a win. The level shows a gentle note; play goes on.
    public var isDeadEnd: Bool { deadEnd && !board.isWon && !board.isStuck }

    @discardableResult
    public mutating func play(_ move: Move, free isFree: Bool = false) -> MoveResult? {
        guard status == .playing else { return nil }
        let before = board
        guard let result = board.apply(move) else { return nil }
        history.append(before)
        free.append(isFree)
        return result
    }

    /// Shake-up: the pieces land in new spots. The moves made so far stay counted, the best answer
    /// is worked out again from here (so a shake-up never costs stars), and undo cannot go back past it.
    public mutating func shakeUp(to newBoard: Board, bestFromHere: Int) {
        movesBefore = moveCount
        history = []
        free = []
        board = newBoard
        par = movesBefore + max(0, bestFromHere)
    }

    /// Shuffle button: the pieces land in new spots, the moves made so far stay counted and the
    /// star limit does not move, so a shuffle gets a player unstuck without being a way to three stars.
    /// Undo cannot go back past it.
    public mutating func shuffle(to newBoard: Board) {
        movesBefore = moveCount
        history = []
        free = []
        board = newBoard
    }

    public var canUndo: Bool {
        guard !history.isEmpty else { return false }
        if let left = undosLeft { return left > 0 }
        return true
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard canUndo, let previous = history.popLast() else { return false }
        if !free.isEmpty { free.removeLast() }
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
