import Foundation

/// Bundled defaults plus remote JSON. Remote config only changes numbers and
/// dates; every feature it can switch on is already in the reviewed build.
public struct GameConfig: Codable, Equatable, Sendable {
    public var adCadence = AdCadenceConfig()
    /// Fixed in the build: remote config can't change the odds.
    public var capsuleOdds = CapsuleOdds()
    public var coins = CoinRules()
    /// Opt-in ads a day, across every placement.
    public var optInAdsPerDay = 6
    /// The festive door shows between these days (device local date, inclusive).
    public var christmasOpenFrom = "2026-12-01"
    public var christmasOpenUntil = "2027-01-06"
    /// Snow on the home screen from this day.
    public var snowFrom = "2026-12-01"
    public var adsEnabled = true
    public var telemetryEnabled = true
    /// Each extra can be switched off remotely without a new build.
    public var squishRoomEnabled = true
    public var mysteryBagEnabled = true
    public var makerEnabled = true
    public var buddyEnabled = true
    /// Off switches for three Workshop Pro tools: drawing a shape or face, the Mixer, teaching a move.
    public var workshopDraw = true
    public var workshopMixer = true
    public var workshopTraining = true
    /// The link to the website's Squishy Shop (affiliate listings of real toys).
    public var squishyShopEnabled = true
    /// The paid extras for 13 and over (starter pack, piggy bank) and the Daily Jar can be switched off.
    public var offersEnabled = true
    public var dailyJarEnabled = true
    /// One light event, or none.
    public var event: GameEvent?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameConfig()
        adCadence = try c.decodeIfPresent(AdCadenceConfig.self, forKey: .adCadence) ?? d.adCadence
        // Capsule odds are published (in the app and on the website), so they
        // are fixed in the build and never read from remote config.
        capsuleOdds = d.capsuleOdds
        coins = try c.decodeIfPresent(CoinRules.self, forKey: .coins) ?? d.coins
        optInAdsPerDay = max(0, try c.decodeIfPresent(Int.self, forKey: .optInAdsPerDay) ?? d.optInAdsPerDay)
        christmasOpenFrom = try c.decodeIfPresent(String.self, forKey: .christmasOpenFrom) ?? d.christmasOpenFrom
        christmasOpenUntil = try c.decodeIfPresent(String.self, forKey: .christmasOpenUntil) ?? d.christmasOpenUntil
        snowFrom = try c.decodeIfPresent(String.self, forKey: .snowFrom) ?? d.snowFrom
        adsEnabled = try c.decodeIfPresent(Bool.self, forKey: .adsEnabled) ?? d.adsEnabled
        telemetryEnabled = try c.decodeIfPresent(Bool.self, forKey: .telemetryEnabled) ?? d.telemetryEnabled
        squishRoomEnabled = try c.decodeIfPresent(Bool.self, forKey: .squishRoomEnabled) ?? d.squishRoomEnabled
        mysteryBagEnabled = try c.decodeIfPresent(Bool.self, forKey: .mysteryBagEnabled) ?? d.mysteryBagEnabled
        makerEnabled = try c.decodeIfPresent(Bool.self, forKey: .makerEnabled) ?? d.makerEnabled
        buddyEnabled = try c.decodeIfPresent(Bool.self, forKey: .buddyEnabled) ?? d.buddyEnabled
        workshopDraw = try c.decodeIfPresent(Bool.self, forKey: .workshopDraw) ?? d.workshopDraw
        workshopMixer = try c.decodeIfPresent(Bool.self, forKey: .workshopMixer) ?? d.workshopMixer
        workshopTraining = try c.decodeIfPresent(Bool.self, forKey: .workshopTraining) ?? d.workshopTraining
        squishyShopEnabled = try c.decodeIfPresent(Bool.self, forKey: .squishyShopEnabled) ?? d.squishyShopEnabled
        offersEnabled = try c.decodeIfPresent(Bool.self, forKey: .offersEnabled) ?? d.offersEnabled
        dailyJarEnabled = try c.decodeIfPresent(Bool.self, forKey: .dailyJarEnabled) ?? d.dailyJarEnabled
        // A broken event never breaks the rest of the config.
        event = (try? c.decodeIfPresent(GameEvent.self, forKey: .event)) ?? nil
    }

    /// Unknown or broken remote JSON falls back to the bundled defaults.
    public static func decodeOrDefault(_ data: Data?) -> GameConfig {
        guard let data, let c = try? JSONDecoder().decode(GameConfig.self, from: data) else { return GameConfig() }
        return c
    }

    /// `today` as yyyy-MM-dd in the player's time zone.
    public func isChristmasWindow(today: String) -> Bool {
        today >= christmasOpenFrom && today <= christmasOpenUntil
    }

    public func showsSnow(today: String) -> Bool { today >= snowFrom }
}
