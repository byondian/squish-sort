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

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // UI tests start from nothing every time, like the progress they run with.
        dir = base.appendingPathComponent(AppModel.isUITesting ? "made-uitest" : "made", isDirectory: true)
        if AppModel.isUITesting { try? FileManager.default.removeItem(at: dir) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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
