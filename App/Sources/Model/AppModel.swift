import AppTrackingTransparency
import Foundation
import StoreKit
import SwiftUI
import SquishCore
import SquishLevels
import SquishPolicy

/// App state: levels, progress, collection, age, purchases.
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case level(Int)
        case map
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

    let levels: [Level]
    let roster: Roster
    let config: GameConfig
    let purchases: PurchaseService
    let haptics = Haptics()
    let ads = AdsService()
    private let store = ProgressStore()
    private var rng = SystemRandomNumberGenerator()
    private var sessionStart = Date()

    /// UI tests start from a fresh install every time.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        let loaded = AppModel.isUITesting ? PlayerProgress() : store.load()
        progress = loaded
        levels = AppModel.loadLevels()
        roster = AppModel.loadRoster()
        config = GameConfig() // remote config fetch arrives with the backend
        purchases = PurchaseService(cachedOwnership: loaded.ownsRemoveAds)
        haptics.enabled = loaded.hapticsOn
        screen = .level(min(loaded.highestUnlocked, max(0, levels.count - 1)))
        purchases.onChange = { [weak self] owns in self?.update { $0.ownsRemoveAds = owns } }
        purchases.onCoins = { [weak self] pack, transactionID in
            self?.update { $0.wallet.credit(pack: pack, transactionID: transactionID) }
        }
        Task {
            storefront = await Storefront.current?.countryCode ?? ""
            await purchases.start()
            startServicesAfterAgeStep()
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

    var today: String { PlayerProgress.today() }

    func isUnlocked(_ index: Int) -> Bool {
        guard levels.indices.contains(index) else { return false }
        return index <= progress.highestUnlocked && config.isWorldUnlocked(levels[index].file.world, today: today)
    }

    /// Corner buttons (book, map, settings) appear after the first capsule.
    var showsCornerButtons: Bool { progress.highestUnlocked >= 3 }

    var ageGroup: AgeGroup { progress.age?.group ?? .child }
    var isGentleMode: Bool { ageGroup == .child }
    var ownsRemoveAds: Bool { purchases.ownsRemoveAds }

    func update(_ change: (inout PlayerProgress) -> Void) {
        change(&progress)
        store.save(progress)
    }

    // MARK: - Levels

    func won(index: Int, moves: Int, stars: Int, attempts: Int, playSeconds: Double) {
        let level = levels[index]
        update { p in
            p.wallet.earn(Coins.earned(forWinWithStars: stars))
            p.winsSinceGift += 1
            if level.file.capsule { p.bonusCapsules.append(level.file.world) }
            p.stars[level.id] = max(p.stars[level.id] ?? 0, stars)
            p.highestUnlocked = max(p.highestUnlocked, min(index + 1, levels.count - 1))
            AdCadence.recordPlayTime(playSeconds, &p.cadence)
            AdCadence.recordWin(&p.cadence)
        }
        // Bonus gift box every 4th win that isn't a capsule level, opt-in only.
        giftOffered = !level.file.capsule && progress.winsSinceGift >= 4 && canWatchRewarded
        if level.file.capsule {
            openCapsule(world: level.file.world)
        }
    }

    func failed(playSeconds: Double) {
        update { AdCadence.recordPlayTime(playSeconds, &$0.cadence) }
    }

    func next(after index: Int) {
        let n = index + 1
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

    /// After the first capsule, the book asks the birthday question.
    func capsuleClosed() {
        capsule = nil
        guard progress.age == nil else { return }
        // Let the capsule cover finish dismissing before the next one presents.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.askAge = true }
    }

    func rerollSpares(world: String) -> Collectible? {
        var state = progress.collection
        let got = CapsuleDrops.rerollSpares(world: world, roster: roster, state: &state, rng: &rng)
        if got != nil { update { $0.collection = state } }
        return got
    }

    // MARK: - Age

    /// Unknown storefront uses the strictest child cut-off (Korea's under-14).
    private var policyStorefront: String { storefront.isEmpty ? "KOR" : storefront }

    func setAge(range: AgeRange?, source: AgeSource) {
        let group = AgePolicy.group(for: range, storefront: policyStorefront)
        let personalise = AgePolicy.mayPersonaliseAds(range: range, storefront: policyStorefront)
        update { $0.age = AgeProfile(group: group, source: source, storefront: storefront, mayPersonaliseAds: personalise) }
        ads.update(policy: currentAdPolicy)
        askAge = false
        startServicesAfterAgeStep()
    }

    /// A parent can switch to gentle mode at any time, no gate needed.
    func switchToGentleMode() {
        update { $0.age = AgeProfile(group: .child, source: .parentSetGentleMode, storefront: storefront) }
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
        let age = progress.age
        return AdPolicy.requestPolicy(group: age?.group ?? .child, storefront: policyStorefront,
                                      consent: ads.consentStatus,
                                      mayPersonalise: age?.mayPersonaliseAds ?? false,
                                      trackingAllowed: trackingAllowed)
    }

    /// Apple's tracking prompt, once, for eligible players only (never gentle mode).
    private func askTrackingIfDue(levelWon: Int) async {
        guard AdPolicy.shouldAskTracking(profile: progress.age, levelWon: levelWon, alreadyAsked: progress.trackingAsked) else { return }
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
