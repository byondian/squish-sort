import Foundation
import SquishWorkshop

/// The extras around the sort game (design doc, "Extras and unlock order").
/// Each one appears as a quiet home button when it unlocks and never pops up.
public enum Extra: String, Codable, CaseIterable, Sendable {
    case squishRoom, mysteryBag, maker, buddy
}

public enum Extras {
    public static let mysteryBagAfterLevel = 10

    /// - Parameters:
    ///   - capsulesOpened: capsules opened so far, any world.
    ///   - levelsWon: how many levels of the play order are finished.
    ///   - firstWorldComplete: every level of the first world is finished.
    ///   - ownsRemoveAds: Remove Ads includes Workshop Pro, so its owner has the Workshop at once.
    public static func isUnlocked(_ extra: Extra, capsulesOpened: Int, levelsWon: Int,
                                  firstWorldComplete: Bool, ownsRemoveAds: Bool = false,
                                  config: GameConfig = GameConfig()) -> Bool {
        switch extra {
        case .squishRoom: return config.squishRoomEnabled && capsulesOpened >= 1
        case .mysteryBag: return config.mysteryBagEnabled && levelsWon >= mysteryBagAfterLevel
        // The Squishy Workshop arrives with the first capsule, next to the Squish Room.
        case .maker: return config.makerEnabled && (capsulesOpened >= 1 || ownsRemoveAds)
        case .buddy: return config.buddyEnabled && capsulesOpened >= 1
        }
    }
}

/// The website's Squishy Shop: affiliate listings of real squishy toys.
/// The app only links to it. Nothing is sold in the app, and the link is for
/// players of 13 and over (14 in Korea) with a known age: never gentle mode.
public enum SquishyShop {
    public static let url = "https://squishsort.app/shop"

    public static func isVisible(profile: AgeProfile?, storefront: String, config: GameConfig = GameConfig()) -> Bool {
        config.squishyShopEnabled && AgePolicy.group(of: profile, storefront: storefront) != .child
    }
}

// MARK: - Santa's Grotto (side world)

/// A side world behind a festive door on the home screen. The door shows once
/// level 10 is won and the date is inside the window. A player who has opened
/// it keeps the world for good; for everyone else the door just isn't there
/// after the window. No countdown and no "last chance" anywhere.
public enum ChristmasWorld {
    public static let id = "christmas"
    public static let doorAfterLevel = 10

    public static func doorShows(today: String, levelTenWon: Bool, entered: Bool, config: GameConfig = GameConfig()) -> Bool {
        entered || (levelTenWon && config.isChristmasWindow(today: today))
    }
}

/// Advent shelf: 24 doors with fixed rewards. Every door up to today's date can
/// be opened once, so missed days are caught up. No ad, no streak, no notification.
public enum Advent {
    public static let doors = 24

    public enum Reward: Equatable, Sendable {
        case coins(Int)
        case treats(Int)
        /// One step on the capsule bar (the same bar as the Mystery Bag).
        case capsuleStep
        case christmasCapsule
    }

    public static func reward(day: Int, rules: CoinRules = CoinRules()) -> Reward {
        switch day {
        case 24: return .christmasCapsule
        case 6, 12, 18: return .capsuleStep
        default: return day % 2 == 1 ? .coins(rules.adventCoins) : .treats(2)
        }
    }

    /// How many doors can be open today: 0 outside the window, the day of the
    /// month in the opening month, and all 24 after it until the window ends.
    public static func doorsAvailable(today: String, config: GameConfig = GameConfig()) -> Int {
        guard config.isChristmasWindow(today: today), today.count == 10, config.christmasOpenFrom.count == 10 else { return 0 }
        guard today.prefix(7) == config.christmasOpenFrom.prefix(7) else { return doors }
        guard let day = Int(today.suffix(2)), let first = Int(config.christmasOpenFrom.suffix(2)) else { return 0 }
        return min(doors, max(0, day - first + 1))
    }
}

public struct AdventState: Codable, Equatable, Sendable {
    public var opened: Set<Int> = []
    /// The season the opened doors belong to (the window's first day), so next
    /// December starts with 24 closed doors.
    public var season: String?

    public init() {}

    public func openedDoors(season: String) -> Set<Int> { self.season == season ? opened : [] }

    /// Opens a door once. False when it is already open or not yet available.
    public mutating func open(day: Int, available: Int, season: String = GameConfig().christmasOpenFrom) -> Bool {
        if self.season != season {
            opened = []
            self.season = season
        }
        guard (1...Advent.doors).contains(day), day <= available, !opened.contains(day) else { return false }
        opened.insert(day)
        return true
    }
}

// MARK: - Mystery Bag

/// Daily guessing game: three clues, pick 1 of 4. No purchase and no ad anywhere.
public struct MysteryBag: Equatable, Sendable {
    public enum Squeak: String, Sendable { case high, middle, low }

    public let answer: Collectible
    /// Four squishies in a stable shuffled order; one is the answer.
    public let choices: [Collectible]
    /// How far the toy is turned inside the bag today, in degrees.
    public let turn: Double

    /// Rarer squishies squeak lower.
    public var squeak: Squeak {
        switch answer.rarity {
        case .common: return .high
        case .rare: return .middle
        case .ultra, .secret: return .low
        }
    }

    public static let stepsPerCapsule = 3
    /// The first days after the bag opens are easy: the choices all look different.
    public static let easyDays = 3
    /// Coins for a guess, by clues used: fewer clues, bigger prize. Every guess pays.
    public static let prizes = [150, 100, 75, 50]

    public static func prize(cluesUsed: Int) -> Int { prizes[min(max(0, cluesUsed), prizes.count - 1)] }
    /// A wrong guess pays the smallest prize whatever the clues, so guessing blind never beats thinking.
    public static func prize(cluesUsed: Int, correct: Bool) -> Int { correct ? prize(cluesUsed: cluesUsed) : prizes[prizes.count - 1] }

    /// The same answer all day for one player. Secrets and locked worlds never appear.
    /// Once the easy days are over (`easy` false) and `shapes` is given, at least two of the other
    /// choices have the answer's body shape, so the shape clue alone never decides it. The other
    /// choices come from squishies the player has `seen` wherever there are enough of them.
    public static func daily(day: String, playerSeed: String, roster: Roster, worlds: [String],
                             shapes: [String: String] = [:], seen: Set<String> = [], easy: Bool = true) -> MysteryBag? {
        let pool = roster.collectibles.filter { worlds.contains($0.world) && $0.rarity != .secret }
        guard pool.count >= 4 else { return nil }
        var rng = SplitMix64(seed: stableHash(day + "|" + playerSeed))
        let shuffled = pool.shuffled(using: &rng)
        if easy || shapes.isEmpty {
            let picked = Array(shuffled.prefix(4))
            let answer = picked[Int(rng.next() % 4)]
            return MysteryBag(answer: answer, choices: picked, turn: Double(rng.next() % 360))
        }
        let answer = shuffled[0]
        let others = Array(shuffled.dropFirst())
        let shape = shapes[answer.id]
        let alike = others.filter { shape != nil && shapes[$0.id] == shape }
        var decoys: [Collectible] = []
        func take(_ from: [Collectible], upTo n: Int) {
            for c in from where decoys.count < n && !decoys.contains(c) { decoys.append(c) }
        }
        take(alike.filter { seen.contains($0.id) }, upTo: 2)
        take(alike, upTo: 2)
        take(others.filter { seen.contains($0.id) }, upTo: 3)
        take(others, upTo: 3)
        let choices = ([answer] + decoys).shuffled(using: &rng)
        return MysteryBag(answer: answer, choices: choices, turn: Double(rng.next() % 360))
    }

    /// FNV-1a: the same on every launch, unlike `hashValue`.
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return h
    }
}

public struct MysteryState: Codable, Equatable, Sendable {
    public var lastPlayedDay: String?
    /// Right guesses towards the next free capsule.
    public var steps = 0
    /// The day of the last wrong guess, and of the last extra guess taken.
    public var wrongDay: String?
    public var extraGuessDay: String?
    /// Days with a guess so far. Missing in older saves, which have played before.
    public var daysPlayed: Int?

    public init() {}

    /// The first few days are easy. Judged on the days before `today`, so the bag does not
    /// change in the middle of a day.
    public func isLearning(today: String) -> Bool {
        let played = daysPlayed ?? (lastPlayedDay == nil && wrongDay == nil ? 0 : MysteryBag.easyDays)
        let todays = (lastPlayedDay == today || wrongDay == today) ? 1 : 0
        return played - todays < MysteryBag.easyDays
    }

    public func canPlay(today: String) -> Bool { lastPlayedDay != today }

    /// After a wrong guess: one more guess, once a day (by opt-in ad; the caller checks age).
    public func canOfferExtraGuess(today: String) -> Bool {
        lastPlayedDay == today && wrongDay == today && extraGuessDay != today
    }

    public mutating func grantExtraGuess(today: String) {
        guard canOfferExtraGuess(today: today) else { return }
        extraGuessDay = today
        lastPlayedDay = nil
    }

    /// One step on the capsule bar from somewhere else (an advent door).
    /// Returns true when it fills the bar and earns a capsule.
    public mutating func addStep() -> Bool {
        steps += 1
        if steps >= MysteryBag.stepsPerCapsule {
            steps = 0
            return true
        }
        return false
    }

    /// One guess a day. Returns true when this guess fills the bar and earns a capsule.
    public mutating func recordGuess(correct: Bool, today: String) -> Bool {
        guard canPlay(today: today) else { return false }
        // The extra guess comes from an opt-in ad (or Remove Ads), so it never
        // moves the capsule bar: nothing paid or watched ever leads to a capsule.
        let extraGuess = extraGuessDay == today
        if !extraGuess { daysPlayed = (daysPlayed ?? (lastPlayedDay == nil && wrongDay == nil ? 0 : MysteryBag.easyDays)) + 1 }
        lastPlayedDay = today
        guard correct else {
            wrongDay = today
            return false
        }
        guard !extraGuess else { return false }
        steps += 1
        if steps >= MysteryBag.stepsPerCapsule {
            steps = 0
            return true
        }
        return false
    }
}

// MARK: - Squishy Maker

/// A squishy the player built. It lives in the Squish Room and as a Buddy only:
/// never on boards, never in capsules, never in the collection book.
public struct MadeSquishy: Codable, Equatable, Identifiable, Sendable {
    public enum Shape: String, Codable, CaseIterable, Sendable { case bun, egg, bean, drop, dome, cloud }
    public enum Eyes: String, Codable, CaseIterable, Sendable { case dots, sparkle, sleepy, wink }
    public enum Mouth: String, Codable, CaseIterable, Sendable { case smile, open, cat, tongue }
    public enum Ears: String, Codable, CaseIterable, Sendable { case none, cat, bear, bunny, horns }
    public enum Accessory: String, Codable, CaseIterable, Sendable { case none, bow, crown, headphones, unicornHorn, leaf }

    public var id: String
    public var name: String
    public var shape: Shape
    /// Index into `MakerParts.palette`.
    public var color: Int
    public var eyes: Eyes
    public var mouth: Mouth
    public var ears: Ears
    public var accessory: Accessory
    /// Made in the Squishy Workshop: its full design. Nil for a squishy from the old Maker, which
    /// keeps today's look. Not part of the progress save: each design is a file of its own
    /// (`MadeStore`), because the progress file is rewritten on every change.
    public var design: WorkshopDesign?

    private enum CodingKeys: String, CodingKey { case id, name, shape, color, eyes, mouth, ears, accessory }

    public init(id: String, name: String = "", shape: Shape = .bun, color: Int = 0, eyes: Eyes = .dots,
                mouth: Mouth = .smile, ears: Ears = .none, accessory: Accessory = .none, design: WorkshopDesign? = nil) {
        self.design = design
        self.id = id
        self.name = name
        self.shape = shape
        self.color = color
        self.eyes = eyes
        self.mouth = mouth
        self.ears = ears
        self.accessory = accessory
    }

    /// The Workshop design this squishy has, or the one its old Maker parts turn into, so every
    /// made squishy can be opened in the Workshop.
    public var workshopDesign: WorkshopDesign {
        if let design { return design }
        var d = WorkshopDesign(mould: shape.rawValue)
        let palette = MakerParts.palette
        d.layers = [GooLayer(colour: palette[min(max(0, color), palette.count - 1)])]
        switch eyes {
        case .dots: d.face.eyes = "dots"
        case .sparkle: d.face.eyes = "sparkle"
        case .sleepy: d.face.eyes = "sleepy"
        case .wink: d.face.eyes = "wink"
        }
        switch mouth {
        case .smile: d.face.mouth = "smile"
        case .open: d.face.mouth = "open-o"
        case .cat: d.face.mouth = "cat-w"
        case .tongue: d.face.mouth = "tongue"
        }
        switch ears {
        case .none: break
        case .cat, .bear, .bunny: d.parts.append(Placed(id: "ears", category: "ears", part: ears.rawValue, x: 0.5, y: 0.24))
        case .horns: d.parts.append(Placed(id: "ears", category: "horns-and-antlers", part: "little-horns", x: 0.5, y: 0.24))
        }
        switch accessory {
        case .none: break
        case .bow: d.parts.append(Placed(id: "extra", category: "hats-and-headwear", part: "bow-headband", x: 0.5, y: 0.22))
        case .crown: d.parts.append(Placed(id: "extra", category: "hats-and-headwear", part: "crown", x: 0.5, y: 0.2))
        case .headphones: d.parts.append(Placed(id: "extra", category: "hats-and-headwear", part: "headphones", x: 0.5, y: 0.3))
        // An old save with horns and a unicorn horn keeps the unicorn horn: one from each tray.
        case .unicornHorn: d.parts.append(Placed(id: "extra", category: "horns-and-antlers", part: "unicorn", x: 0.5, y: 0.2))
        case .leaf: d.parts.append(Placed(id: "extra", category: "antennae-and-hair", part: "sprout", x: 0.5, y: 0.2))
        }
        d.tidy()
        return d
    }

    /// How a made squishy is referred to wherever a collectible id could also go.
    public var ref: String { MadeSquishy.refPrefix + id }
    public static let refPrefix = "made:"
}

public enum MakerParts {
    public static let maxMade = 8
    /// RGB hex, Soft Pop palette.
    public static let palette: [UInt32] = [
        0xFF9EB5, 0xFFD86B, 0x7FE0C4, 0x7CC8FF, 0xC9A7F5, 0xFFB37A,
        0xB8E05A, 0xFF7EB6, 0x9AD9E8, 0xF5F0E6, 0x8C7AE6, 0x6B5B7B,
    ]

    /// Basic parts are free; one more of each kind opens with every world completed.
    public static func unlockedCount(total: Int, base: Int, worldsCompleted: Int) -> Int {
        min(total, base + max(0, worldsCompleted))
    }

    public static func shapes(worldsCompleted w: Int) -> Int { unlockedCount(total: MadeSquishy.Shape.allCases.count, base: 2, worldsCompleted: w) }
    public static func colors(worldsCompleted w: Int) -> Int { unlockedCount(total: palette.count, base: 5, worldsCompleted: w * 2) }
    public static func eyes(worldsCompleted w: Int) -> Int { unlockedCount(total: MadeSquishy.Eyes.allCases.count, base: 1, worldsCompleted: w) }
    public static func mouths(worldsCompleted w: Int) -> Int { unlockedCount(total: MadeSquishy.Mouth.allCases.count, base: 1, worldsCompleted: w) }
    public static func ears(worldsCompleted w: Int) -> Int { unlockedCount(total: MadeSquishy.Ears.allCases.count, base: 2, worldsCompleted: w) }
    public static func accessories(worldsCompleted w: Int) -> Int { unlockedCount(total: MadeSquishy.Accessory.allCases.count, base: 2, worldsCompleted: w) }

    /// A design only uses parts the player has unlocked.
    public static func isAllowed(_ m: MadeSquishy, worldsCompleted w: Int) -> Bool {
        func index<T: CaseIterable & Equatable>(_ v: T) -> Int { Array(T.allCases).firstIndex(of: v) ?? 0 }
        return index(m.shape) < shapes(worldsCompleted: w)
            && m.color >= 0 && m.color < colors(worldsCompleted: w)
            && index(m.eyes) < eyes(worldsCompleted: w)
            && index(m.mouth) < mouths(worldsCompleted: w)
            && index(m.ears) < ears(worldsCompleted: w)
            && index(m.accessory) < accessories(worldsCompleted: w)
    }
}

// MARK: - Names

/// Names for a Buddy or a made squishy. Typed by the player, kept on the
/// device only, never sent anywhere in 1.0.
public enum NameFilter {
    public static let maxLength = 12

    /// Trimmed and shortened name, or nil when it's empty or rude.
    public static func clean(_ raw: String) -> String? {
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRude(trimmed) else { return nil }
        return trimmed
    }

    public static func isRude(_ text: String) -> Bool {
        // Accents are folded for Latin text ("shït"). The unfolded text is checked
        // too, because folding also strips Japanese voicing marks.
        let plain = text.lowercased()
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil).lowercased()
        return isRudeNormalised(plain) || isRudeNormalised(folded)
    }

    private static func isRudeNormalised(_ text: String) -> Bool {
        var words: [String] = []
        var word = ""
        for ch in text {
            if let swap = leet[ch] {
                word.append(swap)
            } else if ch.isLetter {
                word.append(ch)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        // Strong words count anywhere inside a word ("Sh1tface").
        if words.contains(where: { w in insideAWord.contains(where: { w.contains($0) }) }) { return true }
        // Spelt out with gaps ("s h i t"): only when every piece is a single letter,
        // so "Super Ape" and "Bass Hole" are left alone.
        if words.count > 1, words.allSatisfy({ $0.count == 1 }) {
            let joined = words.joined()
            if insideAWord.contains(where: { joined.contains($0) }) || wholeWord.contains(joined) { return true }
        }
        // The rest only count as a whole word, so "Grapey", "Skittle" and "Cocoa" are fine.
        return words.contains(where: { wholeWord.contains($0) })
    }

    private static let leet: [Character: Character] = ["0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i"]

    private static let insideAWord: [String] = [
        "fuck", "shit", "bitch", "cunt", "nigg", "whore", "slut", "penis", "vagina", "pussy",
        "bastard", "hitler", "asshole", "arsehole", "retard", "suicide",
        // ja / ko / zh-Hant basics.
        "くそ", "ばか", "しね", "死ね", "ちんこ", "まんこ", "씨발", "시발", "병신", "개새끼", "좆", "幹你", "操你", "他媽", "白癡", "去死",
    ]

    private static let wholeWord: Set<String> = [
        "ass", "arse", "cock", "cum", "sex", "tit", "tits", "piss", "poo", "crap", "damn", "hell", "die", "sexy", "anal", "anus",
        "rape", "kill", "wank", "wanker", "dick", "fag", "twat", "porn", "boob", "boobs", "nazi",
    ]
}

// MARK: - Squishy Buddy

/// Something the Buddy keeps and wears: a hat, something round its neck or something to hold.
/// Bought with coins, chosen by the player at a price that is shown: never a lucky dip.
/// Just for fun: a gift changes how the Buddy looks and nothing else in the game.
public struct BuddyGift: Equatable, Hashable, Identifiable, Sendable {
    /// The Workshop tray its picture comes from; the Buddy wears one thing from each.
    public let category: String
    public let part: String
    public let price: Int

    public var id: String { category + "/" + part }
}

public enum BuddyGifts {
    public static let hats = "hats-and-headwear"
    public static let neck = "neck-and-body"
    public static let held = "held-items"
    public static let categories = [hats, neck, held]

    public static let all: [BuddyGift] = [
        (hats, "party-hat", 300), (hats, "beanie", 400), (hats, "cap", 400), (hats, "bow-headband", 500),
        (hats, "beret", 600), (hats, "flower-crown", 700), (hats, "cowboy", 800), (hats, "chef", 800),
        (hats, "pirate", 900), (hats, "headphones", 1000), (hats, "wizard-hat", 1200), (hats, "top-hat", 1500),
        (hats, "tiara", 2000), (hats, "crown", 3000),
        (neck, "bow-tie", 300), (neck, "scarf", 400), (neck, "bandana", 500), (neck, "bell-collar", 600),
        (neck, "medal", 1000), (neck, "pearl-necklace", 1500), (neck, "cape", 2000),
        (held, "lollipop", 300), (held, "flower", 400), (held, "balloon", 500), (held, "ice-cream", 600),
        (held, "teddy", 900), (held, "wand", 1200), (held, "guitar", 1800),
    ].map { BuddyGift(category: $0.0, part: $0.1, price: $0.2) }

    /// The Keep Squishing milestone shelf: one for every tenth Keep Squishing level, in this order.
    /// They are prizes for playing and are never in the shop: no price, no coins, no ad.
    public static let milestones: [BuddyGift] = [
        (hats, "sweatband"), (held, "flag"), (neck, "tie"), (hats, "bowler"), (held, "book"), (hats, "sailor"),
        (neck, "bib"), (held, "paintbrush"), (hats, "straw-sun-hat"), (held, "ice-lolly"), (neck, "lei"), (hats, "frog-hood"),
        (held, "umbrella"), (hats, "helmet"), (held, "controller"), (neck, "backpack"), (hats, "bunny-hood"), (held, "microphone"),
        (hats, "graduation"), (held, "foam-sword"), (neck, "tutu"), (hats, "witch"), (held, "heart-sign"), (hats, "space-helmet"),
    ].map { BuddyGift(category: $0.0, part: $0.1, price: 0) }

    public static func gift(_ id: String) -> BuddyGift? { all.first { $0.id == id } ?? milestones.first { $0.id == id } }

    /// The free daily gift holds one of the small gifts on about one day in three, while there is one
    /// the Buddy does not have yet. Stable for the day, so opening it again changes nothing.
    public static let freeUpTo = 600
    public static let freeOneDayIn = 3
    public static func inDailyGift(day: String, installSeed: String, owned: [String]) -> BuddyGift? {
        guard MysteryBag.stableHash(installSeed + "|gift-day|" + day) % UInt64(freeOneDayIn) == 0 else { return nil }
        let open = all.filter { $0.price <= freeUpTo && !owned.contains($0.id) }
        guard !open.isEmpty else { return nil }
        return open[Int(MysteryBag.stableHash(installSeed + "|gift-pick|" + day) % UInt64(open.count))]
    }
}

/// The Keep Squishing milestone shelf: every tenth Keep Squishing level won for the first time puts a
/// prize on the shelf. First time round each is a wearable for the Buddy that is nowhere else in the
/// game; a milestone whose wearable the Buddy already has (a later lap) gives coins instead.
public enum MilestoneShelf {
    public static let every = 10
    public static let coinsWhenOwned = 300

    /// The shelf place (0 is the first) that Keep Squishing level `index` fills; nil for any other level.
    public static func slot(forLevel index: Int) -> Int? {
        guard index > 0, index % every == 0, !BuddyGifts.milestones.isEmpty else { return nil }
        return (index / every - 1) % BuddyGifts.milestones.count
    }

    public static func gift(slot: Int) -> BuddyGift { BuddyGifts.milestones[slot % BuddyGifts.milestones.count] }

    public enum Prize: Equatable, Sendable {
        case gift(BuddyGift)
        case coins(Int)
    }

    /// What winning Keep Squishing level `index` for the first time puts on the shelf.
    public static func prize(forLevel index: Int, buddy: BuddyState) -> Prize? {
        guard let slot = slot(forLevel: index) else { return nil }
        let wearable = gift(slot: slot)
        return buddy.owns(wearable) ? .coins(coinsWhenOwned) : .gift(wearable)
    }
}

/// A gentle pet. It never gets hungry, sick or sad, and never sends notifications.
public struct BuddyState: Codable, Equatable, Sendable {
    /// A collectible id, or a made squishy's `ref`. Nil until the player picks one.
    public var squishy: String?
    public var name = ""
    /// Free treats from wins, waiting to be fed.
    public var treats = 0
    /// Mood hearts: only ever unlock tricks and expressions.
    public var hearts = 0
    /// Seconds since 1970 of the last app open, for "you're back".
    public var lastOpenedAt: Double?
    /// The day the Buddy last asked "How are you today?". The answer is never stored.
    public var moodAskedDay: String?
    /// Seconds since 1970 of the last treat, for the puff that eases back.
    public var lastTreatAt: Double?
    /// How big the puff was just after the last treat or gift. Missing in older saves: one treat's worth.
    public var puffBase: Double?
    /// Gifts the Buddy has been given (`BuddyGift.id`), oldest first. Kept for good.
    public var gifts: [String] = []
    /// The gifts it has on now: at most one from each tray.
    public var wearing: [String] = []

    public static let maxStoredTreats = 3
    public static let heartsPerTreat = 1
    /// A gift is better value than six treats, and nearly a whole trick.
    public static let heartsPerGift = 8
    /// A gift the Buddy keeps also makes it happy.
    public static let heartsPerKeptGift = 3

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        squishy = try c.decodeIfPresent(String.self, forKey: .squishy)
        lastTreatAt = try? c.decodeIfPresent(Double.self, forKey: .lastTreatAt)
        puffBase = try? c.decodeIfPresent(Double.self, forKey: .puffBase)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        treats = try c.decodeIfPresent(Int.self, forKey: .treats) ?? 0
        hearts = try c.decodeIfPresent(Int.self, forKey: .hearts) ?? 0
        lastOpenedAt = try c.decodeIfPresent(Double.self, forKey: .lastOpenedAt)
        moodAskedDay = try c.decodeIfPresent(String.self, forKey: .moodAskedDay)
        gifts = ((try? c.decodeIfPresent([String].self, forKey: .gifts)) ?? nil) ?? []
        wearing = (((try? c.decodeIfPresent([String].self, forKey: .wearing)) ?? nil) ?? []).filter { gifts.contains($0) }
    }

    public func owns(_ gift: BuddyGift) -> Bool { gifts.contains(gift.id) }
    public func isWearing(_ gift: BuddyGift) -> Bool { wearing.contains(gift.id) }

    /// What the Buddy has on, in the order it is drawn.
    public var worn: [BuddyGift] { wearing.compactMap(BuddyGifts.gift) }

    /// A new gift: kept for good, put on at once, and a few hearts. False when it has it already.
    @discardableResult
    public mutating func receive(_ gift: BuddyGift) -> Bool {
        guard !owns(gift) else { return false }
        gifts.append(gift.id)
        hearts += BuddyState.heartsPerKeptGift
        wear(gift)
        return true
    }

    /// Puts on a gift it owns, in place of whatever it had on from the same tray.
    public mutating func wear(_ gift: BuddyGift) {
        guard owns(gift) else { return }
        wearing.removeAll { BuddyGifts.gift($0)?.category == gift.category || BuddyGifts.gift($0) == nil }
        wearing.append(gift.id)
    }

    public mutating func takeOff(_ gift: BuddyGift) {
        wearing.removeAll { $0 == gift.id }
    }

    /// Every level win gives one free treat, up to three stored.
    public mutating func earnTreatForWin() {
        treats = min(BuddyState.maxStoredTreats, treats + 1)
    }

    /// Feed a stored treat. False when there is none.
    @discardableResult
    public mutating func feedStoredTreat() -> Bool {
        guard treats > 0 else { return false }
        treats -= 1
        hearts += BuddyState.heartsPerTreat
        return true
    }

    /// A treat or gift bought with coins is given straight away.
    public mutating func give(_ item: Coins.Item) {
        switch item {
        case .treat: hearts += BuddyState.heartsPerTreat
        case .gift: hearts += BuddyState.heartsPerGift
        case .hint, .theme, .shuffle: break
        }
    }

    /// Tricks open every 10 hearts. Cosmetic only.
    public var tricksUnlocked: Int { BuddyState.tricksKnown(hearts: hearts) }
    public static let tricks = 3
    public static let heartsPerTrick = 10

    public static func tricksKnown(hearts: Int) -> Int { min(tricks, max(0, hearts) / heartsPerTrick) }

    /// Hearts still needed for the next trick, or nil when every trick is known.
    public var heartsToNextTrick: Int? {
        tricksUnlocked < BuddyState.tricks ? BuddyState.heartsPerTrick - hearts % BuddyState.heartsPerTrick : nil
    }

    /// How far round the heart ring is, 0 to 1. Full once every trick is known.
    public var trickProgress: Double {
        heartsToNextTrick == nil ? 1 : Double(hearts % BuddyState.heartsPerTrick) / Double(BuddyState.heartsPerTrick)
    }

    /// The Buddy grows for good through five sizes, and every heart on the way makes it a little
    /// bigger: Small at 5 hearts, Big at 20, Huge at 40 and Giant at 60. It never shrinks.
    /// (Up to 20 hearts this is the 2% a heart of earlier builds, so no saved Buddy gets smaller.)
    public enum Size: Int, CaseIterable, Sendable {
        case tiny, small, big, huge, giant

        /// Hearts that reach this size.
        public var hearts: Int { [0, 5, 20, 40, 60][rawValue] }
        /// How much bigger than a new Buddy this size is.
        public var growth: Double { [0, 0.10, 0.40, 0.50, 0.60][rawValue] }
        public var next: Size? { Size(rawValue: rawValue + 1) }
    }

    public static let maxGrowth = Size.giant.growth

    public static func size(hearts: Int) -> Size {
        Size.allCases.last { hearts >= $0.hearts } ?? .tiny
    }

    /// 0 to 1 of the way from this size to the next. 1 once Giant.
    public static func sizeProgress(hearts: Int) -> Double {
        let size = size(hearts: hearts)
        guard let next = size.next else { return 1 }
        return Double(max(0, hearts) - size.hearts) / Double(next.hearts - size.hearts)
    }

    public static func growth(hearts: Int) -> Double {
        let size = size(hearts: hearts)
        guard let next = size.next else { return maxGrowth }
        return size.growth + (next.growth - size.growth) * sizeProgress(hearts: hearts)
    }

    public var size: Size { BuddyState.size(hearts: hearts) }
    public var sizeProgress: Double { BuddyState.sizeProgress(hearts: hearts) }
    public var growth: Double { BuddyState.growth(hearts: hearts) }

    /// A treat also puffs the Buddy up by 15% on top, easing back over a day to the size it has
    /// earned for good. Nothing earned is ever lost, and nothing is shown when the puff is gone.
    /// Treats stack: each one adds to whatever puff is left, so the Buddy visibly grows on every
    /// treat even when it is fully grown, up to `maxPuff`. A gift fills the puff in one go.
    public static let puffSize = 0.15
    public static let puffStep = 0.05
    public static let maxPuff = 0.25
    public static let puffSeconds = 86_400.0
    /// Gentle mode: a short happy reaction, never something to come back in time for.
    public static let puffSecondsGentle = 60.0
    public func puff(at now: Double, lasting seconds: Double = BuddyState.puffSeconds) -> Double {
        guard let fed = lastTreatAt, now >= fed, seconds > 0 else { return 0 }
        return (puffBase ?? BuddyState.puffSize) * max(0, 1 - (now - fed) / seconds)
    }

    /// A treat or gift has just been eaten: the puff grows from where it is now.
    public mutating func puffUp(_ item: Coins.Item = .treat, at now: Double, lasting seconds: Double = BuddyState.puffSeconds) {
        let left = puff(at: now, lasting: seconds)
        let next = item == .gift ? BuddyState.maxPuff : max(BuddyState.puffSize, left + BuddyState.puffStep)
        puffBase = min(BuddyState.maxPuff, next)
        lastTreatAt = now
    }
}

public struct BuddyLine: Codable, Equatable, Sendable {
    public var id: String
    public var trigger: String
    public var text: [String: String]
    /// When set, the line is only used in these languages.
    public var locales: [String]?
}

/// The pre-written, translated line bank. No AI and no player text.
public struct BuddyScript: Codable, Sendable {
    public struct Rules: Codable, Sendable {
        public var jokeOrFactChancePerVisit = 0.25
        public var greetBackAfterHours = 24.0
        public var askMoodMaxPerDay = 1

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            jokeOrFactChancePerVisit = try c.decodeIfPresent(Double.self, forKey: .jokeOrFactChancePerVisit) ?? 0.25
            greetBackAfterHours = try c.decodeIfPresent(Double.self, forKey: .greetBackAfterHours) ?? 24
            askMoodMaxPerDay = try c.decodeIfPresent(Int.self, forKey: .askMoodMaxPerDay) ?? 1
        }
    }

    public var rules = Rules()
    public var lines: [BuddyLine] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent(Rules.self, forKey: .rules) ?? Rules()
        lines = try c.decodeIfPresent([BuddyLine].self, forKey: .lines) ?? []
    }

    public static func decode(_ data: Data) throws -> BuddyScript {
        try JSONDecoder().decode(BuddyScript.self, from: data)
    }

    /// A random line for the trigger in the player's language, falling back to English.
    public func line<R: RandomNumberGenerator>(_ trigger: String, language: String, using rng: inout R) -> String? {
        let usable = lines.filter { $0.trigger == trigger && ($0.locales?.contains(language) ?? true) }
        guard let line = usable.randomElement(using: &rng) else { return nil }
        return line.text[language] ?? line.text["en"]
    }

    /// Greeting for an app open: "you're back" after a day away, else by time of day.
    public func greetTrigger(hour: Int, hoursSinceLastOpen: Double?) -> String {
        if let away = hoursSinceLastOpen, away >= rules.greetBackAfterHours { return "greet_back" }
        switch hour {
        case 5...11: return "greet_morning"
        case 12...17: return "greet_afternoon"
        case 18...21: return "greet_evening"
        default: return "greet_night"
        }
    }

    public enum HomeLine: Equatable, Sendable {
        case say(trigger: String)
        case askMood
        case quiet
    }

    /// At most one unprompted line per home visit. `roll` is 0..<1.
    public func homeLine(firstVisitThisSession: Bool, hour: Int, hoursSinceLastOpen: Double?,
                         moodAskedToday: Bool, roll: Double) -> HomeLine {
        if firstVisitThisSession {
            return .say(trigger: greetTrigger(hour: hour, hoursSinceLastOpen: hoursSinceLastOpen))
        }
        let chance = rules.jokeOrFactChancePerVisit
        if roll < chance { return .say(trigger: roll < chance / 2 ? "joke" : "fact") }
        if !moodAskedToday && rules.askMoodMaxPerDay > 0 && roll < chance * 2 { return .askMood }
        return .quiet
    }
}

// MARK: - Parental gate

/// "Ask a grown-up": a typed answer to a multiplication, one try per question,
/// and a pause after a wrong answer so it can't be passed by guessing.
public struct ParentalGateState: Equatable, Sendable {
    public static let cooldown: Double = 10

    public private(set) var a: Int
    public private(set) var b: Int
    /// Seconds since 1970 until which answers are refused.
    public private(set) var lockedUntil: Double = 0

    /// `lockedUntil` carries a cooldown over from a gate that was closed and reopened.
    public init<R: RandomNumberGenerator>(using rng: inout R, lockedUntil: Double = 0) {
        a = Int.random(in: 6...9, using: &rng)
        b = Int.random(in: 12...19, using: &rng)
        self.lockedUntil = lockedUntil
    }

    public func isLocked(now: Double) -> Bool { now < lockedUntil }

    public func secondsLeft(now: Double) -> Int { max(0, Int((lockedUntil - now).rounded(.up))) }

    /// True only for the right answer outside a cooldown. A wrong answer starts
    /// the cooldown and swaps in a new question.
    public mutating func submit<R: RandomNumberGenerator>(_ answer: String, now: Double, using rng: inout R) -> Bool {
        guard !isLocked(now: now) else { return false }
        // Only the digits count: a keyboard may add a space, a full stop or digits from another script.
        let digits = answer.compactMap { $0.wholeNumberValue }
        if !digits.isEmpty, digits.count <= 6, digits.reduce(0, { $0 * 10 + $1 }) == a * b { return true }
        lockedUntil = now + ParentalGateState.cooldown
        let old = (a, b)
        repeat {
            a = Int.random(in: 6...9, using: &rng)
            b = Int.random(in: 12...19, using: &rng)
        } while (a, b) == old
        return false
    }
}
