import Foundation
import SquishPolicy

/// Everything the player has, in one Codable file with atomic writes.
/// Collectible ids are stable so the January accounts update can migrate them.
struct PlayerProgress: Codable, Equatable {
    var version = 1
    /// Best stars per level id.
    var stars: [String: Int] = [:]
    /// Index into the play-order level list of the furthest unlocked level.
    var highestUnlocked = 0
    var collection = CollectionState()
    /// Nil until the age step is done. Nothing that sends data starts before then.
    var age: AgeProfile?
    var cadence = AdCadenceState()
    var soundOn = true
    var musicOn = true
    var hapticsOn = true
    /// Last verified Remove Ads state, for offline launches.
    var ownsRemoveAds = false
    /// yyyy-MM-dd of the last free daily extra jar.
    var freeExtraJarDay: String?
    var hintDay: String?
    var hintsUsedToday = 0
    var freeHintUsed = false
    /// Random id, never linked to a person. Not sent for children.
    var installID = UUID().uuidString
    var favouriteSquishy: String?

    static func today(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

final class ProgressStore {
    private let url: URL

    init(fileName: String = "progress.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(fileName)
    }

    func load() -> PlayerProgress {
        guard let data = try? Data(contentsOf: url),
              let p = try? JSONDecoder().decode(PlayerProgress.self, from: data) else { return PlayerProgress() }
        return p
    }

    func save(_ progress: PlayerProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
