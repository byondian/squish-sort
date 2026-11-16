/// Stars against the solver's par: 3 at or under par, 2 up to par + 30%,
/// 1 for any solve. Passing needs only 1 star.
public enum Stars {
    public static func rating(moves: Int, par: Int) -> Int {
        if moves <= par { return 3 }
        if moves * 10 <= par * 13 { return 2 }
        return 1
    }
}
