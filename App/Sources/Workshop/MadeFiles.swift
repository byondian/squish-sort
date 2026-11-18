import SwiftUI
import UIKit
import SquishWorkshop

/// Where made squishies' designs are kept: one small file each in Application Support/made, with a
/// baked picture next to it. The progress file only keeps their ids, names and order, because it
/// is written again on every change.
@MainActor
final class MadeFiles: MadeStore {
    static let shared = MadeFiles()

    private let dir: URL
    private var pictures: [String: UIImage] = [:]
    /// Goes up when the drawing changes, so pictures baked by an older build are baked again.
    private static let look = 1
    static let pictureSide: CGFloat = 512
    static let thumbSide: CGFloat = 128

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // UI tests start from nothing every time, like the progress they run with.
        return base.appendingPathComponent(AppModel.isUITesting ? "made-uitest" : "made", isDirectory: true)
    }

    init() {
        dir = MadeFiles.folder
        if AppModel.isUITesting { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sweepSkins()
    }

    /// Pictures from drawings that no saved squishy wears any more (a squishy that was never
    /// finished, or one whose shape was changed) are thrown away after a day.
    private func sweepSkins() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let skins = files.filter { $0.lastPathComponent.hasPrefix(PhotoSkins.prefix) }
        guard !skins.isEmpty else { return }
        var worn = Set<String>()
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url), let design = try? JSONDecoder().decode(WorkshopDesign.self, from: data),
               let skin = design.skin { worn.insert(PhotoSkins.prefix + skin + ".png") }
        }
        for url in skins where !worn.contains(url.lastPathComponent) {
            let changed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(changed) > 86_400 { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func file(_ id: String, _ ending: String) -> URL {
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return dir.appendingPathComponent(safe + ending)
    }

    func load(id: String) -> WorkshopDesign? {
        guard let data = try? Data(contentsOf: file(id, ".json")) else { return nil }
        return try? JSONDecoder().decode(WorkshopDesign.self, from: data)
    }

    func save(_ design: WorkshopDesign, id: String) {
        guard let data = try? JSONEncoder().encode(design) else { return }
        try? data.write(to: file(id, ".json"), options: [.atomic])
        bake(design, id: id)
    }

    func delete(id: String) {
        if let skin = load(id: id)?.skin { PhotoSkins.remove(skin) }
        for ending in [".json", "-\(MadeFiles.look).png", "-\(MadeFiles.look)-small.png"] {
            try? FileManager.default.removeItem(at: file(id, ending))
        }
        pictures[id] = nil
        pictures[id + "-small"] = nil
    }

    /// Draws the squishy once into a picture, so the room, the Buddy and the shelves do not have
    /// to put it together from its parts every time.
    private func bake(_ design: WorkshopDesign, id: String) {
        for (side, ending, key) in [(MadeFiles.pictureSide, "-\(MadeFiles.look).png", id),
                                    (MadeFiles.thumbSide, "-\(MadeFiles.look)-small.png", id + "-small")] {
            let renderer = ImageRenderer(content: WorkshopSquishyView(design: design).frame(width: side, height: side))
            renderer.scale = 1
            renderer.isOpaque = false
            guard let image = renderer.uiImage else { continue }
            pictures[key] = image
            try? image.pngData()?.write(to: file(id, ending), options: [.atomic])
        }
    }

    /// The baked picture of a saved squishy. Nil when there is none yet: the caller draws it from its parts.
    func picture(_ id: String, small: Bool = false) -> UIImage? {
        let key = small ? id + "-small" : id
        if let hit = pictures[key] { return hit }
        let url = file(id, small ? "-\(MadeFiles.look)-small.png" : "-\(MadeFiles.look).png")
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        pictures[key] = image
        return image
    }
}

/// Pictures lifted from drawings on paper (Squishy Workshop): one PNG each, kept beside the made
/// squishies. A design only holds the picture's name.
@MainActor
enum PhotoSkins {
    static let prefix = "skin-"
    private static var cache: [String: UIImage] = [:]

    private static func file(_ name: String) -> URL {
        let safe = name.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return MadeFiles.folder.appendingPathComponent(prefix + safe + ".png")
    }

    static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        guard let image = UIImage(contentsOfFile: file(name).path) else { return nil }
        cache[name] = image
        return image
    }

    /// Keeps a picture and gives back the name to put in the design.
    static func keep(_ image: UIImage) -> String? {
        let name = UUID().uuidString
        try? FileManager.default.createDirectory(at: MadeFiles.folder, withIntermediateDirectories: true)
        guard let data = image.pngData(), (try? data.write(to: file(name), options: [.atomic])) != nil else { return nil }
        cache[name] = image
        return name
    }

    static func remove(_ name: String) {
        cache[name] = nil
        try? FileManager.default.removeItem(at: file(name))
    }
}
