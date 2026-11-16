import Foundation
import SwiftUI
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
    var wallet = CoinWallet()
    /// Apple's tracking prompt has been shown (it's shown at most once).
    var trackingAsked = false
    var ownedThemes: Set<String> = [BoardTheme.cream.rawValue]
    var theme = BoardTheme.cream.rawValue
    /// Santa's Grotto: opened through the festive door (it then stays open for good).
    var christmasEntered = false
    /// Furthest unlocked Christmas level, 0-based within that world.
    var christmasUnlocked = 0
    var advent = AdventState()
    /// Consecutive first-try wins on new levels.
    var winStreak = 0
    /// yyyy-MM-dd of the last win, for the first-win-of-the-day coins.
    var lastWinDay: String?
    /// yyyy-MM-dd the Buddy's daily gift was last taken.
    var dailyGiftDay: String?
    var optInAds = OptInAdState()
    var stampCard = StampCard()
    /// Worlds of capsules already earned but not opened yet. Saved, so a capsule
    /// is never lost if the app closes before its turn on screen.
    var pendingCapsules: [String] = []
    /// The one soft Remove Ads line on the win card has been shown.
    var removeAdsOfferShown = false
    var buddy = BuddyState()
    var mystery = MysteryState()
    /// Squishies built in the Maker. They live in the Squish Room and as a Buddy only.
    var made: [MadeSquishy] = []
    /// Extras whose "new!" badge has been tapped away.
    var seenExtras: Set<String> = []
    /// Apple's rating prompt has been requested (it's asked for once).
    var ratingAsked = false

    init() {}

    /// Every field is optional on disk, so adding fields never loses a player's progress.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayerProgress()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback }
        version = v(.version, d.version)
        stars = v(.stars, d.stars)
        highestUnlocked = v(.highestUnlocked, d.highestUnlocked)
        collection = v(.collection, d.collection)
        age = (try? c.decodeIfPresent(AgeProfile.self, forKey: .age)) ?? nil
        cadence = v(.cadence, d.cadence)
        soundOn = v(.soundOn, d.soundOn)
        musicOn = v(.musicOn, d.musicOn)
        hapticsOn = v(.hapticsOn, d.hapticsOn)
        ownsRemoveAds = v(.ownsRemoveAds, d.ownsRemoveAds)
        freeExtraJarDay = (try? c.decodeIfPresent(String.self, forKey: .freeExtraJarDay)) ?? nil
        hintDay = (try? c.decodeIfPresent(String.self, forKey: .hintDay)) ?? nil
        hintsUsedToday = v(.hintsUsedToday, d.hintsUsedToday)
        freeHintUsed = v(.freeHintUsed, d.freeHintUsed)
        installID = v(.installID, d.installID)
        favouriteSquishy = (try? c.decodeIfPresent(String.self, forKey: .favouriteSquishy)) ?? nil
        wallet = v(.wallet, d.wallet)
        trackingAsked = v(.trackingAsked, d.trackingAsked)
        ownedThemes = v(.ownedThemes, d.ownedThemes)
        theme = v(.theme, d.theme)
        christmasEntered = v(.christmasEntered, d.christmasEntered)
        christmasUnlocked = v(.christmasUnlocked, d.christmasUnlocked)
        advent = v(.advent, d.advent)
        winStreak = v(.winStreak, d.winStreak)
        lastWinDay = (try? c.decodeIfPresent(String.self, forKey: .lastWinDay)) ?? nil
        dailyGiftDay = (try? c.decodeIfPresent(String.self, forKey: .dailyGiftDay)) ?? nil
        optInAds = v(.optInAds, d.optInAds)
        stampCard = v(.stampCard, d.stampCard)
        pendingCapsules = v(.pendingCapsules, d.pendingCapsules)
        removeAdsOfferShown = v(.removeAdsOfferShown, d.removeAdsOfferShown)
        buddy = v(.buddy, d.buddy)
        mystery = v(.mystery, d.mystery)
        made = v(.made, d.made)
        seenExtras = v(.seenExtras, d.seenExtras)
        ratingAsked = v(.ratingAsked, d.ratingAsked)
    }

    static func today(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

/// Cosmetic board backgrounds, bought with coins.
enum BoardTheme: String, CaseIterable, Identifiable {
    case cream, mint, sky, bubblegum, night

    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .cream: return [Color(red: 1, green: 0.957, blue: 0.91), Color(red: 1, green: 0.92, blue: 0.85)]
        case .mint: return [Color(red: 0.85, green: 0.98, blue: 0.93), Color(red: 0.7, green: 0.93, blue: 0.85)]
        case .sky: return [Color(red: 0.87, green: 0.94, blue: 1), Color(red: 0.74, green: 0.87, blue: 1)]
        case .bubblegum: return [Color(red: 1, green: 0.9, blue: 0.95), Color(red: 1, green: 0.78, blue: 0.88)]
        case .night: return [Color(red: 0.25, green: 0.2, blue: 0.38), Color(red: 0.14, green: 0.11, blue: 0.24)]
        }
    }

    var name: LocalizedStringKey {
        switch self {
        case .cream: return "Cream"
        case .mint: return "Mint Fizz"
        case .sky: return "Blue Sky"
        case .bubblegum: return "Bubblegum"
        case .night: return "Night"
        }
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
        guard let data = try? Data(contentsOf: url) else { return PlayerProgress() }
        if let p = try? JSONDecoder().decode(PlayerProgress.self, from: data) { return p }
        // Unreadable save: keep it for support instead of letting the next save overwrite it.
        let stamp = PlayerProgress.today() + "-" + String(Int(Date().timeIntervalSince1970))
        let backup = url.deletingLastPathComponent().appendingPathComponent("progress.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        return PlayerProgress()
    }

    func save(_ progress: PlayerProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
