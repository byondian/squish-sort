import Foundation

/// The worlds in play order (main path first, then side worlds) and where their level files live.
public enum LevelCatalog {
    /// The main path, in play order: 60 levels.
    public static let worlds = ["toyshop", "sweetfactory", "starlight"]
    /// Side worlds have their own level numbers 1 to 20 and are not on the map's main path.
    public static let sideWorlds = ["christmas"]
    public static var allWorlds: [String] { worlds + sideWorlds }
    public static let levelsPerWorld = 20
    public static var mainLevelCount: Int { worlds.count * levelsPerWorld }

    /// A capsule every 3rd level of a world and on its last level:
    /// 3, 6, 9, 12, 15, 18 and 20.
    public static func isCapsuleLevel(index: Int) -> Bool {
        index % 3 == 0 || index == levelsPerWorld
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
