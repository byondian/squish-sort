import Foundation
import SquishCore

/// The 10-level sawtooth from the structure blueprint.
public enum Beat: String, Codable, CaseIterable, Sendable {
    case intro, easy, medium, showpiece, breather, bonus, tension, calm, boss

    /// The beat a level at this position in its world must have. A world always ends on a boss.
    public static func expected(forIndex index: Int, world: String) -> Beat {
        if world == LevelCatalog.weekly {
            // Five boards a theme, a little harder each time; no boss.
            return [.easy, .easy, .medium, .tension, .showpiece][(max(1, index) - 1) % LevelCatalog.weeklyBoards]
        }
        if index == LevelCatalog.levelCount(in: world) { return .boss }
        let pattern: [Beat] = [.intro, .easy, .easy, .medium, .showpiece, .breather, .bonus, .tension, .calm, .boss]
        return pattern[(index - 1) % pattern.count]
    }
}

/// One level, exactly as stored in Levels/<world>/<nn>.json (schema 1).
public struct LevelFile: Codable, Equatable, Sendable {
    public struct Mechanics: Codable, Equatable, Sendable {
        /// [jar, position] of wrapped pieces.
        public var hidden: [[Int]]?
        /// [jar, position] of the lower piece of each duet (it and the one above move together).
        public var sticky: [[Int]]?
        /// [jar, position] or [jar, position, movesToThaw] (default 2). In Bubble Bath these are bubbles:
        /// [jar, position, 1] a floater, [jar, position, 2] a golden bubble that can ride.
        public var frozen: [[Int]]?
        /// Jars that start behind a closed curtain.
        public var curtains: [Int]?
        /// [jar, tag]: jars tied shut by a vine until `tag` jars have been finished (1 or 2).
        public var vines: [[Int]]?
        /// True when the frozen entries are bubbles outside Bubble Bath (a Keep Squishing block that borrows them).
        public var floats: Bool?
        /// Key jars (Keep Squishing): the jar is padlocked until a jar of `kind` is finished.
        public var keys: [KeyJar]?
        /// Morph pieces (Keep Squishing): the piece at `at` in `jar` flips to `kind` when it is poured, and back.
        public var morph: [MorphPiece]?

        public struct KeyJar: Codable, Equatable, Sendable {
            public var jar: Int
            public var kind: String
            public init(jar: Int, kind: String) {
                self.jar = jar
                self.kind = kind
            }
        }

        public struct MorphPiece: Codable, Equatable, Sendable {
            public var jar: Int
            public var at: Int
            public var kind: String
            public init(jar: Int, at: Int, kind: String) {
                self.jar = jar
                self.at = at
                self.kind = kind
            }
        }

        public init(hidden: [[Int]]? = nil, sticky: [[Int]]? = nil, frozen: [[Int]]? = nil, curtains: [Int]? = nil,
                    vines: [[Int]]? = nil, floats: Bool? = nil, keys: [KeyJar]? = nil, morph: [MorphPiece]? = nil) {
            self.keys = keys
            self.morph = morph
            self.hidden = hidden
            self.sticky = sticky
            self.frozen = frozen
            self.curtains = curtains
            self.vines = vines
            self.floats = floats
        }
    }

    public var schema: Int
    public var id: String
    public var world: String
    public var index: Int
    public var beat: Beat
    public var capacity: Int
    /// Piece names per jar, bottom to top.
    public var jars: [[String]]
    public var mechanics: Mechanics?
    public var par: Int?
    public var solution: [[Int]]?
    public var capsule: Bool
    public var softenAfterFails: Int?

    public static let currentSchema = 1
    public static let defaultThaw = 2

    public static func decode(_ data: Data) throws -> LevelFile {
        try JSONDecoder().decode(LevelFile.self, from: data)
    }
}

public enum LevelError: Error, Equatable, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let s): return s
        }
    }
}

/// A decoded level ready to play.
public struct Level: Sendable {
    public let file: LevelFile
    /// Piece names, indexed by `Piece.kind`, in order of first appearance.
    public let kinds: [String]
    public let board: Board

    public var id: String { file.id }
    /// The world this level looks like (Keep Squishing borrows the story worlds in turn).
    public var look: String { LevelCatalog.look(world: file.world, index: file.index) }
    public var par: Int { file.par ?? 0 }

    public var solution: [Move] {
        (file.solution ?? []).compactMap { $0.count == 2 ? Move(from: $0[0], to: $0[1]) : nil }
    }

    /// The hint for `current`. While the player is still on the level's own shortest answer the next
    /// move of that answer is given, which costs nothing and is right even on boards too big to
    /// search to the end. Anywhere else the solver looks for the shortest way on from here.
    public func hint(for current: Board) -> Solver.Hint {
        var step = board
        for move in solution {
            if step == current { return .move(move) }
            guard step.apply(move) != nil else { break }
        }
        return Solver.hint(current)
    }

    public init(file: LevelFile) throws {
        var kinds: [String] = []
        for jar in file.jars {
            for name in jar where !kinds.contains(name) { kinds.append(name) }
        }
        guard kinds.count <= 15 else { throw LevelError.invalid("\(file.id): more than 15 kinds") }

        let m = file.mechanics ?? LevelFile.Mechanics()
        func positions(_ list: [[Int]]?, _ label: String) throws -> [[Int]] {
            for p in list ?? [] {
                guard p.count >= 2, file.jars.indices.contains(p[0]), file.jars[p[0]].indices.contains(p[1]) else {
                    throw LevelError.invalid("\(file.id): \(label) position \(p) is not on the board")
                }
            }
            return list ?? []
        }
        let hidden = Set(try positions(m.hidden, "hidden").map { [$0[0], $0[1]] })
        let sticky = Set(try positions(m.sticky, "sticky").map { [$0[0], $0[1]] })
        let floats = file.world == LevelCatalog.floatWorld || m.floats == true
        var frozen: [[Int]: UInt8] = [:]
        for p in try positions(m.frozen, "frozen") {
            frozen[[p[0], p[1]]] = UInt8(clamping: p.count > 2 ? p[2] : (floats ? 1 : LevelFile.defaultThaw))
        }

        var morphs: [[Int]: UInt8] = [:]
        for piece in m.morph ?? [] {
            let at = [piece.jar, piece.at]
            guard file.jars.indices.contains(piece.jar), file.jars[piece.jar].indices.contains(piece.at),
                  let other = kinds.firstIndex(of: piece.kind), morphs[at] == nil else {
                throw LevelError.invalid("\(file.id): morph piece \(at) must be on the board, once, with a kind of this level")
            }
            morphs[at] = UInt8(other + 1)
        }

        var jars: [[Piece]] = []
        for (j, jar) in file.jars.enumerated() {
            var pieces: [Piece] = []
            for (i, name) in jar.enumerated() {
                let kind = UInt8(kinds.firstIndex(of: name)!)
                pieces.append(Piece(kind: kind,
                                    hidden: hidden.contains([j, i]),
                                    frozen: frozen[[j, i]] ?? 0,
                                    bondedAbove: sticky.contains([j, i]),
                                    morph: morphs[[j, i]] ?? 0))
            }
            jars.append(pieces)
        }
        self.file = file
        self.kinds = kinds
        for j in m.curtains ?? [] where !file.jars.indices.contains(j) {
            throw LevelError.invalid("\(file.id): curtain jar \(j) is not on the board")
        }
        var vines: [Int: Int] = [:]
        for v in m.vines ?? [] {
            guard v.count == 2, file.jars.indices.contains(v[0]), (1...2).contains(v[1]), vines[v[0]] == nil else {
                throw LevelError.invalid("\(file.id): vine \(v) must be [jar, 1 or 2], one per jar")
            }
            vines[v[0]] = v[1]
        }
        var keys: [Int: Int] = [:]
        for key in m.keys ?? [] {
            guard file.jars.indices.contains(key.jar), let kind = kinds.firstIndex(of: key.kind), keys[key.jar] == nil else {
                throw LevelError.invalid("\(file.id): key jar \(key.jar) must be on the board, once, with a kind of this level")
            }
            keys[key.jar] = kind
        }
        self.board = Board(capacity: file.capacity, jars: jars, curtains: m.curtains ?? [], vines: vines, floats: floats,
                           keys: keys)
    }
}
