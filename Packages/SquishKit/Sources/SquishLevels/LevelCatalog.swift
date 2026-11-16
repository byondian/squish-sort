import Foundation

/// The worlds in play order and where their level files live.
public enum LevelCatalog {
    public static let worlds = ["toyshop", "sweetfactory", "starlight", "christmas"]
    public static let levelsPerWorld = 20

    /// 1-based number across all worlds (toyshop-01 is 1, sweetfactory-01 is 21).
    public static func globalNumber(world: String, index: Int) -> Int? {
        guard let w = worlds.firstIndex(of: world) else { return nil }
        return w * levelsPerWorld + index
    }

    /// A capsule every 3rd level of a world and on its last level:
    /// 3, 6, 9, 12, 15, 18 and 20.
    public static func isCapsuleLevel(index: Int) -> Bool {
        index % 3 == 0 || index == levelsPerWorld
    }

    /// Reads every Levels/<world>/<nn>.json under `root`, in play order.
    public static func loadFiles(root: URL) throws -> [LevelFile] {
        var out: [LevelFile] = []
        let fm = FileManager.default
        for world in worlds {
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
