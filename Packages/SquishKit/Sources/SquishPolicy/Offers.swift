import Foundation

/// Fair paid extras (Ian, 17 Nov 2026). Every one is for players of 13 and over only (14 in Korea);
/// gentle mode and an unknown age see none of them. No timers, no "last chance", nothing is ever
/// taken away, and nothing paid gives a squishy or a capsule.
public enum Offers {
    public static func allowed(group: AgeGroup, ageKnown: Bool) -> Bool { ageKnown && group != .child }
}

/// A one-time pack: coins, hint tokens and a board theme that is only in the pack.
public enum StarterPack {
    public static let productID = "com.ianatkinson.squishsort.starterpack"
    public static let coins = 2500
    public static let hints = 3
    /// The board theme's raw value (never a squishy).
    public static let theme = "gold"
}

/// The piggy bank: a bonus on top of every win drops in (the win's own coins are untouched).
/// It never empties or expires; breaking it is a purchase in the shop, and only the fill bar is
/// ever shown outside the shop.
public struct PiggyBank: Codable, Equatable, Sendable {
    public static let productID = "com.ianatkinson.squishsort.piggybank"
    /// It holds no more than this.
    public static let full = 4000
    /// It can be broken from here.
    public static let ready = 2000
    /// Percent of a win's coins added as a bonus.
    public static let percent = 50

    public private(set) var coins = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coins = min(PiggyBank.full, max(0, try c.decodeIfPresent(Int.self, forKey: .coins) ?? 0))
    }

    public var isReady: Bool { coins >= PiggyBank.ready }
    public var isFull: Bool { coins >= PiggyBank.full }
    public var fill: Double { Double(coins) / Double(PiggyBank.full) }

    /// Returns what went in.
    @discardableResult
    public mutating func add(forWin winCoins: Int) -> Int {
        let before = coins
        coins = min(PiggyBank.full, coins + max(0, winCoins) * PiggyBank.percent / 100)
        return coins - before
    }

    /// Breaks it: returns everything inside and starts again from empty.
    public mutating func take() -> Int {
        let all = coins
        coins = 0
        return all
    }
}

/// Squishy Maker shelf: the first place is free, each further one is bought with coins.
public enum MakerSlots {
    public static let free = 1
    public static let price = 2500

    /// Places a save starts with: one, or as many as it had already made before places had a price.
    public static func starting(alreadyMade: Int) -> Int { min(MakerParts.maxMade, max(free, alreadyMade)) }
}

/// Daily Jar: one board a day from the date, after level 10. It pays coins and a Buddy treat and
/// counts as the day's stamp. There is no streak and nothing is lost by missing a day.
public enum DailyJar {
    public static let opensAfterLevel = 10
    public static let coins = 100

    /// Which of `count` boards is today's. The same for every player on the same date.
    public static func board(day: String, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return Int(MysteryBag.stableHash("daily|" + day) % UInt64(count))
    }
}

/// One light event at a time, set from the website's config with no app update. No countdowns.
public struct GameEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Win coins are doubled.
        case doubleCoins
        /// The Daily Jar pays double.
        case dailyJarBonus
        /// Just a banner (for example a featured world).
        case banner
    }

    /// yyyy-MM-dd, inclusive, device local date.
    public var from: String
    public var until: String
    public var kind: Kind
    /// Banner text by language code ("en", "ja", "ko", "zh-Hant").
    public var banner: [String: String]

    public init(from: String, until: String, kind: Kind, banner: [String: String]) {
        self.from = from
        self.until = until
        self.kind = kind
        self.banner = banner
    }

    public func isOn(today: String) -> Bool { today >= from && today <= until }

    public func text(language: String) -> String? { banner[language] ?? banner["en"] }
}
