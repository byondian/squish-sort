/// Stars against the solver's par, which is the fewest moves possible. Par itself is
/// a perfect game, so three stars leave a little room: par plus a fifth (at least 2 moves).
/// Two stars reach to par plus a half (at least 4 moves); any other solve is 1 star.
/// Passing needs only 1 star.
public enum Stars {
    /// The most moves that still earn this many stars (nil for 1 star: any solve).
    public static func moveLimit(forStars stars: Int, par: Int) -> Int? {
        switch stars {
        case 3...: return par + max(2, par / 5)
        case 2: return par + max(4, par / 2)
        default: return nil
        }
    }

    public static func rating(moves: Int, par: Int) -> Int {
        if moves <= par + max(2, par / 5) { return 3 }
        if moves <= par + max(4, par / 2) { return 2 }
        return 1
    }
}
