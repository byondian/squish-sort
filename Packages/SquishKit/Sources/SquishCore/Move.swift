/// Tap jar `from`, then tap jar `to`.
public struct Move: Hashable, Codable, Sendable, CustomStringConvertible {
    public let from: Int
    public let to: Int

    public init(from: Int, to: Int) {
        self.from = from
        self.to = to
    }

    /// Bubble Bath: the golden bubble on top of jar `from` rides to jar `to`. Stored with a negative
    /// `to` (-1 - jar), so a level file keeps its solution as plain pairs of numbers.
    public static func ride(from: Int, to: Int) -> Move { Move(from: from, to: -1 - to) }
    /// The jar a ride lands in; nil for an ordinary move.
    public var rideTarget: Int? { to < 0 ? -1 - to : nil }
    public var isRide: Bool { to < 0 }
    /// The jar the move ends in, ride or not.
    public var destination: Int { rideTarget ?? to }

    public var description: String { isRide ? "\(from)⇢\(destination)" : "\(from)→\(to)" }
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
    /// Vine jars whose tag reached zero on this move: the vine snaps and the jar is ordinary.
    public var snappedVines: [Int] = []
    /// Jars where a bubble popped on this move (Bubble Bath).
    public var poppedJars: [Int] = []
}
