/// Tap jar `from`, then tap jar `to`.
public struct Move: Hashable, Codable, Sendable, CustomStringConvertible {
    public let from: Int
    public let to: Int

    public init(from: Int, to: Int) {
        self.from = from
        self.to = to
    }

    public var description: String { "\(from)→\(to)" }
}

/// What a move did, so the board scene can animate it.
public struct MoveResult: Equatable, Sendable {
    public let move: Move
    /// How many pieces hopped (a conga line when > 1).
    public let count: Int
    /// The source jar's new top was unwrapped.
    public let revealedSourceTop: Bool
    /// The destination jar is now complete and lidded.
    public let completedJar: Int?
    /// Jars whose frozen pieces fully thawed on this move.
    public let thawedJars: [Int]
    /// A duet landed on its bottom member's kind and let go.
    public var duetLetGo = false
    /// Curtain jars that opened because the jar next door was finished on this move.
    public var raisedCurtains: [Int] = []
}
