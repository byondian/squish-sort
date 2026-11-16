import AppTrackingTransparency
import Foundation
import StoreKit
import SwiftUI
import UIKit
import SquishCore
import SquishLevels
import SquishPolicy

/// App state: levels, progress, collection, age, purchases.
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case level(Int)
        case home
        case map
        case mystery
        case maker
        case book
        case room
        case settings
        case shop
    }

    @Published var screen: Screen = .level(0)
    @Published private(set) var progress: PlayerProgress
    @Published var capsule: Collectible?
    @Published var askAge = false
    /// Win card offers: the opt-in bonus gift box (a rewarded ad for coins).
    @Published var giftOffered = false
    @Published var storefront = ""
    /// The Buddy's speech bubble on the home screen. Never shown during a level.
    @Published var buddySays: String?
    @Published var buddyAsksMood = false
    /// The Buddy's line on the win or stuck card.
    @Published var levelCheer: String?

    let levels: [Level]
    let roster: Roster
    /// Bundled defaults, replaced by the last fetched remote config when there is one.
    @Published private(set) var config: GameConfig
    let buddyScript: BuddyScript
    let purchases: PurchaseService
    let haptics = Haptics()
    let ads = AdsService()
    private let store = ProgressStore()
    private var rng = SystemRandomNumberGenerator()
    private var sessionStart = Date()
    private var greetedThisSession = false

    /// UI tests start from a fresh install every time.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        let loaded = AppModel.isUITesting ? PlayerProgress() : store.load()
        progress = loaded
        levels = AppModel.loadLevels()
        roster = AppModel.loadRoster()
        config = RemoteConfig.cached()
        buddyScript = AppModel.loadBuddyScript()
        purchases = PurchaseService(cachedOwnership: loaded.ownsRemoveAds)
        haptics.enabled = loaded.hapticsOn
        // New players land straight on Level 1; the home screen arrives with the first capsule.
        screen = loaded.highestUnlocked >= 3 ? .home : .level(min(loaded.highestUnlocked, max(0, levels.count - 1)))
        purchases.onChange = { [weak self] owns in self?.update { $0.ownsRemoveAds = owns } }
        purchases.onCoins = { [weak self] pack, transactionID in
            self?.update { $0.wallet.credit(pack: pack, transactionID: transactionID) }
        }
        Task {
            storefront = await Storefront.current?.countryCode ?? ""
            await purchases.start()
            startServicesAfterAgeStep()
            // The storefront can change while the app runs; ad flags follow it.
            for await next in Storefront.updates {
                storefront = next.countryCode
                ads.update(policy: currentAdPolicy)
            }
        }
        Task {
            if let fresh = await RemoteConfig.fetch() { config = fresh }
        }
    }

    // MARK: - Content

    private static func loadLevels() -> [Level] {
        guard let root = Bundle.main.url(forResource: "Levels", withExtension: nil),
              let levels = try? LevelCatalog.load(root: root) else { return [] }
        return levels
    }

    private static func loadRoster() -> Roster {
        guard let url = Bundle.main.url(forResource: "roster", withExtension: "json", subdirectory: "Content"),
              let data = try? Data(contentsOf: url),
              let roster = try? Roster.decode(data) else { return Roster(collectibles: []) }
        return roster
    }

    private static func loadBuddyScript() -> BuddyScript {
        guard let url = Bundle.main.url(forResource: "buddy-lines", withExtension: "json", subdirectory: "Content"),
              let data = try? Data(contentsOf: url),
              let script = try? BuddyScript.decode(data) else { return BuddyScript() }
        return script
    }

    var today: String { PlayerProgress.today() }

    func isUnlocked(_ index: Int) -> Bool {
        guard levels.indices.contains(index) else { return false }
        return index <= progress.highestUnlocked && config.isWorldUnlocked(levels[index].file.world, today: today)
    }

    /// Corner buttons (book, map, settings) appear after the first capsule.
    var showsCornerButtons: Bool { progress.highestUnlocked >= 3 }

    /// Where "back" and "home" lead: the home screen once it exists, else the current level.
    var homeScreen: Screen { showsCornerButtons ? .home : .level(progress.highestUnlocked) }

    // MARK: - Extras

    var levelsWon: Int { progress.stars.count }

    private func isWorldComplete(_ world: String) -> Bool {
        let ids = levels.filter { $0.file.world == world }.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { progress.stars[$0] != nil }
    }

    var worldsCompleted: Int { LevelCatalog.worlds.filter { isWorldComplete($0) }.count }

    func isExtraUnlocked(_ extra: Extra) -> Bool {
        Extras.isUnlocked(extra, capsulesOpened: progress.collection.totalCapsules, levelsWon: levelsWon,
                          firstWorldComplete: isWorldComplete(LevelCatalog.worlds[0]), config: config)
    }

    func isNew(_ extra: Extra) -> Bool { isExtraUnlocked(extra) && !progress.seenExtras.contains(extra.rawValue) }

    func open(_ extra: Extra) {
        guard isExtraUnlocked(extra) else { return }
        if isNew(extra) { update { $0.seenExtras.insert(extra.rawValue) } }
        switch extra {
        case .squishRoom: screen = .room
        case .mysteryBag: screen = .mystery
        case .maker: screen = .maker
        case .buddy: break // lives on the home screen
        }
    }

    /// Everything that can be squeezed or be a Buddy: starter toys, owned squishies, made ones.
    var squeezables: [String] {
        roster.squishRoomToys.map(\.id)
            + roster.collectibles.filter { progress.collection.owns($0.id) }.map(\.id)
            + (isExtraUnlocked(.maker) ? progress.made.map(\.ref) : [])
    }

    func displayName(for ref: String) -> String {
        if let made = progress.made.first(where: { $0.ref == ref }) { return made.name }
        if let c = roster.collectible(ref) { return c.name(in: language) }
        return roster.squishRoomToys.first { $0.id == ref }?.name(in: language) ?? ""
    }

    func morphTarget(for id: String) -> Collectible? {
        roster.morphTarget(for: id, using: &rng)
    }

    // MARK: - Squishy Shop (website)

    /// Link to the website's affiliate listings of real squishies. 13+ only
    /// (14 in Korea), never gentle mode or an unknown age. Nothing is sold in the app.
    var showsSquishyShop: Bool {
        SquishyShop.isVisible(profile: progress.age, storefront: storefront, config: config)
    }

    /// Opens the shop in Safari. Call only after the grown-up check.
    func openSquishyShop() {
        guard showsSquishyShop, let url = URL(string: SquishyShop.url) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Mystery Bag

    private var openWorlds: [String] {
        LevelCatalog.worlds.filter { world in
            guard let first = levels.firstIndex(where: { $0.file.world == world }) else { return false }
            return isUnlocked(first)
        }
    }

    var mysteryBag: MysteryBag? {
        MysteryBag.daily(day: today, playerSeed: progress.installID, roster: roster, worlds: openWorlds)
    }

    /// One guess a day. A right guess moves the capsule bar on; a full bar is a free capsule.
    func guessMystery(_ id: String) -> Bool {
        guard let bag = mysteryBag, progress.mystery.canPlay(today: today) else { return false }
        let correct = bag.answer.id == id
        var earned = false
        update { earned = $0.mystery.recordGuess(correct: correct, today: today) }
        if earned {
            let world = levels.indices.contains(progress.highestUnlocked) ? levels[progress.highestUnlocked].file.world : LevelCatalog.worlds[0]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.openCapsule(world: world) }
        }
        return correct
    }

    // MARK: - Squishy Maker

    /// False when the name is empty or rude, a part is still locked, or the shelf is full.
    func saveMade(_ draft: MadeSquishy) -> Bool {
        guard isExtraUnlocked(.maker), let name = NameFilter.clean(draft.name),
              MakerParts.isAllowed(draft, worldsCompleted: worldsCompleted) else { return false }
        var made = draft
        made.name = name
        if let i = progress.made.firstIndex(where: { $0.id == made.id }) {
            update { $0.made[i] = made }
        } else {
            guard progress.made.count < MakerParts.maxMade else { return false }
            update { $0.made.append(made) }
        }
        return true
    }

    func deleteMade(_ id: String) {
        update { p in
            if let made = p.made.first(where: { $0.id == id }), p.buddy.squishy == made.ref { p.buddy.squishy = nil }
            p.made.removeAll { $0.id == id }
        }
    }

    // MARK: - Squishy Buddy

    var buddyActive: Bool { isExtraUnlocked(.buddy) && progress.buddy.squishy != nil }

    var language: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return ["ja", "ko", "zh-Hant"].contains(code) ? code : "en"
    }

    func buddyLine(_ trigger: String) -> String? {
        guard buddyActive else { return nil }
        return buddyScript.line(trigger, language: language, using: &rng)
    }

    /// False when the name is empty or rude.
    func setBuddy(ref: String, name: String) -> Bool {
        guard isExtraUnlocked(.buddy), squeezables.contains(ref), let clean = NameFilter.clean(name) else { return false }
        update { $0.buddy.squishy = ref; $0.buddy.name = clean; $0.seenExtras.insert(Extra.buddy.rawValue) }
        buddySays = buddyLine("greet_back")
        return true
    }

    /// At most one unprompted line per home visit: a greeting on the first visit
    /// of a session, then now and then a joke, a fact or "How are you today?".
    func homeAppeared() {
        buddyAsksMood = false
        guard buddyActive else { buddySays = nil; return }
        let now = Date()
        let away = progress.buddy.lastOpenedAt.map { (now.timeIntervalSince1970 - $0) / 3600 }
        let first = !greetedThisSession
        if first {
            greetedThisSession = true
            update { $0.buddy.lastOpenedAt = now.timeIntervalSince1970 }
        }
        let line = buddyScript.homeLine(firstVisitThisSession: first, hour: Calendar.current.component(.hour, from: now),
                                        hoursSinceLastOpen: away, moodAskedToday: progress.buddy.moodAskedDay == today,
                                        roll: Double.random(in: 0..<1, using: &rng))
        switch line {
        case .say(let trigger): buddySays = buddyLine(trigger)
        case .askMood:
            update { $0.buddy.moodAskedDay = today }
            buddySays = buddyLine("ask_mood")
            buddyAsksMood = buddySays != nil
        case .quiet: buddySays = nil
        }
    }

    /// The answer picks a reply and is then forgotten: never stored, never sent.
    func answerMood(_ mood: String) {
        buddyAsksMood = false
        buddySays = buddyLine("reply_\(mood)")
    }

    func pokeBuddy() {
        haptics.land()
        buddyAsksMood = false
        buddySays = buddyLine("poke")
    }

    func feedBuddy() {
        guard buddyActive, progress.buddy.treats > 0 else { return }
        update { _ = $0.buddy.feedStoredTreat() }
        haptics.complete()
        buddySays = buddyLine("treat")
    }

    /// Treats and gifts bought with coins are given straight away.
    func buyForBuddy(_ item: Coins.Item) {
        guard buddyActive, item == .treat || item == .gift, spend(item) else { return }
        update { $0.buddy.give(item) }
        haptics.complete()
        buddySays = buddyLine("treat")
    }

    /// Re-derived from the current storefront every time (unknown storefront = strictest).
    var ageGroup: AgeGroup { AgePolicy.group(of: progress.age, storefront: storefront) }
    var isGentleMode: Bool { ageGroup == .child }
    var ownsRemoveAds: Bool { purchases.ownsRemoveAds }

    func update(_ change: (inout PlayerProgress) -> Void) {
        change(&progress)
        store.save(progress)
    }

    // MARK: - Levels

    func won(index: Int, moves: Int, stars: Int, attempts: Int, playSeconds: Double) {
        let level = levels[index]
        // A level pays out once. Replays can raise the stars (and pay the
        // three-star difference once) but never another capsule or more coins.
        let previousBest = progress.stars[level.id]
        let firstClear = previousBest == nil
        update { p in
            p.wallet.earn(Coins.earned(forWinWithStars: stars, previousBest: previousBest))
            if firstClear {
                p.winsSinceGift += 1
                if level.file.capsule { p.bonusCapsules.append(level.file.world) }
            }
            p.buddy.earnTreatForWin()
            p.stars[level.id] = max(previousBest ?? 0, stars)
            p.highestUnlocked = max(p.highestUnlocked, min(index + 1, levels.count - 1))
            AdCadence.recordPlayTime(playSeconds, &p.cadence)
            AdCadence.recordWin(&p.cadence)
        }
        // Bonus gift box every 4th first clear that isn't a capsule level. Opt-in,
        // and never on the win card in gentle mode (no pop-up offers for under-13s).
        giftOffered = firstClear && !isGentleMode && !level.file.capsule && progress.winsSinceGift >= 4 && canWatchRewarded
        levelCheer = buddyLine(stars >= 3 ? "win_3star" : "win")
        if firstClear && level.file.capsule {
            openCapsule(world: level.file.world)
        }
    }

    /// Coins a win on this level would pay now (0 on a replay that doesn't improve).
    func coinsForWin(index: Int, stars: Int) -> Int {
        Coins.earned(forWinWithStars: stars, previousBest: progress.stars[levels[index].id])
    }

    func failed(playSeconds: Double) {
        update { AdCadence.recordPlayTime(playSeconds, &$0.cadence) }
        levelCheer = buddyLine("fail")
    }

    func next(after index: Int) {
        let n = index + 1
        levelCheer = nil
        screen = isUnlocked(n) ? .level(n) : .map
    }

    // MARK: - Capsules

    private func openCapsule(world: String) {
        var state = progress.collection
        if let got = CapsuleDrops.open(world: world, roster: roster, state: &state, rng: &rng) {
            update { $0.collection = state }
            capsule = got
        }
    }

    enum AfterCapsule { case nothing, bonusCapsule }
    private var afterCapsule = AfterCapsule.nothing

    /// Closes the capsule screen. What follows (the birthday question after the
    /// first capsule, or the opt-in bonus capsule ad) waits for `capsuleDismissed`,
    /// because nothing can be presented while the cover is still closing.
    func capsuleClosed(then next: AfterCapsule = .nothing) {
        afterCapsule = next
        capsule = nil
    }

    /// Called by the capsule cover's onDismiss.
    func capsuleDismissed() {
        let next = afterCapsule
        afterCapsule = .nothing
        if progress.age == nil {
            askAge = true
        } else if next == .bonusCapsule {
            openBonusCapsule()
        }
    }

    func rerollSpares(world: String) -> Collectible? {
        var state = progress.collection
        let got = CapsuleDrops.rerollSpares(world: world, roster: roster, state: &state, rng: &rng)
        if got != nil { update { $0.collection = state } }
        return got
    }

    // MARK: - Age

    /// `storefront` is "" until StoreKit reports it; the policy treats that as the strictest case.
    func setAge(range: AgeRange?, source: AgeSource) {
        let group = AgePolicy.group(for: range, storefront: storefront)
        update { $0.age = AgeProfile(group: group, source: source, storefront: storefront, lowerBound: range?.lower) }
        ads.update(policy: currentAdPolicy)
        askAge = false
        startServicesAfterAgeStep()
    }

    /// A parent can switch to gentle mode at any time, no gate needed. Ad flags
    /// change at once and any ad loaded under the old flags is thrown away.
    func switchToGentleMode() {
        update { $0.age = AgeProfile(group: .child, source: .parentSetGentleMode, storefront: storefront) }
        giftOffered = false
        ads.update(policy: currentAdPolicy)
    }

    /// Ads SDK and telemetry start only here, after the age step, with flags for the group.
    private func startServicesAfterAgeStep() {
        guard let age = progress.age, config.adsEnabled else { return }
        _ = age
        let policy = currentAdPolicy
        Task { await ads.start(policy: policy) }
        // The first-open counter joins here with the backend; children send counts only.
    }

    // MARK: - Ads

    private var trackingAllowed: Bool { ATTrackingManager.trackingAuthorizationStatus == .authorized }

    var currentAdPolicy: AdRequestPolicy {
        AdPolicy.requestPolicy(profile: progress.age, storefront: storefront, consent: ads.consentStatus,
                               trackingAllowed: trackingAllowed)
    }

    /// Apple's tracking prompt, once, for eligible players only (never gentle mode).
    private func askTrackingIfDue(levelWon: Int) async {
        guard AdPolicy.shouldAskTracking(profile: progress.age, storefront: storefront, levelWon: levelWon, alreadyAsked: progress.trackingAsked) else { return }
        update { $0.trackingAsked = true }
        _ = await ATTrackingManager.requestTrackingAuthorization()
        ads.update(policy: currentAdPolicy)
    }

    /// Bonus gift box: watch an ad, get a fixed number of coins.
    func openGift() {
        giftOffered = false
        watchRewarded { [weak self] in
            self?.update { $0.wallet.earn(Coins.bonusGift); $0.winsSinceGift = 0 }
        }
    }

    /// Double capsule: an extra capsule for a capsule level, by opt-in ad. Same odds.
    /// Teens and adults get it on the capsule screen; gentle mode only from the book.
    var bonusCapsuleWorld: String? { progress.bonusCapsules.last }

    func openBonusCapsule() {
        guard let world = bonusCapsuleWorld else { return }
        watchRewarded { [weak self] in
            guard let self else { return }
            self.update { p in
                if let i = p.bonusCapsules.lastIndex(of: world) { p.bonusCapsules.remove(at: i) }
            }
            self.openCapsule(world: world)
        }
    }

    // MARK: - Coins

    func spend(_ item: Coins.Item) -> Bool {
        guard progress.wallet.canAfford(item) else { return false }
        update { $0.wallet.spend(on: item) }
        return true
    }

    func buyTheme(_ theme: BoardTheme) {
        guard !progress.ownedThemes.contains(theme.rawValue), spend(.theme) else { return }
        update { $0.ownedThemes.insert(theme.rawValue); $0.theme = theme.rawValue }
    }

    func selectTheme(_ theme: BoardTheme) {
        guard progress.ownedThemes.contains(theme.rawValue) else { return }
        update { $0.theme = theme.rawValue }
    }

    var boardTheme: BoardTheme { BoardTheme(rawValue: progress.theme) ?? .cream }

    /// After a win: maybe an interstitial (never after a fail, never mid-level), then continue.
    func continueAfterWin(index: Int, attempts: Int) {
        giftOffered = false
        Task {
            await askTrackingIfDue(levelWon: index + 1)
            showInterstitialThenNext(index: index, attempts: attempts)
        }
    }

    private func showInterstitialThenNext(index: Int, attempts: Int) {
        let level = levels[index]
        let win = LevelWin(level: index + 1, attempts: attempts, isBoss: level.file.beat == .boss,
                           secondsIntoSession: Date().timeIntervalSince(sessionStart))
        let show = progress.age != nil && config.adsEnabled
            && AdCadence.shouldShowInterstitial(after: win, state: progress.cadence, group: ageGroup,
                                                ownsRemoveAds: ownsRemoveAds, config: config.adCadence)
        if show, ads.showInterstitial(done: { [weak self] in self?.next(after: index) }) {
            update { AdCadence.recordInterstitialShown(&$0.cadence) }
        } else if !show {
            next(after: index)
        }
    }

    /// Rewarded ads are opt-in and never award squishies.
    var canWatchRewarded: Bool { progress.age != nil && config.adsEnabled && ads.rewardedReady }

    func watchRewarded(_ granted: @escaping () -> Void) {
        ads.showRewarded { earned in if earned { granted() } }
    }

    // MARK: - Helpers

    var undoLimit: Int? { ownsRemoveAds ? nil : 5 }

    /// Extra jar: 1 free a day (1 free per level with Remove Ads).
    func canUseFreeExtraJar(usedThisLevel: Bool) -> Bool {
        ownsRemoveAds ? !usedThisLevel : progress.freeExtraJarDay != today
    }

    func useFreeExtraJar() {
        if !ownsRemoveAds { update { $0.freeExtraJarDay = today } }
    }

    /// Hint: first one free, then 3 a day with Remove Ads (rewarded ads for others once ads are in).
    var hintsAvailable: Bool {
        if !progress.freeHintUsed { return true }
        guard ownsRemoveAds else { return false }
        return progress.hintDay != today || progress.hintsUsedToday < 3
    }

    func useHint() {
        update { p in
            if !p.freeHintUsed { p.freeHintUsed = true; return }
            if p.hintDay != today { p.hintDay = today; p.hintsUsedToday = 0 }
            p.hintsUsedToday += 1
        }
    }

    func setHaptics(_ on: Bool) {
        update { $0.hapticsOn = on }
        haptics.enabled = on
    }
}
