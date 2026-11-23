/// One squishy on the board.
///
/// `kind` indexes the level's kind table (its art, colour and squeak).
/// Mechanics travel with the piece when it moves:
/// - `hidden`: wrapped, shown as "?" until it reaches the top of its jar.
/// - `frozen`: moves left until it thaws; a frozen piece can't move. On a Bubble Bath board it is a
///   bubble instead: 1 a floater, 2 a golden bubble that can still ride (see `Board`).
/// - `bondedAbove`: this piece and the one directly above it are a duet and
///   always move together.
/// - `morph`: a morph piece shows two kinds. It counts as `kind`, and each time it is itself
///   poured it flips to its other kind (`morph` is that kind + 1; 0 for an ordinary piece).
public struct Piece: Hashable, Sendable {
    public var kind: UInt8
    public var hidden: Bool
    public var frozen: UInt8
    public var bondedAbove: Bool
    public var morph: UInt8

    public init(kind: UInt8, hidden: Bool = false, frozen: UInt8 = 0, bondedAbove: Bool = false, morph: UInt8 = 0) {
        self.morph = morph
        self.kind = kind
        self.hidden = hidden
        self.frozen = frozen
        self.bondedAbove = bondedAbove
    }

    public var isFrozen: Bool { frozen > 0 }
    public var isMorph: Bool { morph > 0 }
    /// The kind a morph piece turns into the next time it is poured; nil for an ordinary piece.
    public var otherKind: UInt8? { morph > 0 ? morph - 1 : nil }

    /// A morph piece swaps its two kinds; an ordinary piece stays as it is. True if it changed.
    @discardableResult
    public mutating func flip() -> Bool {
        guard morph > 0 else { return false }
        let other = morph - 1
        morph = kind + 1
        kind = other
        return true
    }

    /// Compact encoding used for solver state keys.
    public var code: UInt8 {
        (kind & 0x0F) | (hidden ? 0x10 : 0) | (Swift.min(frozen, 3) << 5) | (bondedAbove ? 0x80 : 0)
    }
}
