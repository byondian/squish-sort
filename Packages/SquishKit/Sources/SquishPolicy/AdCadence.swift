import Foundation

/// When a forced interstitial may show (Ian, 16 Nov 2026). Remote config can
/// change the numbers; defaults match the decision.
public struct AdCadenceConfig: Codable, Equatable, Sendable {
    public struct Tier: Codable, Equatable, Sendable {
        public var fromLevel: Int
        public var everyLevels: Int
        public var everySeconds: Double

        public init(fromLevel: Int, everyLevels: Int, everySeconds: Double) {
            self.fromLevel = fromLevel
            self.everyLevels = everyLevels
            self.everySeconds = everySeconds
        }
    }

    /// Levels 1–6 never; 7–15 every 4 levels and 4 min; 16–30 every 3 and 3 min; 31+ every 2 and 90 s.
    public var tiers: [Tier] = [
        Tier(fromLevel: 7, everyLevels: 4, everySeconds: 240),
        Tier(fromLevel: 16, everyLevels: 3, everySeconds: 180),
        Tier(fromLevel: 31, everyLevels: 2, everySeconds: 90),
    ]
    /// No interstitial in the first minute of a session.
    public var sessionGraceSeconds: Double = 60
    /// Gentle mode: first ad around level 12, gaps doubled.
    public var childFirstLevel = 12
    public var childGapMultiplier = 2
    /// Kill switch.
    public var interstitialsEnabled = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AdCadenceConfig()
        tiers = try c.decodeIfPresent([Tier].self, forKey: .tiers) ?? d.tiers
        sessionGraceSeconds = try c.decodeIfPresent(Double.self, forKey: .sessionGraceSeconds) ?? d.sessionGraceSeconds
        childFirstLevel = try c.decodeIfPresent(Int.self, forKey: .childFirstLevel) ?? d.childFirstLevel
        childGapMultiplier = try c.decodeIfPresent(Int.self, forKey: .childGapMultiplier) ?? d.childGapMultiplier
        interstitialsEnabled = try c.decodeIfPresent(Bool.self, forKey: .interstitialsEnabled) ?? d.interstitialsEnabled
    }
}

/// Persisted between launches.
public struct AdCadenceState: Codable, Equatable, Sendable {
    public var levelsSinceAd = 0
    /// Play time (in levels, not in menus) since the last interstitial, or since first launch.
    public var playSecondsSinceAd: Double = 0
    public var interstitialsShown = 0

    public init() {}
}

public struct LevelWin: Sendable {
    /// Global level number (1 = toyshop-01).
    public var level: Int
    public var attempts: Int
    public var isBoss: Bool
    public var secondsIntoSession: Double
    /// This win opened a capsule or unlocked an extra. Those moments stay ad-free.
    public var hadReward: Bool

    public init(level: Int, attempts: Int, isBoss: Bool, secondsIntoSession: Double, hadReward: Bool = false) {
        self.level = level
        self.attempts = attempts
        self.isBoss = isBoss
        self.secondsIntoSession = secondsIntoSession
        self.hadReward = hadReward
    }
}

/// Interstitials are only ever considered after a win, so "never after a fail"
/// and "never mid-level" hold by construction.
public enum AdCadence {
    /// Call when a level is won, after `recordWin`.
    public static func shouldShowInterstitial(after win: LevelWin, state: AdCadenceState, group: AgeGroup,
                                              ownsRemoveAds: Bool, config: AdCadenceConfig = .init()) -> Bool {
        guard config.interstitialsEnabled, !ownsRemoveAds, let firstTier = config.tiers.first else { return false }
        let child = group == .child
        let firstLevel = child ? max(config.childFirstLevel, firstTier.fromLevel) : firstTier.fromLevel
        guard win.level >= firstLevel else { return false }
        guard win.secondsIntoSession >= config.sessionGraceSeconds else { return false }
        // Never straight after a boss win, a capsule or an extra unlocking: the big moments stay clean.
        if win.isBoss || win.hadReward { return false }
        let tier = config.tiers.last { $0.fromLevel <= win.level } ?? firstTier
        let multiplier = child ? max(1, config.childGapMultiplier) : 1
        let secondsOK = state.playSecondsSinceAd >= tier.everySeconds * Double(multiplier)
        // The very first interstitial only waits for play time.
        let levelsOK = state.interstitialsShown == 0 || state.levelsSinceAd >= tier.everyLevels * multiplier
        return secondsOK && levelsOK
    }

    public static func recordWin(_ state: inout AdCadenceState) {
        state.levelsSinceAd += 1
    }

    public static func recordPlayTime(_ seconds: Double, _ state: inout AdCadenceState) {
        state.playSecondsSinceAd += max(0, seconds)
    }

    /// An opt-in rewarded ad counts as the ad break: the wait for the next forced ad starts again.
    public static func recordRewardedWatched(_ state: inout AdCadenceState) {
        state.levelsSinceAd = 0
        state.playSecondsSinceAd = 0
    }

    public static func recordInterstitialShown(_ state: inout AdCadenceState) {
        state.levelsSinceAd = 0
        state.playSecondsSinceAd = 0
        state.interstitialsShown += 1
    }
}

/// Apple's rating prompt: once, at a happy moment. After a boss win on the
/// first try from level 10 on, never in gentle mode. Boss wins never show a
/// forced ad, so it never follows an ad or a fail.
public enum RatingPrompt {
    /// Apple's own star pop-up is asked for once, at a happy moment: after the first
    /// world-complete celebration or the first ultra-rare capsule, whichever comes first.
    public enum Moment: Sendable { case worldComplete, ultraCapsule }

    public static func shouldAsk(at moment: Moment, group: AgeGroup, alreadyAsked: Bool) -> Bool {
        !alreadyAsked && group != .child
    }
}
