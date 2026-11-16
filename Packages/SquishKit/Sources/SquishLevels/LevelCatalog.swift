import Foundation

/// The worlds in play order (main path first, then side worlds) and where their level files live.
public enum LevelCatalog {
    /// The main path, in play order.
    public static let worlds = ["toyshop", "sweetfactory", "starlight"]
    /// Side worlds have their own level numbers and are not on the map's main path.
    public static let sideWorlds = ["christmas"]
    public static var allWorlds: [String] { worlds + sideWorlds }
    /// How many levels each world has. Worlds grow as the game goes on; this table is the one place that says so.
    public static let lengths: [String: Int] = ["toyshop": 15, "sweetfactory": 20, "starlight": 25, "christmas": 20]
    public static func levelCount(in world: String) -> Int { lengths[world] ?? 20 }
    public static var mainLevelCount: Int { worlds.reduce(0) { $0 + levelCount(in: $1) } }

    /// A capsule every 3rd level of a world and on its last level.
    public static func isCapsuleLevel(index: Int, world: String) -> Bool {
        index % 3 == 0 || index == levelCount(in: world)
    }

    /// Reads every Levels/<world>/<nn>.json under `root`, in play order.
    public static func loadFiles(root: URL) throws -> [LevelFile] {
        var out: [LevelFile] = []
        let fm = FileManager.default
        for world in allWorlds {
            let dir = root.appendingPathComponent(world, isDirectory: true)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names.sorted() where name.hasSuffix(".json") {
                let data = try Data(contentsOf: dir.appendingPathComponent(name))
                do {
                    out.append(try LevelFile.decode(data))
                } catch {
                    throw LevelError.invalid("\(world)/\(name): \(error)")
                }
            }
        }
        return out
    }

    public static func load(root: URL) throws -> [Level] {
        try loadFiles(root: root).map { try Level(file: $0) }
    }
}
