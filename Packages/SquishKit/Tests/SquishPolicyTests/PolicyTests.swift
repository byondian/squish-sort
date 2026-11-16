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
        XCTAssertEqual(roster.collectibles.count, 64)
        XCTAssertEqual(Set(roster.collectibles.map(\.id)).count, 64, "ids are unique")
        for world in ["toyshop", "sweetfactory", "starlight", "christmas"] {
            XCTAssertEqual(roster.world(world, .common).count, 6)
            XCTAssertGreaterThanOrEqual(roster.world(world, .rare).count, 4)
            XCTAssertGreaterThanOrEqual(roster.world(world, .ultra).count, 2)
            XCTAssertEqual(roster.world(world, .secret).count, 1)
            XCTAssertEqual(roster.collectibles.filter { $0.world == world && $0.shapeshifter }.count, 1,
                           "one Morph Squad member per world")
        }
        XCTAssertEqual(Set(roster.squishRoomToys.map(\.id)), ["gloop", "tapey"])
    }

    func testMorphSquadTurnsIntoSomeoneFromItsOwnWorld() {
        var rng = SplitMix64(seed: 7)
        for id in roster.collectibles.filter(\.shapeshifter).map(\.id) {
            let me = roster.collectible(id)!
            for _ in 0..<50 {
                let t = roster.morphTarget(for: id, using: &rng)!
                XCTAssertEqual(t.world, me.world)
                XCTAssertNotEqual(t.id, id)
                XCTAssertNotEqual(t.rarity, .secret)
            }
        }
        XCTAssertNil(roster.morphTarget(for: "strawbie", using: &rng))
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

final class ExtrasTests: XCTestCase {
    private func content(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Content/\(name)")
        return try Data(contentsOf: url)
    }

    func testUnlockOrderKeepsTheFirstMinutesSimple() {
        func open(_ e: Extra, capsules: Int = 0, won: Int = 0, world: Bool = false) -> Bool {
            Extras.isUnlocked(e, capsulesOpened: capsules, levelsWon: won, firstWorldComplete: world)
        }
        for e in Extra.allCases { XCTAssertFalse(open(e), "\(e) is hidden on a fresh install") }
        XCTAssertTrue(open(.squishRoom, capsules: 1, won: 3))
        XCTAssertFalse(open(.mysteryBag, capsules: 3, won: 9))
        XCTAssertTrue(open(.mysteryBag, capsules: 3, won: 10))
        XCTAssertFalse(open(.maker, capsules: 6, won: 19))
        XCTAssertTrue(open(.maker, capsules: 6, won: 20, world: true))
        XCTAssertTrue(open(.buddy, capsules: 6, won: 20, world: true))
    }

    func testEachExtraHasARemoteOffSwitch() {
        var config = GameConfig()
        config.squishRoomEnabled = false
        config.mysteryBagEnabled = false
        config.makerEnabled = false
        config.buddyEnabled = false
        for e in Extra.allCases {
            XCTAssertFalse(Extras.isUnlocked(e, capsulesOpened: 50, levelsWon: 80, firstWorldComplete: true, config: config))
        }
        let remote = GameConfig.decodeOrDefault(Data(#"{"makerEnabled": false}"#.utf8))
        XCTAssertFalse(remote.makerEnabled)
        XCTAssertTrue(remote.buddyEnabled)
    }

    func testMysteryBagIsTheSameAllDayAndNeverShowsSecretsOrLockedWorlds() throws {
        let roster = try Roster.decode(content("roster.json"))
        let worlds = ["toyshop", "sweetfactory", "starlight"]
        for day in 1...28 {
            let d = String(format: "2026-12-%02d", day)
            let a = try XCTUnwrap(MysteryBag.daily(day: d, playerSeed: "p1", roster: roster, worlds: worlds))
            let b = try XCTUnwrap(MysteryBag.daily(day: d, playerSeed: "p1", roster: roster, worlds: worlds))
            XCTAssertEqual(a, b)
            XCTAssertEqual(Set(a.choices.map(\.id)).count, 4)
            XCTAssertTrue(a.choices.contains(a.answer))
            for c in a.choices {
                XCTAssertNotEqual(c.rarity, .secret)
                XCTAssertNotEqual(c.world, "christmas")
            }
        }
        let answers = Set((1...28).compactMap {
            MysteryBag.daily(day: String(format: "2026-12-%02d", $0), playerSeed: "p1", roster: roster, worlds: worlds)?.answer.id
        })
        XCTAssertGreaterThan(answers.count, 10, "the bag changes from day to day")
        XCTAssertNil(MysteryBag.daily(day: "2026-12-01", playerSeed: "p1", roster: Roster(collectibles: []), worlds: worlds))
    }

    func testMysteryBagIsOneGuessADayAndThreeRightGuessesEarnACapsule() {
        var s = MysteryState()
        XCTAssertFalse(s.recordGuess(correct: true, today: "2026-12-01"))
        XCTAssertFalse(s.canPlay(today: "2026-12-01"))
        XCTAssertFalse(s.recordGuess(correct: true, today: "2026-12-01"), "a second guess the same day does nothing")
        XCTAssertEqual(s.steps, 1)
        XCTAssertFalse(s.recordGuess(correct: false, today: "2026-12-02"))
        XCTAssertEqual(s.steps, 1)
        XCTAssertFalse(s.recordGuess(correct: true, today: "2026-12-03"))
        XCTAssertTrue(s.recordGuess(correct: true, today: "2026-12-04"))
        XCTAssertEqual(s.steps, 0)
    }

    func testMakerPartsOpenWithWorlds() {
        XCTAssertEqual(MakerParts.shapes(worldsCompleted: 1), 3)
        XCTAssertEqual(MakerParts.shapes(worldsCompleted: 10), MadeSquishy.Shape.allCases.count)
        XCTAssertTrue(MakerParts.isAllowed(MadeSquishy(id: "a"), worldsCompleted: 1))
        XCTAssertFalse(MakerParts.isAllowed(MadeSquishy(id: "a", shape: .cloud), worldsCompleted: 1))
        XCTAssertTrue(MakerParts.isAllowed(MadeSquishy(id: "a", shape: .cloud, color: 11, eyes: .wink, mouth: .tongue,
                                                       ears: .horns, accessory: .leaf), worldsCompleted: 4))
        XCTAssertFalse(MakerParts.isAllowed(MadeSquishy(id: "a", color: 99), worldsCompleted: 4))
        XCTAssertEqual(MadeSquishy(id: "x").ref, "made:x")
    }

    func testNamesAreTrimmedShortenedAndFiltered() {
        XCTAssertEqual(NameFilter.clean("  Mochi  "), "Mochi")
        XCTAssertEqual(NameFilter.clean("Supercalifragilistic"), "Supercalifra")
        XCTAssertNil(NameFilter.clean("   "))
        for rude in ["shit", "Sh1t", "s h i t", "FUCKface", "a$$hole", "ass", "씨발", "くそ"] {
            XCTAssertNil(NameFilter.clean(rude), rude)
        }
        for fine in ["Grass", "Cocoa", "Bassy", "Peach Bun", "もち", "모찌", "麻糬", "Hello", "Shelly"] {
            XCTAssertNotNil(NameFilter.clean(fine), fine)
        }
    }

    func testBuddyTreatsAndHearts() {
        var b = BuddyState()
        XCTAssertFalse(b.feedStoredTreat())
        for _ in 0..<5 { b.earnTreatForWin() }
        XCTAssertEqual(b.treats, 3, "at most three free treats are stored")
        XCTAssertTrue(b.feedStoredTreat())
        XCTAssertEqual(b.treats, 2)
        XCTAssertEqual(b.hearts, 1)
        b.give(.gift)
        XCTAssertEqual(b.hearts, 6)
        b.give(.hint)
        XCTAssertEqual(b.hearts, 6)
        b.hearts = 1000
        XCTAssertEqual(b.tricksUnlocked, BuddyState.tricks)
        XCTAssertEqual(Coins.Item.treat.price, 10)
        XCTAssertEqual(Coins.Item.gift.price, 60)
    }

    func testBuddyStateDecodesFromAnOlderSave() throws {
        let b = try JSONDecoder().decode(BuddyState.self, from: Data("{}".utf8))
        XCTAssertEqual(b, BuddyState())
    }

    func testLineBankCoversEveryTriggerInEveryLanguage() throws {
        let script = try BuddyScript.decode(content("buddy-lines.json"))
        XCTAssertGreaterThan(script.lines.count, 100)
        XCTAssertEqual(Set(script.lines.map(\.id)).count, script.lines.count, "ids are unique")
        let needed = ["greet_morning", "greet_afternoon", "greet_evening", "greet_night", "greet_back", "win", "win_3star",
                      "fail", "poke", "treat", "joke", "fact", "ask_mood", "reply_happy", "reply_okay", "reply_sleepy", "reply_grumpy"]
        var rng = SplitMix64(seed: 1)
        for trigger in needed {
            for language in ["en", "ja", "ko", "zh-Hant"] {
                let line = script.line(trigger, language: language, using: &rng)
                XCTAssertFalse((line ?? "").isEmpty, "\(trigger) in \(language)")
            }
        }
        for line in script.lines {
            for language in ["en", "ja", "ko", "zh-Hant"] {
                XCTAssertFalse((line.text[language] ?? "").isEmpty, "\(line.id) in \(language)")
            }
        }
        XCTAssertEqual(script.line("win", language: "fr", using: &rng) != nil, true, "unknown languages fall back to English")
        XCTAssertNil(script.line("no_such_trigger", language: "en", using: &rng))
    }

    func testBuddySpeaksAtMostOncePerHomeVisit() {
        let s = BuddyScript()
        XCTAssertEqual(s.greetTrigger(hour: 8, hoursSinceLastOpen: 2), "greet_morning")
        XCTAssertEqual(s.greetTrigger(hour: 14, hoursSinceLastOpen: nil), "greet_afternoon")
        XCTAssertEqual(s.greetTrigger(hour: 19, hoursSinceLastOpen: 1), "greet_evening")
        XCTAssertEqual(s.greetTrigger(hour: 2, hoursSinceLastOpen: 1), "greet_night")
        XCTAssertEqual(s.greetTrigger(hour: 8, hoursSinceLastOpen: 30), "greet_back")
        func visit(first: Bool = false, asked: Bool = false, roll: Double) -> BuddyScript.HomeLine {
            s.homeLine(firstVisitThisSession: first, hour: 8, hoursSinceLastOpen: 1, moodAskedToday: asked, roll: roll)
        }
        XCTAssertEqual(visit(first: true, roll: 0.99), .say(trigger: "greet_morning"))
        XCTAssertEqual(visit(roll: 0.05), .say(trigger: "joke"))
        XCTAssertEqual(visit(roll: 0.2), .say(trigger: "fact"))
        XCTAssertEqual(visit(roll: 0.3), .askMood)
        XCTAssertEqual(visit(asked: true, roll: 0.3), .quiet, "the mood question comes at most once a day")
        XCTAssertEqual(visit(roll: 0.9), .quiet)
    }
}
