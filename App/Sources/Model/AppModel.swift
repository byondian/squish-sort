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
    }

    @Published var screen: Screen = .level(0)
    @Published private(set) var progress: PlayerProgress
    @Published var capsule: Collectible?
    @Published var askAge = false
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

    init() {
        let loaded = store.load()
        progress = loaded
        levels = AppModel.loadLevels()
        roster = AppModel.loadRoster()
        config = GameConfig() // remote config fetch arrives with the backend
        purchases = PurchaseService(cachedOwnership: loaded.ownsRemoveAds)
        haptics.enabled = loaded.hapticsOn
        screen = .level(min(loaded.highestUnlocked, max(0, levels.count - 1)))
        purchases.onChange = { [weak self] owns in self?.update { $0.ownsRemoveAds = owns } }
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
            p.stars[level.id] = max(p.stars[level.id] ?? 0, stars)
            p.highestUnlocked = max(p.highestUnlocked, min(index + 1, levels.count - 1))
            AdCadence.recordPlayTime(playSeconds, &p.cadence)
            AdCadence.recordWin(&p.cadence)
        }
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
        update { $0.age = AgeProfile(group: group, source: source, storefront: storefront) }
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
        let policy = AdPolicy.requestPolicy(group: age.group, storefront: policyStorefront, consent: .unknown)
        Task { await ads.start(policy: policy) }
        // The first-open counter joins here with the backend; children send counts only.
    }

    // MARK: - Ads

    /// After a win: maybe an interstitial (never after a fail, never mid-level), then continue.
    func continueAfterWin(index: Int, attempts: Int) {
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
