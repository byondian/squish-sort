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

/// Squishy Workshop shelf: three places are free, each further one is bought with coins.
public enum MakerSlots {
    public static let free = 3
    public static let price = 2500

    /// Places a save starts with: three, or as many as it had already made before places had a price.
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

/// Twist of the week: the date picks one of eight themes, each with five boards (Levels/weekly).
/// Nobody loses anything by missing a week: boards won count towards a theme's sticker for good, and
/// every theme comes round again every eight weeks. Nothing here is sold, and no ad gives any of it.
public enum WeeklyTwist {
    /// In the order they come round. Keep in step with WEEKLY_THEMES in tools/levelgen.py.
    public static let themes = ["keys", "vines", "morph", "duets", "big", "floaters", "frozen", "grand-mix"]
    public static let boardsPerTheme = 5
    /// Each board pays this once a week.
    public static let coins = 100
    /// All five boards of a theme whose sticker is already on the card.
    public static let coinsWhenOwned = 300

    /// Whole weeks since Monday 5 January 2026 (weeks start on Monday, like ISO weeks). Nil for a bad date.
    public static func week(day: String) -> Int? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        let days = daysFromCivil(parts[0], parts[1], parts[2]) - daysFromCivil(2026, 1, 5)
        return Int((Double(days) / 7).rounded(.down))
    }

    public static func theme(week: Int) -> String {
        themes[((week % themes.count) + themes.count) % themes.count]
    }

    public static func theme(day: String) -> String? { week(day: day).map(theme(week:)) }

    /// Days since 1 January 1970 in the Gregorian calendar.
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// The level number (1 to 40) of a theme's board (1 to 5) in the weekly world.
    public static func levelIndex(theme: String, board: Int) -> Int? {
        guard let t = themes.firstIndex(of: theme), (1...boardsPerTheme).contains(board) else { return nil }
        return t * boardsPerTheme + board
    }

    public static func theme(levelIndex: Int) -> String? {
        let t = (levelIndex - 1) / boardsPerTheme
        return levelIndex >= 1 && themes.indices.contains(t) ? themes[t] : nil
    }

    /// The wearable a theme's sticker brings: one pair of glasses each, found nowhere else in the game.
    public static func gift(theme: String) -> BuddyGift? {
        guard let t = themes.firstIndex(of: theme), BuddyGifts.weekly.indices.contains(t) else { return nil }
        return BuddyGifts.weekly[t]
    }

    /// The Workshop sticker picture that stands for a theme on the sticker card.
    public static func sticker(theme: String) -> String {
        switch theme {
        case "keys": return "planet"
        case "vines": return "leaf"
        case "morph": return "swirl"
        case "duets": return "music"
        case "big": return "rainbow"
        case "floaters": return "bubble"
        case "frozen": return "snowflake"
        default: return "star"
        }
    }
}

/// What a player has done in Twist of the week. Saved with the rest of the progress.
public struct WeeklyState: Codable, Equatable, Sendable {
    /// The week `paid` belongs to.
    public var week: Int?
    /// Boards (1 to 5) that have paid their coins in that week.
    public var paid: [Int] = []
    /// Boards ever won, by theme. Never cleared, so a half-done theme carries on when it comes back.
    public var won: [String: [Int]] = [:]
    /// Themes whose sticker is on the card.
    public var stickers: [String] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = (try? c.decodeIfPresent(Int.self, forKey: .week)) ?? nil
        paid = ((try? c.decodeIfPresent([Int].self, forKey: .paid)) ?? nil) ?? []
        won = ((try? c.decodeIfPresent([String: [Int]].self, forKey: .won)) ?? nil) ?? [:]
        stickers = ((try? c.decodeIfPresent([String].self, forKey: .stickers)) ?? nil) ?? []
    }

    public func hasSticker(_ theme: String) -> Bool { stickers.contains(theme) }

    /// Boards played this week.
    public func playedThisWeek(_ week: Int) -> [Int] { self.week == week ? paid : [] }

    /// How far the theme's sticker is: boards ever won, 0 to 5.
    public func towardsSticker(_ theme: String) -> Int { Set(won[theme] ?? []).count }

    /// The board to play next this week: first one still needed for the sticker, then any other not
    /// played this week. Nil when all five are played.
    public func next(theme: String, week: Int) -> Int? {
        let played = playedThisWeek(week)
        let open = (1...WeeklyTwist.boardsPerTheme).filter { !played.contains($0) }
        return open.first { !(won[theme] ?? []).contains($0) } ?? open.first
    }

    public struct Prize: Equatable, Sendable {
        public var coins = 0
        /// The fifth board of the theme was just won for the first time: its sticker goes on the card.
        public var sticker = false
        /// Coins for all five in a week once the sticker is owned.
        public var bonus = 0

        public init(coins: Int = 0, sticker: Bool = false, bonus: Int = 0) {
            self.coins = coins
            self.sticker = sticker
            self.bonus = bonus
        }
    }

    /// A board of the week's theme is won. A board pays once a week; a replay in the same week pays nothing.
    public mutating func win(theme: String, board: Int, week: Int) -> Prize {
        var prize = Prize()
        guard WeeklyTwist.themes.contains(theme), (1...WeeklyTwist.boardsPerTheme).contains(board) else { return prize }
        if self.week != week {
            self.week = week
            paid = []
        }
        guard !paid.contains(board) else { return prize }
        paid.append(board)
        prize.coins = WeeklyTwist.coins
        let owned = hasSticker(theme)
        if !(won[theme] ?? []).contains(board) { won[theme, default: []].append(board) }
        if !owned, towardsSticker(theme) >= WeeklyTwist.boardsPerTheme {
            stickers.append(theme)
            prize.sticker = true
        } else if owned, paid.count >= WeeklyTwist.boardsPerTheme {
            prize.bonus = WeeklyTwist.coinsWhenOwned
        }
        return prize
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
