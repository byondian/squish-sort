/// Stars against the solver's par: 3 at or under par, 2 up to par + 30%,
/// 1 for any solve. Passing needs only 1 star.
public enum Stars {
    /// The most moves that still earn this many stars (nil for 1 star: any solve).
    public static func moveLimit(forStars stars: Int, par: Int) -> Int? {
        switch stars {
        case 3...: return par
        case 2: return par * 13 / 10
        default: return nil
        }
    }

    public static func rating(moves: Int, par: Int) -> Int {
        if moves <= par { return 3 }
        if moves * 10 <= par * 13 { return 2 }
        return 1
    }
}
