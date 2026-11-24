import Foundation
import SwiftUI
import SquishPolicy

/// Everything the player has, in one Codable file with atomic writes.
/// Collectible ids are stable so the January accounts update can migrate them.
struct PlayerProgress: Codable, Equatable {
    /// 2 since the worlds became 15, 20 and 25 levels long (build 3).
    var version = 3
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
    /// Sliders in Settings, 0 to 1. Zero counts as off (ads start muted).
    var soundLevel = 1.0
    var musicLevel = 1.0
    /// The close squish sounds of a soft squishy, and the Buddy's own noises.
    var squishSoundsOn = true
    var buddyVoiceOn = true
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
    /// Star jar prizes already given, by world: 0 to 3.
    var starJarPrizes: [String: Int] = [:]
    /// Squishies whose card has been opened: the others wear a NEW badge on the Collection page.
    var seenCards: Set<String> = []
    /// Set goals already paid, as "world.goal".
    var setGoalsClaimed: Set<String> = []
    /// The long boss splash has been seen once: after that a tap skips it.
    var bossSplashSeen = false
    /// Board rules whose demo has been shown (wrapped, duet, frozen).
    var rulesShown: Set<String> = []
    /// Sneak peeks of a world's big show already watched, by world: 0 up to the number it has.
    var teasersSeen: [String: Int] = [:]
    /// Worlds whose big show has been watched to the end (or skipped), and the keepsakes they gave.
    var finalesSeen: Set<String> = []
    var keepsakes: Set<String> = []
    /// Times Keep Squishing has been played all the way through.
    var endlessLaps = 0
    /// Levels won in the fewest moves there are, with no extra jar: a gold fourth star on the map.
    var goldStars: Set<String> = []
    /// yyyy-MM-dd of the last Daily Jar won.
    var dailyJarDay: String?
    /// Twist of the week: boards played this week, boards ever won and the sticker card.
    var weekly = WeeklyState()
    /// Places on the Workshop shelf: three are free, more are bought with coins.
    var makerSlots = MakerSlots.free
    /// Workshop wearables bought one at a time with coins, as "tray/part".
    var workshopParts: Set<String> = []
    var piggy = PiggyBank()
    var starterPackOwned = false
    /// The one soft starter pack card (after the first world) has been shown.
    var starterCardShown = false
    /// Hints from the starter pack, used when there is no free one.
    var hintTokens = 0
    /// Magic moves waiting to be used: the game plays the best next move. Earned by streaks and bosses.
    var magicMoves = 0

    init() {}

    /// Saves from before the worlds changed length (every world had 20 levels) point at the old
    /// place on the path. Finds the same level by its id; a level that is gone moves on to the
    /// start of the next world, and its stars are dropped.
    /// - Parameter path: ids of the main path as it is now, in play order.
    mutating func migrate(path: [String], oldWorlds: [String] = ["toyshop", "sweetfactory", "starlight"], oldLength: Int = 20) {
        guard version < 2 else { return }
        version = 2
        guard !path.isEmpty else { return }
        let world = oldWorlds[min(max(0, highestUnlocked / oldLength), oldWorlds.count - 1)]
        let number = highestUnlocked % oldLength + 1
        func levelID(_ world: String, _ number: Int) -> String {
            let digits: String = number < 10 ? "0\(number)" : "\(number)"
            return "\(world)-\(digits)"
        }
        let id: String = levelID(world, number)
        if let same = path.firstIndex(of: id) {
            highestUnlocked = same
        } else if let w = oldWorlds.firstIndex(of: world), w + 1 < oldWorlds.count,
                  let next = path.firstIndex(where: { $0.hasPrefix(oldWorlds[w + 1] + "-") }) {
            highestUnlocked = next
        } else {
            highestUnlocked = path.count - 1
        }
        for old in oldWorlds {
            for n in 1...oldLength {
                let gone: String = levelID(old, n)
                if !path.contains(gone) { stars[gone] = nil }
            }
        }
    }

    /// Saves from before Bubble Bath and Jungle Jam joined the path (story levels ended at 60, then
    /// Keep Squishing). Anyone who was past Starlight Stage starts the new worlds at Bubble Bath 1:
    /// their Keep Squishing stars are kept and those levels open again after Jungle Jam.
    /// - Parameter path: ids of the story levels as they are now, in play order.
    mutating func migrateNewWorlds(path: [String], oldStoryCount: Int = 60) {
        guard version < 3 else { return }
        version = 3
        guard highestUnlocked >= oldStoryCount, let first = path.firstIndex(of: "bubblebath-01") else { return }
        highestUnlocked = first
    }

    /// Every field is optional on disk, so adding fields never loses a player's progress.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayerProgress()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback }
        version = v(.version, 1)
        stars = v(.stars, d.stars)
        highestUnlocked = v(.highestUnlocked, d.highestUnlocked)
        collection = v(.collection, d.collection)
        age = (try? c.decodeIfPresent(AgeProfile.self, forKey: .age)) ?? nil
        cadence = v(.cadence, d.cadence)
        soundOn = v(.soundOn, d.soundOn)
        musicOn = v(.musicOn, d.musicOn)
        hapticsOn = v(.hapticsOn, d.hapticsOn)
        soundLevel = min(1, max(0, v(.soundLevel, d.soundLevel)))
        musicLevel = min(1, max(0, v(.musicLevel, d.musicLevel)))
        squishSoundsOn = v(.squishSoundsOn, d.squishSoundsOn)
        buddyVoiceOn = v(.buddyVoiceOn, d.buddyVoiceOn)
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
        starJarPrizes = v(.starJarPrizes, d.starJarPrizes)
        // A save from before the Collection page: what is already owned is not suddenly new.
        seenCards = v(.seenCards, Set(collection.owned.keys))
        setGoalsClaimed = v(.setGoalsClaimed, d.setGoalsClaimed)
        bossSplashSeen = v(.bossSplashSeen, d.bossSplashSeen)
        rulesShown = v(.rulesShown, d.rulesShown)
        teasersSeen = v(.teasersSeen, d.teasersSeen)
        finalesSeen = v(.finalesSeen, d.finalesSeen)
        keepsakes = v(.keepsakes, d.keepsakes)
        endlessLaps = max(0, v(.endlessLaps, d.endlessLaps))
        goldStars = v(.goldStars, d.goldStars)
        dailyJarDay = (try? c.decodeIfPresent(String.self, forKey: .dailyJarDay)) ?? nil
        weekly = v(.weekly, d.weekly)
        // A save from before places had a price keeps a place for everything it already made.
        makerSlots = max(MakerSlots.free, v(.makerSlots, MakerSlots.starting(alreadyMade: made.count)))
        workshopParts = v(.workshopParts, d.workshopParts)
        piggy = v(.piggy, d.piggy)
        starterPackOwned = v(.starterPackOwned, d.starterPackOwned)
        starterCardShown = v(.starterCardShown, d.starterCardShown)
        hintTokens = max(0, v(.hintTokens, d.hintTokens))
        magicMoves = min(Coins.maxMagicMoves, max(0, v(.magicMoves, d.magicMoves)))
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
    /// Only in the starter pack: never sold for coins.
    case gold

    /// Themes the shop sells for coins.
    static var forCoins: [BoardTheme] { allCases.filter { $0 != .gold } }

    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .cream: return [Color(red: 1, green: 0.957, blue: 0.91), Color(red: 1, green: 0.92, blue: 0.85)]
        case .mint: return [Color(red: 0.85, green: 0.98, blue: 0.93), Color(red: 0.7, green: 0.93, blue: 0.85)]
        case .sky: return [Color(red: 0.87, green: 0.94, blue: 1), Color(red: 0.74, green: 0.87, blue: 1)]
        case .bubblegum: return [Color(red: 1, green: 0.9, blue: 0.95), Color(red: 1, green: 0.78, blue: 0.88)]
        case .night: return [Color(red: 0.25, green: 0.2, blue: 0.38), Color(red: 0.14, green: 0.11, blue: 0.24)]
        case .gold: return [Color(red: 1, green: 0.95, blue: 0.74), Color(red: 1, green: 0.82, blue: 0.45)]
        }
    }

    var name: LocalizedStringKey {
        switch self {
        case .cream: return "Cream"
        case .mint: return "Mint Fizz"
        case .sky: return "Blue Sky"
        case .bubblegum: return "Bubblegum"
        case .night: return "Night"
        case .gold: return "Golden Hour"
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
