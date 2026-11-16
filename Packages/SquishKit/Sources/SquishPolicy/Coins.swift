import Foundation

/// Coin amounts (rules approved 16 Nov 2026). Remote config can change the numbers.
public struct CoinRules: Codable, Equatable, Sendable {
    public var winBase = 50
    public var threeStarBonus = 50
    /// Two jars completed within `doublePopSeconds`.
    public var doublePop = 10
    public var doublePopSeconds: Double = 3
    public var lucky = 100
    public var luckyFromLevel = 10
    /// About one first-clear level in this many has a lucky squishy.
    public var luckyOneIn = 5
    public var firstWinOfDay = 50
    public var mysteryGuess = 50
    public var streakStep = 10
    public var streakCap = 50
    public var dailyGift = 200
    public var adventCoins = 100
    /// Paid once when every level of a world is finished.
    public var worldComplete = 500
    /// Coins for stamps 1 to 6 of the stamp card (the 7th moves the capsule bar).
    public var stampCoins = [50, 50, 100, 100, 150, 150]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CoinRules()
        func int(_ key: CodingKeys, _ fallback: Int) -> Int { max(0, ((try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil) ?? fallback) }
        winBase = int(.winBase, d.winBase)
        threeStarBonus = int(.threeStarBonus, d.threeStarBonus)
        doublePop = int(.doublePop, d.doublePop)
        doublePopSeconds = ((try? c.decodeIfPresent(Double.self, forKey: .doublePopSeconds)) ?? nil) ?? d.doublePopSeconds
        lucky = int(.lucky, d.lucky)
        luckyFromLevel = int(.luckyFromLevel, d.luckyFromLevel)
        luckyOneIn = int(.luckyOneIn, d.luckyOneIn)
        firstWinOfDay = int(.firstWinOfDay, d.firstWinOfDay)
        mysteryGuess = int(.mysteryGuess, d.mysteryGuess)
        streakStep = int(.streakStep, d.streakStep)
        streakCap = int(.streakCap, d.streakCap)
        dailyGift = int(.dailyGift, d.dailyGift)
        adventCoins = int(.adventCoins, d.adventCoins)
        worldComplete = int(.worldComplete, d.worldComplete)
        stampCoins = (((try? c.decodeIfPresent([Int].self, forKey: .stampCoins)) ?? nil) ?? d.stampCoins).map { max(0, $0) }
    }
}

/// Coins (Ian, 16 Nov 2026): earned by playing, also sold in packs. Spent on
/// hints, extra jars, board themes and Buddy treats and gifts only. Nothing paid leads to squishies or
/// capsules: capsules come only from finishing levels, and every level can be
/// finished free (no move limit, unlimited retries, auto-softening).
public enum Coins {
    public static func earned(forWinWithStars stars: Int, rules: CoinRules = CoinRules()) -> Int {
        rules.winBase + (stars >= 3 ? rules.threeStarBonus : 0)
    }

    /// Coins for a win, given the best stars the level had before. A level pays
    /// once: in full on the first clear, plus the three-star difference once if
    /// a replay gets there. Replays otherwise pay nothing, so easy levels can't be farmed.
    public static func earned(forWinWithStars stars: Int, previousBest: Int?, rules: CoinRules = CoinRules()) -> Int {
        guard let previousBest else { return earned(forWinWithStars: stars, rules: rules) }
        return max(0, earned(forWinWithStars: stars, rules: rules) - earned(forWinWithStars: previousBest, rules: rules))
    }

    /// The three-star bonus this win adds on the win card: once per level.
    public static func starBonus(stars: Int, previousBest: Int?, rules: CoinRules = CoinRules()) -> Int {
        stars >= 3 && (previousBest ?? 0) < 3 ? rules.threeStarBonus : 0
    }

    /// The base win coins split across the level's jars; the last jar takes the remainder.
    public static func jarShares(jars: Int, rules: CoinRules = CoinRules()) -> [Int] {
        guard jars > 0 else { return [] }
        var shares = Array(repeating: rules.winBase / jars, count: jars)
        shares[jars - 1] += rules.winBase - (rules.winBase / jars) * jars
        return shares
    }

    /// Consecutive first-try wins on levels not cleared before. A replay
    /// neither moves nor breaks the streak, so it can't be farmed.
    public static func nextStreak(current: Int, firstClear: Bool, attempts: Int) -> Int {
        guard firstClear else { return current }
        return attempts == 1 ? current + 1 : 0
    }

    /// From a streak of 2: +10 a step, capped. Never in gentle mode (the caller checks).
    public static func streakBonus(streak: Int, rules: CoinRules = CoinRules()) -> Int {
        streak >= 2 ? min(rules.streakCap, (streak - 1) * rules.streakStep) : 0
    }

    /// The lucky squishy's kind for this level, or nil when the level has none.
    /// A stable hash of the install seed and level id, so a restart never re-rolls it.
    public static func luckyKind(levelNumber: Int, levelID: String, installSeed: String, kinds: Int,
                                 rules: CoinRules = CoinRules()) -> Int? {
        guard levelNumber >= rules.luckyFromLevel, rules.luckyOneIn > 0, kinds > 0 else { return nil }
        guard MysteryBag.stableHash(installSeed + "|lucky|" + levelID) % UInt64(rules.luckyOneIn) == 0 else { return nil }
        return Int(MysteryBag.stableHash(installSeed + "|kind|" + levelID) % UInt64(kinds))
    }

    public enum Item: String, Codable, CaseIterable, Sendable {
        case hint, extraJar, theme
        /// Buddy items. Cosmetic fun only: hearts never affect squishies, capsules, odds or level help.
        case treat, gift

        public var price: Int {
            switch self {
            case .hint: return 250
            case .extraJar: return 400
            case .theme: return 3000
            case .treat: return 100
            case .gift: return 600
            }
        }
    }

    public struct Pack: Equatable, Sendable {
        public let productID: String
        public let coins: Int
    }

    public static let packs: [Pack] = [
        Pack(productID: "com.ianatkinson.squishsort.coins1000", coins: 1000),
        Pack(productID: "com.ianatkinson.squishsort.coins3500", coins: 3500),
        Pack(productID: "com.ianatkinson.squishsort.coins7500", coins: 7500),
    ]

    public static func pack(for productID: String) -> Pack? { packs.first { $0.productID == productID } }
}

/// The coins a level's jars have thrown so far. Banked on the win; a retry or
/// leaving the level starts a new, empty pot, so nothing can be farmed.
public struct LevelPot: Equatable, Sendable {
    public struct Payout: Equatable, Sendable {
        public var coins = 0
        public var doublePop = false
        public var lucky = false

        public init(coins: Int = 0, doublePop: Bool = false, lucky: Bool = false) {
            self.coins = coins
            self.doublePop = doublePop
            self.lucky = lucky
        }
    }

    public private(set) var coins = 0
    /// False on a replay: jars throw sparkles, not coins.
    public let paysCoins: Bool
    private let shares: [Int]
    private let luckyKind: Int?
    private let rules: CoinRules
    private var paidKinds: Set<Int> = []
    private var lastJarAt: Double?

    /// `jarMultiplier` is 2 on a bonus level (Coin Rush): every finished jar throws double.
    public init(firstClear: Bool, jars: Int, luckyKind: Int? = nil, jarMultiplier: Int = 1, rules: CoinRules = CoinRules()) {
        paysCoins = firstClear
        shares = Coins.jarShares(jars: jars, rules: rules).map { $0 * max(1, jarMultiplier) }
        self.luckyKind = firstClear ? luckyKind : nil
        self.rules = rules
    }

    /// A jar of `kind` was completed `seconds` into the attempt. Each kind pays
    /// once, so undoing and completing the same jar again adds nothing.
    public mutating func jarCompleted(kind: Int, at seconds: Double) -> Payout {
        guard paysCoins, !paidKinds.contains(kind) else { return Payout() }
        var out = Payout()
        out.coins = paidKinds.count < shares.count ? shares[paidKinds.count] : 0
        paidKinds.insert(kind)
        if let last = lastJarAt, seconds - last <= rules.doublePopSeconds {
            out.doublePop = true
            out.coins += rules.doublePop
        }
        lastJarAt = seconds
        if kind == luckyKind {
            out.lucky = true
            out.coins += rules.lucky
        }
        coins += out.coins
        return out
    }

    /// Coins for a squishy streak word. Each word pays once an attempt, and only on a first clear.
    @discardableResult
    public mutating func streakWord(_ word: SortChain.Word) -> Int {
        guard paysCoins, !paidWords.contains(word) else { return 0 }
        paidWords.insert(word)
        coins += word.coins
        return word.coins
    }

    private var paidWords: Set<SortChain.Word> = []
}

/// Squishy streak (fix list B3): a chain of moves that each land on a matching squishy
/// within a few seconds of the last. A move into an empty jar keeps the chain alive but
/// adds nothing. Undo, a hint or a long pause ends it, and nothing is ever shown when it ends.
/// In gentle mode there is no time limit at all.
public struct SortChain: Equatable, Sendable {
    public enum Word: Int, CaseIterable, Sendable {
        case nice = 1, streak, onARoll, unstoppable

        /// The chain length that earns this word.
        public var length: Int {
            switch self {
            case .nice: return 3
            case .streak: return 5
            case .onARoll: return 8
            case .unstoppable: return 12
            }
        }

        /// Added to the level pot on a first clear.
        public var coins: Int { rawValue * 5 }
    }

    public static let seconds = 4.0
    public private(set) var count = 0
    private var lastAt: Double?
    /// Nil for under-13s: speed is never rewarded there, so a chain is just matching moves in a row.
    private let window: Double?

    public init(timed: Bool = true) {
        window = timed ? SortChain.seconds : nil
    }

    /// A move landed `seconds` into the attempt. Returns the word it earned, if it reached one.
    public mutating func move(ontoMatch: Bool, at seconds: Double) -> Word? {
        if let window, let last = lastAt, seconds - last > window { count = 0 }
        lastAt = seconds
        guard ontoMatch else { return nil }
        count += 1
        return Word.allCases.first { $0.length == count }
    }

    public mutating func end() {
        count = 0
        lastAt = nil
    }
}

/// Stamp card (Ian, 16 Nov 2026): the first win of a day earns one stamp, once
/// level 3 has been won. Stamps 1 to 6 give coins, stamp 7 moves the capsule
/// bar one step, then a new card starts. A missed day just means no stamp:
/// nothing is ever lost, nothing expires, and it is never called a streak.
public struct StampCard: Codable, Equatable, Sendable {
    public static let size = 7

    public enum Reward: Equatable, Sendable {
        case coins(Int)
        case capsuleStep
    }

    /// Stamps on the current card, 0 to 6 (a full card starts again at 0).
    public var stamps = 0
    public var lastStampDay: String?

    public init() {}

    /// Only a later day than the last stamp counts, so winding the clock back gives nothing.
    public func canStamp(today: String) -> Bool {
        guard let last = lastStampDay else { return true }
        return today > last
    }

    /// What stamp `number` (1 to 7) gives.
    public static func reward(stamp number: Int, rules: CoinRules = CoinRules()) -> Reward {
        guard number < size else { return .capsuleStep }
        let coins = rules.stampCoins
        return .coins(coins.isEmpty ? 0 : coins[min(max(0, number - 1), coins.count - 1)])
    }

    /// One stamp a day. Nil when today's stamp is already on the card.
    public mutating func stamp(today: String, rules: CoinRules = CoinRules()) -> Reward? {
        guard canStamp(today: today) else { return nil }
        lastStampDay = today
        stamps += 1
        let reward = StampCard.reward(stamp: stamps, rules: rules)
        if stamps >= StampCard.size { stamps = 0 }
        return reward
    }
}

/// Opt-in (rewarded) ads: capped per day across every placement.
public struct OptInAdState: Codable, Equatable, Sendable {
    public var day: String?
    public var count = 0

    public init() {}

    public func used(today: String) -> Int { day == today ? count : 0 }

    public func canWatch(today: String, cap: Int) -> Bool { used(today: today) < cap }

    public mutating func record(today: String) {
        if day != today { day = today; count = 0 }
        count += 1
    }
}

public enum OptInReward: String, CaseIterable, Sendable {
    case hint, extraJar, doubleCoins, extraGuess, dailyGift

    /// Gentle mode is offered opt-in ads only for a hint and for the extra jar.
    /// (Its daily gift is free, with no ad.)
    public func isOffered(to group: AgeGroup) -> Bool {
        group != .child || self == .hint || self == .extraJar
    }
}

/// One soft "Remove Ads" line on the win card after the 3rd interstitial ever,
/// for players of 13 and over, then never again outside the shop and Settings.
public enum RemoveAdsOffer {
    public static let afterInterstitials = 3

    public static func shouldShow(interstitialsShown: Int, group: AgeGroup, alreadyShown: Bool, ownsRemoveAds: Bool) -> Bool {
        !alreadyShown && !ownsRemoveAds && group != .child && interstitialsShown >= afterInterstitials
    }
}

public struct CoinWallet: Codable, Equatable, Sendable {
    public private(set) var balance = 0
    /// StoreKit transaction ids already credited, so a pack is never counted twice.
    public private(set) var creditedTransactions: Set<UInt64> = []

    public init() {}

    /// Missing fields fall back to defaults, so a later build's new fields can
    /// never wipe a balance or the credited-transaction list.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balance = max(0, try c.decodeIfPresent(Int.self, forKey: .balance) ?? 0)
        creditedTransactions = try c.decodeIfPresent(Set<UInt64>.self, forKey: .creditedTransactions) ?? []
    }

    public mutating func earn(_ amount: Int) {
        balance += max(0, amount)
    }

    /// Returns false (and credits nothing) if this transaction was already counted.
    @discardableResult
    public mutating func credit(pack: Coins.Pack, transactionID: UInt64) -> Bool {
        guard !creditedTransactions.contains(transactionID) else { return false }
        creditedTransactions.insert(transactionID)
        balance += pack.coins
        return true
    }

    public func canAfford(_ item: Coins.Item) -> Bool { balance >= item.price }

    @discardableResult
    public mutating func spend(on item: Coins.Item) -> Bool {
        guard canAfford(item) else { return false }
        balance -= item.price
        return true
    }
}
