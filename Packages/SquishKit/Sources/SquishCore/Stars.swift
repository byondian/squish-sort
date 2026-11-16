/// Stars against the solver's par, which is the fewest moves possible. Par itself is
/// a perfect game, so three stars leave a little room: par plus a fifth (at least 2 moves).
/// Two stars reach to par plus a third (at least 4 moves); any other solve is 1 star.
/// Passing needs only 1 star.
public enum Stars {
    /// The most moves that still earn this many stars (nil for 1 star: any solve).
    /// `tight` is for the hard levels (tension and boss): about half the slack.
    public static func moveLimit(forStars stars: Int, par: Int, tight: Bool = false) -> Int? {
        switch stars {
        case 3...: return par + (tight ? max(1, par / 10) : max(2, par / 5))
        case 2: return par + (tight ? max(3, par / 5) : max(4, par / 3))
        default: return nil
        }
    }

    public static func rating(moves: Int, par: Int, tight: Bool = false) -> Int {
        if let three = moveLimit(forStars: 3, par: par, tight: tight), moves <= three { return 3 }
        if let two = moveLimit(forStars: 2, par: par, tight: tight), moves <= two { return 2 }
        return 1
    }
}
