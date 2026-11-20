/// One squishy on the board.
///
/// `kind` indexes the level's kind table (its art, colour and squeak).
/// Mechanics travel with the piece when it moves:
/// - `hidden`: wrapped, shown as "?" until it reaches the top of its jar.
/// - `frozen`: moves left until it thaws; a frozen piece can't move. On a Bubble Bath board it is a
///   bubble instead: 1 a floater, 2 a golden bubble that can still ride (see `Board`).
/// - `bondedAbove`: this piece and the one directly above it are a duet and
///   always move together.
public struct Piece: Hashable, Sendable {
    public var kind: UInt8
    public var hidden: Bool
    public var frozen: UInt8
    public var bondedAbove: Bool

    public init(kind: UInt8, hidden: Bool = false, frozen: UInt8 = 0, bondedAbove: Bool = false) {
        self.kind = kind
        self.hidden = hidden
        self.frozen = frozen
        self.bondedAbove = bondedAbove
    }

    public var isFrozen: Bool { frozen > 0 }

    /// Compact encoding used for solver state keys.
    public var code: UInt8 {
        (kind & 0x0F) | (hidden ? 0x10 : 0) | (Swift.min(frozen, 3) << 5) | (bondedAbove ? 0x80 : 0)
    }
}
