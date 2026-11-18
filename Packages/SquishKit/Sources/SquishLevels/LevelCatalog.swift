import Foundation

/// The worlds in play order (main path first, then side worlds) and where their level files live.
public enum LevelCatalog {
    /// The main path, in play order.
    public static let worlds = ["toyshop", "sweetfactory", "starlight", "bubblebath", "junglejam"]
    /// Side worlds have their own level numbers and are not on the map's main path.
    public static let sideWorlds = ["christmas"]
    public static var allWorlds: [String] { worlds + sideWorlds }
    /// Keep Squishing: where the main path carries on once the story worlds are won. Blocks of ten
    /// borrow the story worlds' squishies and rules in turn; when its last level is won it starts again.
    public static let endless = "endless"
    /// Every level you walk through in order: the story worlds, then Keep Squishing.
    public static var path: [String] { worlds + [endless] }
    /// Every world with level files, in the order the files are loaded.
    public static var fileWorlds: [String] { path + sideWorlds }
    /// Whose squishies and room each block of ten in Keep Squishing borrows.
    public static let endlessLooks = ["sweetfactory", "starlight", "toyshop", "starlight"]
    /// The world a level looks like: its own, or the one its block borrows.
    public static func look(world: String, index: Int) -> String {
        guard world == endless else { return world }
        return endlessLooks[((max(1, index) - 1) / 10) % endlessLooks.count]
    }
    /// How many levels each world has. Worlds grow as the game goes on; this table is the one place that says so.
    public static let lengths: [String: Int] = ["toyshop": 15, "sweetfactory": 20, "starlight": 25, "bubblebath": 30, "junglejam": 35, "christmas": 20, endless: 240]
    public static func levelCount(in world: String) -> Int { lengths[world] ?? 20 }
    public static var mainLevelCount: Int { worlds.reduce(0) { $0 + levelCount(in: $1) } }

    /// A capsule every 3rd level of a world, on every boss (each 10th level) and on its last level.
    public static func isCapsuleLevel(index: Int, world: String) -> Bool {
        // Keep Squishing: every fifth level.
        if world == endless { return index % 5 == 0 }
        return index % 3 == 0 || index % 10 == 0 || index == levelCount(in: world)
    }

    /// Reads every Levels/<world>/<nn>.json under `root`, in play order.
    public static func loadFiles(root: URL) throws -> [LevelFile] {
        var out: [LevelFile] = []
        let fm = FileManager.default
        for world in fileWorlds {
            let dir = root.appendingPathComponent(world, isDirectory: true)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            var inWorld: [LevelFile] = []
            for name in names.sorted() where name.hasSuffix(".json") {
                let data = try Data(contentsOf: dir.appendingPathComponent(name))
                do {
                    inWorld.append(try LevelFile.decode(data))
                } catch {
                    throw LevelError.invalid("\(world)/\(name): \(error)")
                }
            }
            // By number, not by file name: 100 comes after 99.
            out += inWorld.sorted { $0.index < $1.index }
        }
        return out
    }

    public static func load(root: URL) throws -> [Level] {
        try loadFiles(root: root).map { try Level(file: $0) }
    }
}
