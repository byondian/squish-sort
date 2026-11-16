/// Stars against the solver's par, which is the fewest moves possible. Par itself is
/// a perfect game, so three stars leave a little room: par plus a fifth (at least 2 moves).
/// Two stars reach to par plus a third (at least 4 moves); any other solve is 1 star.
/// Passing needs only 1 star.
public enum Stars {
    /// The most moves that still earn this many stars (nil for 1 star: any solve).
    /// `slack` is how many moves over the best answer still earn three stars. The game sets it
    /// per level, from 2 at the start down to 0 on later hard levels. Nil is the roomy early rule.
    public static func moveLimit(forStars stars: Int, par: Int, slack: Int? = nil) -> Int? {
        switch stars {
        case 3...: return par + (slack.map { max(0, $0) } ?? max(2, par / 5))
        case 2: return par + (slack.map { max(0, $0) + max(2, par / 6) } ?? max(4, par / 3))
        default: return nil
        }
    }

    public static func rating(moves: Int, par: Int, slack: Int? = nil) -> Int {
        if let three = moveLimit(forStars: 3, par: par, slack: slack), moves <= three { return 3 }
        if let two = moveLimit(forStars: 2, par: par, slack: slack), moves <= two { return 2 }
        return 1
    }
}
