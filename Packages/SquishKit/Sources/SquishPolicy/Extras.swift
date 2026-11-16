import Foundation

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
    public static func isUnlocked(_ extra: Extra, capsulesOpened: Int, levelsWon: Int,
                                  firstWorldComplete: Bool, config: GameConfig = GameConfig()) -> Bool {
        switch extra {
        case .squishRoom: return config.squishRoomEnabled && capsulesOpened >= 1
        case .mysteryBag: return config.mysteryBagEnabled && levelsWon >= mysteryBagAfterLevel
        case .maker: return config.makerEnabled && firstWorldComplete
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

    /// Rarer squishies squeak lower.
    public var squeak: Squeak {
        switch answer.rarity {
        case .common: return .high
        case .rare: return .middle
        case .ultra, .secret: return .low
        }
    }

    public static let stepsPerCapsule = 3

    /// The same bag all day for one player. Secrets and locked worlds never appear.
    public static func daily(day: String, playerSeed: String, roster: Roster, worlds: [String]) -> MysteryBag? {
        let pool = roster.collectibles.filter { worlds.contains($0.world) && $0.rarity != .secret }
        guard pool.count >= 4 else { return nil }
        var rng = SplitMix64(seed: stableHash(day + "|" + playerSeed))
        let picked = Array(pool.shuffled(using: &rng).prefix(4))
        let answer = picked[Int(rng.next() % 4)]
        return MysteryBag(answer: answer, choices: picked)
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

    public init() {}

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

    public init(id: String, name: String = "", shape: Shape = .bun, color: Int = 0, eyes: Eyes = .dots,
                mouth: Mouth = .smile, ears: Ears = .none, accessory: Accessory = .none) {
        self.id = id
        self.name = name
        self.shape = shape
        self.color = color
        self.eyes = eyes
        self.mouth = mouth
        self.ears = ears
        self.accessory = accessory
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

    public static let maxStoredTreats = 3
    public static let heartsPerTreat = 1
    public static let heartsPerGift = 5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        squishy = try c.decodeIfPresent(String.self, forKey: .squishy)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        treats = try c.decodeIfPresent(Int.self, forKey: .treats) ?? 0
        hearts = try c.decodeIfPresent(Int.self, forKey: .hearts) ?? 0
        lastOpenedAt = try c.decodeIfPresent(Double.self, forKey: .lastOpenedAt)
        moodAskedDay = try c.decodeIfPresent(String.self, forKey: .moodAskedDay)
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
        case .hint, .extraJar, .theme: break
        }
    }

    /// Tricks open every 10 hearts. Cosmetic only.
    public var tricksUnlocked: Int { min(BuddyState.tricks, hearts / 10) }
    public static let tricks = 3
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
        if Int(answer.trimmingCharacters(in: .whitespaces)) == a * b { return true }
        lockedUntil = now + ParentalGateState.cooldown
        let old = (a, b)
        repeat {
            a = Int.random(in: 6...9, using: &rng)
            b = Int.random(in: 12...19, using: &rng)
        } while (a, b) == old
        return false
    }
}
