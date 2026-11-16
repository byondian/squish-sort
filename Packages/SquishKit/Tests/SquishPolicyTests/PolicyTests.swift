import Foundation
import XCTest
@testable import SquishPolicy

final class AgeTests: XCTestCase {
    func testUnknownAgeIsAChild() {
        XCTAssertEqual(AgePolicy.group(for: nil, storefront: "GBR"), .child)
        XCTAssertEqual(AgePolicy.group(for: AgeRange(lower: nil, upper: 20), storefront: "USA"), .child)
        XCTAssertEqual(AgePolicy.group(for: AgePolicy.range(birthYear: nil, currentYear: 2026), storefront: "USA"), .child)
    }

    func testKoreaUsesUnderFourteen() {
        let thirteen = AgeRange(lower: 13, upper: 13)
        XCTAssertEqual(AgePolicy.group(for: thirteen, storefront: "KOR"), .child)
        XCTAssertEqual(AgePolicy.group(for: thirteen, storefront: "JPN"), .teen)
        XCTAssertEqual(AgePolicy.group(for: AgeRange(lower: 14, upper: nil), storefront: "KOR"), .teen)
    }

    func testUnclearRangesResolveYounger() {
        // Declared Age Range can say "under 13" or "13 to 17"
        XCTAssertEqual(AgePolicy.group(for: AgeRange(lower: 0, upper: 12), storefront: "USA"), .child)
        XCTAssertEqual(AgePolicy.group(for: AgeRange(lower: 13, upper: 17), storefront: "USA"), .teen)
        XCTAssertEqual(AgePolicy.group(for: AgeRange(lower: 18, upper: nil), storefront: "USA"), .adult)
    }

    func testBirthYearAssumesTheBirthdayHasNotHappened() {
        // Born 2013, in 2026: could be 12 or 13, so a child.
        let r = AgePolicy.range(birthYear: 2013, currentYear: 2026)
        XCTAssertEqual(r, AgeRange(lower: 12, upper: 13))
        XCTAssertEqual(AgePolicy.group(for: r, storefront: "GBR"), .child)
        XCTAssertEqual(AgePolicy.group(for: AgePolicy.range(birthYear: 2007, currentYear: 2026), storefront: "GBR"), .adult)
        XCTAssertNil(AgePolicy.range(birthYear: 2030, currentYear: 2026))
    }

    func testLeavingGentleModeNeedsTheParentalGate() {
        XCTAssertTrue(AgePolicy.needsParentalGate(from: .child, to: .teen))
        XCTAssertTrue(AgePolicy.needsParentalGate(from: .child, to: .adult))
        XCTAssertFalse(AgePolicy.needsParentalGate(from: .adult, to: .child))
        XCTAssertFalse(AgePolicy.needsParentalGate(from: .teen, to: .teen))
    }
}

final class AdPolicyTests: XCTestCase {
    func testChildrenGetChildDirectedGRatedAds() {
        let p = AdPolicy.requestPolicy(group: .child, storefront: "GBR", consent: .obtained)
        XCTAssertTrue(p.tagForChildDirectedTreatment)
        XCTAssertEqual(p.maxAdContentRating, .g)
        XCTAssertFalse(p.allowPersonalisedAds)
        XCTAssertFalse(p.showConsentForm)
    }

    func testNothingIsPersonalisedWithoutTrackingAllow() {
        for group in [AgeGroup.teen, .adult] {
            let p = AdPolicy.requestPolicy(group: group, storefront: "USA", consent: .notRequired, mayPersonalise: true, trackingAllowed: false)
            XCTAssertFalse(p.allowPersonalisedAds)
        }
    }

    func testTeensOverTheConsentAgePersonaliseAfterAllow() {
        let p = AdPolicy.requestPolicy(group: .teen, storefront: "JPN", consent: .notRequired, mayPersonalise: true, trackingAllowed: true)
        XCTAssertTrue(p.allowPersonalisedAds)
        XCTAssertFalse(p.tagForUnderAgeOfConsent)
        XCTAssertEqual(p.maxAdContentRating, .pg)
        let young = AdPolicy.requestPolicy(group: .teen, storefront: "KOR", consent: .notRequired, mayPersonalise: false, trackingAllowed: true)
        XCTAssertFalse(young.allowPersonalisedAds)
        XCTAssertTrue(young.tagForUnderAgeOfConsent)
    }

    func testChildrenNeverPersonaliseEvenWithAllow() {
        let p = AdPolicy.requestPolicy(group: .child, storefront: "USA", consent: .obtained, mayPersonalise: true, trackingAllowed: true)
        XCTAssertFalse(p.allowPersonalisedAds)
        XCTAssertTrue(p.tagForChildDirectedTreatment)
    }

    func testAdultsInTheUKNeedTheConsentFormToo() {
        XCTAssertTrue(AdPolicy.requestPolicy(group: .adult, storefront: "GBR", consent: .unknown).showConsentForm)
        XCTAssertFalse(AdPolicy.requestPolicy(group: .adult, storefront: "GBR", consent: .denied, mayPersonalise: true, trackingAllowed: true).allowPersonalisedAds)
        XCTAssertTrue(AdPolicy.requestPolicy(group: .adult, storefront: "GBR", consent: .obtained, mayPersonalise: true, trackingAllowed: true).allowPersonalisedAds)
        XCTAssertFalse(AdPolicy.requestPolicy(group: .adult, storefront: "JPN", consent: .unknown).showConsentForm)
    }

    func testPersonalisationAges() {
        XCTAssertEqual(AgePolicy.personalisationAge(storefront: "USA"), 13)
        XCTAssertEqual(AgePolicy.personalisationAge(storefront: "KOR"), 14)
        XCTAssertEqual(AgePolicy.personalisationAge(storefront: "GBR"), 18, "UK teens stay non-personalised")
        XCTAssertEqual(AgePolicy.personalisationAge(storefront: "DEU"), 16)
        XCTAssertFalse(AgePolicy.mayPersonaliseAds(range: nil, storefront: "USA"), "unknown age never personalises")
        XCTAssertTrue(AgePolicy.mayPersonaliseAds(range: AgeRange(lower: 13, upper: 17), storefront: "USA"))
        XCTAssertFalse(AgePolicy.mayPersonaliseAds(range: AgeRange(lower: 13, upper: 17), storefront: "GBR"))
    }

    func testTrackingPromptOnlyForEligiblePlayersAfterLevelFive() {
        let teen = AgeProfile(group: .teen, source: .birthYear, storefront: "USA", mayPersonaliseAds: true)
        let child = AgeProfile(group: .child, source: .skipped, storefront: "USA", mayPersonaliseAds: true)
        XCTAssertFalse(child.mayPersonaliseAds, "children can never be marked for personalisation")
        XCTAssertFalse(AdPolicy.shouldAskTracking(profile: teen, levelWon: 4, alreadyAsked: false))
        XCTAssertTrue(AdPolicy.shouldAskTracking(profile: teen, levelWon: 5, alreadyAsked: false))
        XCTAssertFalse(AdPolicy.shouldAskTracking(profile: teen, levelWon: 9, alreadyAsked: true))
        XCTAssertFalse(AdPolicy.shouldAskTracking(profile: child, levelWon: 9, alreadyAsked: false))
        XCTAssertFalse(AdPolicy.shouldAskTracking(profile: nil, levelWon: 9, alreadyAsked: false))
    }
}

final class CadenceTests: XCTestCase {
    func win(_ level: Int, session: Double = 600, attempts: Int = 1, boss: Bool = false) -> LevelWin {
        LevelWin(level: level, attempts: attempts, isBoss: boss, secondsIntoSession: session)
    }

    func played(_ seconds: Double, levels: Int = 0, shown: Int = 0) -> AdCadenceState {
        var s = AdCadenceState()
        s.playSecondsSinceAd = seconds
        s.levelsSinceAd = levels
        s.interstitialsShown = shown
        return s
    }

    func testNoAdsInLevelsOneToSix() {
        for level in 1...6 {
            XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(level), state: played(9999), group: .adult, ownsRemoveAds: false))
        }
    }

    func testFirstAdAfterLevelSevenOnceFourMinutesPlayed() {
        XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(7), state: played(200, levels: 7), group: .adult, ownsRemoveAds: false))
        XCTAssertTrue(AdCadence.shouldShowInterstitial(after: win(7), state: played(240, levels: 7), group: .adult, ownsRemoveAds: false))
    }

    func testRemoveAdsMeansNoInterstitials() {
        XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(40), state: played(9999, levels: 99, shown: 3), group: .adult, ownsRemoveAds: true))
    }

    func testNotInTheFirstMinuteOfASession() {
        XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(20, session: 30), state: played(9999, levels: 9, shown: 1), group: .adult, ownsRemoveAds: false))
    }

    func testNotAfterABossThatTookSeveralTries() {
        XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(10, attempts: 2, boss: true), state: played(9999, levels: 9, shown: 1), group: .adult, ownsRemoveAds: false))
    }

    func testTiersRampUp() {
        let s3 = played(180, levels: 3, shown: 1)
        XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(12), state: s3, group: .adult, ownsRemoveAds: false), "7–15 waits 4 levels")
        XCTAssertTrue(AdCadence.shouldShowInterstitial(after: win(20), state: s3, group: .adult, ownsRemoveAds: false), "16–30 every 3 levels / 3 min")
        XCTAssertTrue(AdCadence.shouldShowInterstitial(after: win(35), state: played(90, levels: 2, shown: 4), group: .adult, ownsRemoveAds: false))
    }

    func testGentleModeStartsLaterAndHalvesFrequency() {
        XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(8), state: played(9999), group: .child, ownsRemoveAds: false))
        XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(12), state: played(400), group: .child, ownsRemoveAds: false))
        XCTAssertTrue(AdCadence.shouldShowInterstitial(after: win(12), state: played(480), group: .child, ownsRemoveAds: false))
        XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(20), state: played(360, levels: 5, shown: 1), group: .child, ownsRemoveAds: false))
        XCTAssertTrue(AdCadence.shouldShowInterstitial(after: win(20), state: played(360, levels: 6, shown: 1), group: .child, ownsRemoveAds: false))
    }

    func testKillSwitch() {
        var c = AdCadenceConfig()
        c.interstitialsEnabled = false
        XCTAssertFalse(AdCadence.shouldShowInterstitial(after: win(40), state: played(9999, levels: 9, shown: 1), group: .adult, ownsRemoveAds: false, config: c))
    }

    func testRecording() {
        var s = AdCadenceState()
        AdCadence.recordWin(&s)
        AdCadence.recordPlayTime(30, &s)
        AdCadence.recordInterstitialShown(&s)
        XCTAssertEqual(s.levelsSinceAd, 0)
        XCTAssertEqual(s.playSecondsSinceAd, 0)
        XCTAssertEqual(s.interstitialsShown, 1)
    }
}

final class CapsuleTests: XCTestCase {
    var roster: Roster!

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Content/roster.json")
        roster = try Roster.decode(Data(contentsOf: url))
    }

    func testRosterShape() {
        XCTAssertEqual(roster.collectibles.count, 48)
        XCTAssertEqual(Set(roster.collectibles.map(\.id)).count, 48, "ids are unique")
        for world in ["toyshop", "sweetfactory", "starlight", "christmas"] {
            XCTAssertEqual(roster.world(world, .common).count, 6)
            XCTAssertEqual(roster.world(world, .rare).count, 4)
            XCTAssertEqual(roster.world(world, .ultra).count, 1)
            XCTAssertEqual(roster.world(world, .secret).count, 1)
        }
    }

    func testFirstCapsuleIsPeachBun() {
        var state = CollectionState()
        var rng = SplitMix64(seed: 42)
        XCTAssertEqual(CapsuleDrops.open(world: "toyshop", roster: roster, state: &state, rng: &rng)?.id, "peach-bun")
    }

    func testRareGuaranteedByTheFourthCapsuleOfEachWorld() {
        for seed in 0..<200 as Range<UInt64> {
            var state = CollectionState()
            state.totalCapsules = 1 // past the Peach Bun capsule
            var rng = SplitMix64(seed: seed)
            var rare = false
            for _ in 0..<4 {
                let got = CapsuleDrops.open(world: "sweetfactory", roster: roster, state: &state, rng: &rng)!
                if got.rarity != .common { rare = true }
            }
            XCTAssertTrue(rare, "seed \(seed)")
        }
    }

    func testNewCommonsFirstAndSecretsNeverDrop() {
        var state = CollectionState()
        state.totalCapsules = 1
        var rng = SplitMix64(seed: 7)
        var commons: [String] = []
        for _ in 0..<60 {
            let got = CapsuleDrops.open(world: "toyshop", roster: roster, state: &state, rng: &rng)!
            XCTAssertNotEqual(got.rarity, .secret)
            if got.rarity == .common { commons.append(got.id) }
        }
        XCTAssertEqual(Set(commons.prefix(6)).count, 6, "the first six commons are all different")
    }

    func testOddsAreRoughly70_25_5() {
        var rng = SplitMix64(seed: 1)
        var counts: [Rarity: Int] = [:]
        for _ in 0..<20_000 { counts[CapsuleDrops.rollTier(&rng), default: 0] += 1 }
        XCTAssertEqual(Double(counts[.common]!) / 20_000, 0.70, accuracy: 0.02)
        XCTAssertEqual(Double(counts[.rare]!) / 20_000, 0.25, accuracy: 0.02)
        XCTAssertEqual(Double(counts[.ultra]!) / 20_000, 0.05, accuracy: 0.01)
    }

    func testDropsAreTheSameWithOrWithoutRemoveAds() {
        // CapsuleDrops takes no purchase state at all; the same seed always
        // gives the same squishies, whatever the player has bought.
        func run() -> [String] {
            var state = CollectionState()
            var rng = SplitMix64(seed: 99)
            return (0..<30).compactMap { _ in CapsuleDrops.open(world: "starlight", roster: roster, state: &state, rng: &rng)?.id }
        }
        XCTAssertEqual(run(), run())
    }

    func testRerollSpendsThreeSparesForSomethingNew() {
        var state = CollectionState()
        state.owned = ["strawbie": 3, "tango": 2, "sunny": 1]
        var rng = SplitMix64(seed: 3)
        let got = CapsuleDrops.rerollSpares(world: "toyshop", roster: roster, state: &state, rng: &rng)
        XCTAssertNotNil(got)
        XCTAssertEqual(state.owned["strawbie"], 1)
        XCTAssertEqual(state.owned["tango"], 1)
        XCTAssertFalse(["strawbie", "tango", "sunny"].contains(got!.id))
        XCTAssertNil(CapsuleDrops.rerollSpares(world: "toyshop", roster: roster, state: &state, rng: &rng), "no spares left")
    }
}

final class ConfigTests: XCTestCase {
    func testPartialRemoteConfigKeepsDefaults() {
        let json = #"{"adCadence": {"sessionGraceSeconds": 90}, "christmasUnlock": "2026-12-15"}"#
        let c = GameConfig.decodeOrDefault(Data(json.utf8))
        XCTAssertEqual(c.adCadence.sessionGraceSeconds, 90)
        XCTAssertEqual(c.adCadence.tiers.count, 3)
        XCTAssertEqual(c.christmasUnlock, "2026-12-15")
        XCTAssertTrue(c.adsEnabled)
    }

    func testBrokenConfigFallsBack() {
        XCTAssertEqual(GameConfig.decodeOrDefault(Data("nope".utf8)), GameConfig())
        XCTAssertEqual(GameConfig.decodeOrDefault(nil), GameConfig())
    }

    func testChristmasUnlocksByDate() {
        let c = GameConfig()
        XCTAssertFalse(c.isWorldUnlocked("christmas", today: "2026-12-17"))
        XCTAssertTrue(c.isWorldUnlocked("christmas", today: "2026-12-18"))
        XCTAssertTrue(c.isWorldUnlocked("toyshop", today: "2026-11-25"))
    }
}

final class CoinTests: XCTestCase {
    func testEarningAndSpending() {
        var w = CoinWallet()
        w.earn(Coins.earned(forWinWithStars: 3))
        w.earn(Coins.earned(forWinWithStars: 1))
        XCTAssertEqual(w.balance, 15)
        XCTAssertFalse(w.spend(on: .hint), "can't go below zero")
        w.earn(10)
        XCTAssertTrue(w.spend(on: .hint))
        XCTAssertEqual(w.balance, 0)
    }

    func testAPackIsCreditedOnce() {
        var w = CoinWallet()
        let pack = Coins.packs[1]
        XCTAssertTrue(w.credit(pack: pack, transactionID: 42))
        XCTAssertFalse(w.credit(pack: pack, transactionID: 42))
        XCTAssertEqual(w.balance, 350)
    }

    func testNothingInTheShopIsASquishy() {
        XCTAssertEqual(Set(Coins.Item.allCases), [.hint, .extraJar, .theme])
    }
}
