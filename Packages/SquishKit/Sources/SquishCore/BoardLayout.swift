/// Jar rows. Up to 6 jars sit in one row; 7 to 12 are split into two rows,
/// the top row taking the extra jar when the count is odd.
public enum BoardLayout {
    public static let maxJars = 12
    public static let maxPerRow = 6

    public static func rows(jarCount n: Int) -> [[Int]] {
        guard n > 0 else { return [] }
        if n <= maxPerRow { return [Array(0..<n)] }
        let top = (n + 1) / 2
        return [Array(0..<top), Array(top..<n)]
    }

    /// Jars next to `jar` in its row. Used by the frozen mechanic.
    public static func neighbours(of jar: Int, jarCount n: Int) -> [Int] {
        for row in rows(jarCount: n) {
            guard let i = row.firstIndex(of: jar) else { continue }
            var out: [Int] = []
            if i > 0 { out.append(row[i - 1]) }
            if i < row.count - 1 { out.append(row[i + 1]) }
            return out
        }
        return []
    }
}
