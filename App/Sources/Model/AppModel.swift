import AppTrackingTransparency
import Foundation
import StoreKit
import SwiftUI
import UIKit
import SquishCore
import SquishLevels
import SquishPolicy
import SquishSoft

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

    /// One-line bios and the secrets' riddles, by squishy id then language.
    private let bios: [String: [String: String]]
    private let riddles: [String: [String: String]]
    /// Display-only stats, 1 to 99: squish, bounce, stretch, charm. Nothing in the game reads them yet.
    private let stats: [String: [String: Int]]
    /// A duplicate just came out of a capsule or a swap: the spares it made, for "+1 spare".
    @Published private(set) var capsuleSpares: Int?
    @Published var screen: Screen = .level(0)
    @Published private(set) var progress: PlayerProgress
    @Published var capsule: Collectible?
    @Published var askAge = false
    /// One line before Apple's tracking prompt, shown over the board at the start of level 7.
    @Published var trackingExplainer = false
    /// A common that just joined the book by being sorted, for the board's sticker.
    @Published var joinedBook: Collectible?
    /// What the last win paid, for the win card.
    @Published private(set) var lastWin = WinSummary()
    /// A short line at the top of the screen that fades by itself.
    @Published var toast: String?
    /// Good news earned by the last win (a new place to play, a finished world), told
    /// one card at a time when the player moves on from the win card.
    @Published var news: [News] = []
    @Published var showingNews: News?
    private var afterNews: Int?

    enum News: Identifiable, Equatable {
        case unlocked(Extra)
        case worldComplete(world: String, next: String?)
        /// The Buddy learned its first, second or third trick.
        case trick(Int)
        /// A world's star jar reached its first, second or third prize.
        case starJar(world: String, prize: Int)

        var id: String {
            switch self {
            case .unlocked(let extra): return "extra-\(extra.rawValue)"
            case .worldComplete(let world, _): return "world-\(world)"
            case .trick(let number): return "trick-\(number)"
            case .starJar(let world, let prize): return "starjar-\(world)-\(prize)"
            }
        }
    }

    nonisolated static func worldName(_ id: String) -> LocalizedStringKey {
        switch id {
        case "toyshop": return "Toy Shop"
        case "sweetfactory": return "Sweet Factory"
        case "starlight": return "Starlight Stage"
        default: return christmasWorldName
        }
    }
    @Published var storefront = ""
    /// The Buddy's speech bubble on the home screen. Never shown during a level.
    @Published var buddySays: String?
    /// A trick the Buddy should do now on Home (1 spin, 2 flip, 3 dance). Home clears it.
    @Published var trickToShow: Int?
    /// The trick Home is teaching right now: everything else dims until the player has done it once.
    @Published var trickTeaching: Int?
    /// The trigger of the line being said ("joke", "fact", "poke", ...).
    private(set) var buddySaysKind = ""
    /// Goes up each time the daily gift is opened, so the home screen can throw the coins.
    @Published var giftsOpened = 0
    /// A treat or gift bought in the shop, on its way to the Buddy.
    @Published var buddyDelivery: Coins.Item?
    private var heartsBeforeDelivery = 0
    private var ultraJustOpened = false
    private var squeezeAfterCapsule: String?
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
    let sounds = SoundService()
    let ads = AdsService()
    private let store = ProgressStore()
    private var rng = SystemRandomNumberGenerator()
    private var sessionStart = Date()
    private var greetedThisSession = false
    private var thankedForAdThisSession = false
    /// The last win opened a capsule or unlocked an extra, so no forced ad follows it.
    private var lastWinHadReward = false
    /// Whether the capsule on screen is a squishy the player didn't have yet.
    @Published private(set) var capsuleIsNew = false

    /// UI tests start from a fresh install every time.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    init() {
        var loaded = AppModel.isUITesting ? PlayerProgress() : store.load()
        levels = AppModel.loadLevels()
        if loaded.version < 2 {
            loaded.migrate(path: levels.filter { LevelCatalog.worlds.contains($0.file.world) }.map(\.id))
            store.save(loaded)
        }
        progress = loaded
        roster = AppModel.loadRoster()
        let words = AppModel.loadBios()
        bios = words.bios
        riddles = words.riddles
        stats = words.stats
        config = RemoteConfig.cached()
        buddyScript = AppModel.loadBuddyScript()
        purchases = PurchaseService(cachedOwnership: loaded.ownsRemoveAds)
        haptics.enabled = loaded.hapticsOn
        sounds.enabled = loaded.soundOn
        sounds.level = Float(loaded.soundLevel)
        sounds.squishOn = loaded.squishSoundsOn
        sounds.buddyVoice = loaded.buddyVoiceOn
        sounds.musicLevel = loaded.musicOn ? Float(loaded.musicLevel) : 0
        // New players land straight on Level 1; the home screen arrives with the first capsule.
        screen = loaded.highestUnlocked >= 3 ? .home : .level(min(loaded.highestUnlocked, max(0, levels.count - 1)))
        // A save that already holds every other squishy of a world is owed that world's secret.
        for world in LevelCatalog.worlds + [ChristmasWorld.id] { queueSecretIfWon(world: world) }
        repairBuddyName()
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

    private static func loadBios() -> (bios: [String: [String: String]], riddles: [String: [String: String]],
                                       stats: [String: [String: Int]]) {
        guard let url = Bundle.main.url(forResource: "squishy-bios", withExtension: "json", subdirectory: "Content"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ([:], [:], [:]) }
        return (file["bios"] as? [String: [String: String]] ?? [:], file["riddles"] as? [String: [String: String]] ?? [:],
                file["stats"] as? [String: [String: Int]] ?? [:])
    }

    /// The four stats of a squishy in card order, or nil when it has none yet.
    func stats(for id: String) -> [Int]? {
        guard let s = stats[id] else { return nil }
        return ["squish", "bounce", "stretch", "charm"].map { min(99, max(1, s[$0] ?? 1)) }
    }

    /// A world's name as plain text, for tags and counts.
    func worldTitle(_ world: String) -> String {
        switch world {
        case "toyshop": return String(localized: "Toy Shop")
        case "sweetfactory": return String(localized: "Sweet Factory")
        case "starlight": return String(localized: "Starlight Stage")
        default:
            return ["US", "CA"].contains(Locale.current.region?.identifier ?? "")
                ? String(localized: "Santa's Workshop") : String(localized: "Santa's Grotto")
        }
    }

    /// The squishy's one-line bio in the player's language, or nil when it has none yet.
    func bio(for id: String) -> String? {
        guard let lines = bios[id] else { return nil }
        return lines[language] ?? lines["en"]
    }

    /// The riddle that says how a secret squishy is found.
    func riddle(for id: String) -> String? {
        guard let lines = riddles[id] else { return nil }
        return lines[language] ?? lines["en"]
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

    /// Levels on the main path come first in `levels`; side-world levels follow.
    var mainLevelCount: Int { levels.filter { LevelCatalog.worlds.contains($0.file.world) }.count }

    func isSideLevel(_ index: Int) -> Bool {
        levels.indices.contains(index) && !LevelCatalog.worlds.contains(levels[index].file.world)
    }

    /// The number on the board: 1 to 60 on the main path, 1 to 20 in a side world.
    func levelNumber(_ index: Int) -> Int {
        isSideLevel(index) ? levels[index].file.index : index + 1
    }

    // MARK: - Tester tools (TestFlight and debug builds only)

    /// True in debug builds and in TestFlight (sandbox receipt). The tools still stay
    /// hidden until the version line in Settings is tapped seven times.
    static var isTesterBuild: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    /// Opens the main path up to the first level of a world and goes there. Earlier levels
    /// that were not played count as won with one star, so the extras they open are there too.
    func testerStart(world: String) {
        guard AppModel.isTesterBuild,
              let first = levels.indices.first(where: { levels[$0].file.world == world && !isSideLevel($0) }) else { return }
        update { p in
            for i in 0..<first where !isSideLevel(i) && p.stars[levels[i].id] == nil { p.stars[levels[i].id] = 1 }
            p.highestUnlocked = max(p.highestUnlocked, first)
        }
        news = []
        showingNews = nil
        afterNews = nil
        levelCheer = nil
        screen = .level(first)
    }

    /// Back to a brand new player.
    func testerReset() {
        guard AppModel.isTesterBuild else { return }
        update { $0 = PlayerProgress() }
        // A new player has no known age: the ads go back to the strictest flags.
        ads.update(policy: currentAdPolicy)
        news = []
        showingNews = nil
        afterNews = nil
        levelCheer = nil
        screen = .level(0)
    }

    func isUnlocked(_ index: Int) -> Bool {
        guard levels.indices.contains(index) else { return false }
        if isSideLevel(index) {
            return progress.christmasEntered && levels[index].file.index - 1 <= progress.christmasUnlocked
        }
        return index <= progress.highestUnlocked
    }

    // MARK: - Santa's Grotto and the advent shelf

    /// "Santa's Workshop" in the US and Canada, "Santa's Grotto" everywhere else (Ian, 16 Nov).
    nonisolated static var christmasWorldName: LocalizedStringKey {
        ["US", "CA"].contains(Locale.current.region?.identifier ?? "") ? "Santa's Workshop" : "Santa's Grotto"
    }

    var christmasLevels: [Int] { levels.indices.filter { levels[$0].file.world == ChristmasWorld.id } }

    /// The festive door on the home screen. Once opened, the world stays for good.
    var showsFestiveDoor: Bool {
        !christmasLevels.isEmpty && showsCornerButtons
            && ChristmasWorld.doorShows(today: today, levelTenWon: levels.count > 9 && progress.stars[levels[9].id] != nil,
                                        entered: progress.christmasEntered, config: config)
    }

    func openFestiveDoor() {
        guard showsFestiveDoor else { return }
        if !progress.christmasEntered {
            update { $0.christmasEntered = true }
            sounds.play("sleigh")
        }
        if let next = christmasLevels.last(where: { isUnlocked($0) }) { screen = .level(next) }
    }

    /// Doors that can be open today (0 hides the shelf).
    var adventDoors: Int { showsCornerButtons ? Advent.doorsAvailable(today: today, config: config) : 0 }

    /// Doors opened this season (last year's doors don't count).
    var adventOpened: Set<Int> { progress.advent.openedDoors(season: config.christmasOpenFrom) }

    /// Opens one advent door. Rewards are fixed and need no ad.
    @discardableResult
    func openAdventDoor(_ day: Int) -> Advent.Reward? {
        // Read before `update`: nothing may read `progress` while it is being changed.
        let available = adventDoors
        var opened = false
        let season = config.christmasOpenFrom
        update { opened = $0.advent.open(day: day, available: available, season: season) }
        guard opened else { return nil }
        let reward = Advent.reward(day: day, rules: config.coins)
        sounds.play("sleigh")
        switch reward {
        case .coins(let amount):
            update { $0.wallet.earn(amount) }
            sounds.play("coin_shower")
        case .treats(let count):
            update { $0.buddy.treats += count }
            sounds.play("heart")
        case .capsuleStep:
            var full = false
            update { full = $0.mystery.addStep() }
            sounds.play("heart")
            if full { openCapsule(world: mysteryCapsuleWorld) }
        case .christmasCapsule:
            openCapsule(world: ChristmasWorld.id)
        }
        haptics.complete()
        return reward
    }

    /// Corner buttons (book, map, settings) appear after the first capsule.
    var showsCornerButtons: Bool { progress.highestUnlocked >= 3 }

    /// Where "back" and "home" lead: the home screen once it exists, else the current level.
    var homeScreen: Screen { showsCornerButtons ? .home : .level(progress.highestUnlocked) }

    // MARK: - Extras

    var levelsWon: Int { progress.stars.count }

    func isWorldComplete(_ world: String) -> Bool {
        let ids = levels.filter { $0.file.world == world }.map(\.id)
        return !ids.isEmpty && ids.allSatisfy { progress.stars[$0] != nil }
    }

    /// Stars earned in a world, and how many it has to give.
    func stars(inWorld world: String) -> (earned: Int, possible: Int) {
        let ids = levels.filter { $0.file.world == world }.map(\.id)
        return (ids.reduce(0) { $0 + (progress.stars[$1] ?? 0) }, ids.count * 3)
    }

    /// How many moves over the best answer still earn three stars. It starts roomy and tightens:
    /// 2 for the first five levels, 1 for the rest of the first world, then none at all except on
    /// a world's rests. A level with wrapped squishies always keeps one, because nobody can plan
    /// round what they cannot see.
    func starSlack(index: Int) -> Int {
        guard levels.indices.contains(index) else { return 2 }
        let level = levels[index]
        let beat = level.file.beat
        let wrapped = !(level.file.mechanics?.hidden ?? []).isEmpty
        var slack: Int
        if isSideLevel(index) {
            slack = 1
        } else {
            let number = index + 1
            let worldNumber = LevelCatalog.worlds.firstIndex(of: level.file.world) ?? 0
            if number <= 5 {
                slack = 2
            } else if worldNumber == 0 {
                slack = 1
            } else {
                slack = [Beat.intro, Beat.breather, Beat.calm].contains(beat) ? 1 : 0
            }
        }
        return wrapped ? max(1, slack) : slack
    }

    /// Shake-up: on a boss level from the second world on, the pieces are shuffled once, after
    /// this many moves. Nil where the level has none.
    func shakeUpMove(index: Int) -> Int? {
        guard levels.indices.contains(index), !isSideLevel(index), !AppModel.isUITesting else { return nil }
        let level = levels[index]
        guard level.file.beat == .boss, (LevelCatalog.worlds.firstIndex(of: level.file.world) ?? 0) >= 1 else { return nil }
        return max(4, level.par / 2)
    }

    // MARK: - Star jar

    static let starJarCoins = 300
    /// Marks a waiting capsule as golden (always an ultra).
    private static let goldenMark = "#gold"

    /// The stars a world's jar needs for its three prizes: a third, two thirds and all of them.
    func starJarGoals(_ world: String) -> [Int] {
        let possible = stars(inWorld: world).possible
        return [possible / 3, possible * 2 / 3, possible]
    }

    /// Prizes given so far in a world, 0 to 3.
    func starJarPrizes(_ world: String) -> Int { min(3, progress.starJarPrizes[world] ?? 0) }

    /// Stars come only from playing, so these capsules keep the rule that no ad or purchase gives one.
    /// Each prize is given once: coins, then a capsule from that world, then a golden capsule.
    private func awardStarJars() {
        for world in LevelCatalog.allWorlds {
            let goals = starJarGoals(world)
            let earned = stars(inWorld: world).earned
            guard goals[2] > 0 else { continue }
            var given = starJarPrizes(world)
            while given < 3, earned >= goals[given] {
                given += 1
                let prize = given
                update { p in
                    p.starJarPrizes[world] = prize
                    switch prize {
                    case 1: p.wallet.earn(AppModel.starJarCoins)
                    case 2: p.pendingCapsules.append(world)
                    default: p.pendingCapsules.append(world + AppModel.goldenMark)
                    }
                }
                news.append(.starJar(world: world, prize: prize))
            }
        }
    }

    var worldsCompleted: Int { LevelCatalog.allWorlds.filter { isWorldComplete($0) }.count }

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
        case .buddy: screen = homeScreen // lives on the home screen
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

    /// How a squeezable thing squishes. Made squishies, like anything with no feel of its own, are jelly.
    func feel(for ref: String) -> SquishFeel {
        if let c = roster.collectible(ref) { return SquishFeel(named: c.feel) }
        return SquishFeel(named: roster.squishRoomToys.first { $0.id == ref }?.feel)
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
        LevelCatalog.allWorlds.filter { world in
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
        update {
            earned = $0.mystery.recordGuess(correct: correct, today: today)
            // Any guess pays, right or wrong.
            $0.wallet.earn(config.coins.mysteryGuess)
        }
        sounds.play(correct ? "mystery_right" : "mystery_close")
        if earned {
            let world = mysteryCapsuleWorld
            update { $0.pendingCapsules.append(world) }
            openPendingCapsule(after: 1.6)
        }
        return correct
    }

    /// After a wrong guess: one more, once a day, by opt-in ad. Never in gentle mode.
    var offersExtraMysteryGuess: Bool {
        progress.mystery.canOfferExtraGuess(today: today) && canOptIn(.extraGuess)
    }

    func takeExtraMysteryGuess(_ ready: @escaping () -> Void) {
        guard offersExtraMysteryGuess else { return }
        optIn(.extraGuess) { [weak self] in
            guard let self else { return }
            self.update { $0.mystery.grantExtraGuess(today: self.today) }
            ready()
        }
    }

    private func isBookComplete(_ world: String) -> Bool {
        roster.collectibles.filter { $0.world == world && $0.rarity != .secret }
            .allSatisfy { progress.collection.owns($0.id) }
    }

    /// The Mystery Bag capsule opens for the world the player is in, or for
    /// another open world when that book is already complete. Never a locked world.
    private var mysteryCapsuleWorld: String {
        let open = openWorlds
        let current = levels.indices.contains(progress.highestUnlocked) ? levels[progress.highestUnlocked].file.world : ""
        let here = open.contains(current) ? current : (open.first ?? LevelCatalog.worlds[0])
        if isBookComplete(here), let other = open.first(where: { !isBookComplete($0) }) { return other }
        return here
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

    /// The Buddy says a line on Home. The trigger also picks the bubble's tint.
    func say(_ trigger: String) {
        buddySaysKind = trigger
        buddySays = buddyLine(trigger)
    }

    func buddyLine(_ trigger: String) -> String? {
        guard buddyActive else { return nil }
        return buddyScript.line(trigger, language: language, using: &rng)
    }

    /// Peach Bun asks "Can I be your Buddy?" on the first capsule screen.
    func adoptFirstBuddy(_ squishy: Collectible) {
        guard isExtraUnlocked(.buddy), progress.buddy.squishy == nil else { return }
        update {
            $0.buddy.squishy = squishy.id
            $0.buddy.name = squishy.name(in: language)
            $0.seenExtras.insert(Extra.buddy.rawValue)
        }
    }

    /// The squishy the Squish Room should open with (set by "Squeeze me" buttons, used once).
    var roomStart: String?

    /// Opens the Squish Room with this squishy in hand.
    func squeeze(_ ref: String) {
        guard isExtraUnlocked(.squishRoom), squeezables.contains(ref) else { return }
        roomStart = ref
        open(.squishRoom)
    }

    /// True when `name` is the roster name (in any language) of a squishy other than `ref`.
    private func isAnotherSquishysName(_ name: String, than ref: String) -> Bool {
        roster.collectibles.contains { c in
            c.id != ref && (c.name == name || c.names.values.contains(name))
        }
    }

    /// Build 3 could leave the Buddy wearing the name of the squishy it used to be.
    private func repairBuddyName() {
        guard let ref = progress.buddy.squishy, isAnotherSquishysName(progress.buddy.name, than: ref),
              let own = NameFilter.clean(displayName(for: ref)) else { return }
        update { $0.buddy.name = own }
    }

    var offersFirstBuddy: Bool { isExtraUnlocked(.buddy) && progress.buddy.squishy == nil }

    /// False when the name is empty or rude.
    func setBuddy(ref: String, name: String) -> Bool {
        guard isExtraUnlocked(.buddy), squeezables.contains(ref), let clean = NameFilter.clean(name) else { return false }
        // A name that is really another squishy's own name does not follow the Buddy to a new squishy.
        let kept = isAnotherSquishysName(clean, than: ref) ? (NameFilter.clean(displayName(for: ref)) ?? clean) : clean
        update { $0.buddy.squishy = ref; $0.buddy.name = kept; $0.seenExtras.insert(Extra.buddy.rawValue) }
        say("greet_back")
        return true
    }

    /// At most one unprompted line per home visit: a greeting on the first visit
    /// of a session, then now and then a joke, a fact or "How are you today?".
    func homeAppeared() {
        openPendingCapsule(after: 0.4)
        buddyAsksMood = false
        guard buddyActive else { buddySays = nil; return }
        let now = Date()
        let away = progress.buddy.lastOpenedAt.map { (now.timeIntervalSince1970 - $0) / 3600 }
        let first = !greetedThisSession
        if first {
            sounds.play("buddy_hello")
            greetedThisSession = true
            update { $0.buddy.lastOpenedAt = now.timeIntervalSince1970 }
        }
        let line = buddyScript.homeLine(firstVisitThisSession: first, hour: Calendar.current.component(.hour, from: now),
                                        hoursSinceLastOpen: away, moodAskedToday: progress.buddy.moodAskedDay == today,
                                        roll: Double.random(in: 0..<1, using: &rng))
        switch line {
        case .say(let trigger): say(trigger)
        case .askMood:
            update { $0.buddy.moodAskedDay = today }
            say("ask_mood")
            buddyAsksMood = buddySays != nil
        case .quiet: buddySays = nil
        }
    }

    /// The answer picks a reply and is then forgotten: never stored, never sent.
    func answerMood(_ mood: String) {
        buddyAsksMood = false
        say("reply_\(mood)")
    }

    func pokeBuddy() {
        haptics.land()
        sounds.play("buddy_giggle")
        buddyAsksMood = false
        say("poke")
    }

    func feedBuddy() {
        guard buddyActive, progress.buddy.treats > 0 else { return }
        let before = progress.buddy.hearts
        update { _ = $0.buddy.feedStoredTreat(); $0.buddy.lastTreatAt = Date().timeIntervalSince1970 }
        haptics.complete()
        sounds.play("buddy_yum", or: "buddy_munch")
        heartsChanged(from: before)
    }

    /// Hearts only ever add up: every 10 teach a trick, and each one makes the Buddy a little bigger.
    private func heartsChanged(from before: Int) {
        let now = progress.buddy.hearts
        if BuddyState.tricksKnown(hearts: now) > BuddyState.tricksKnown(hearts: before) {
            sounds.play("trick", or: "unlock_new")
            buddySays = String(localized: "I grew!")
            if showingNews == nil { showingNews = .trick(BuddyState.tricksKnown(hearts: now)) }
        } else if now / 5 > before / 5, Double(before) * BuddyState.growthPerHeart < BuddyState.maxGrowth {
            // Every fifth heart the Buddy says so; the growing itself shows on every treat.
            sounds.play("grow", or: "heart")
            buddySays = String(localized: "I grew!")
        } else {
            buddySays = String(localized: "Yum!")
        }
    }

    /// Treats and gifts bought with coins are given straight away.
    func buyForBuddy(_ item: Coins.Item) {
        guard buddyActive, item == .treat || item == .gift, spend(item) else { return }
        giveBuddy(item)
    }

    /// Bought in the shop: paid for and saved here in one go, so nothing can be lost. The home screen
    /// then plays the arrival, where the Buddy can be seen enjoying it.
    func buyForBuddyFromShop(_ item: Coins.Item) {
        guard buddyActive, buddyDelivery == nil, item == .treat || item == .gift, spend(item) else { return }
        heartsBeforeDelivery = progress.buddy.hearts
        applyToBuddy(item)
        buddyDelivery = item
        screen = homeScreen
    }

    /// The home screen calls this when the bought treat or gift reaches the Buddy: only the celebration is left to do.
    func deliverToBuddy() {
        guard let item = buddyDelivery else { return }
        buddyDelivery = nil
        celebrate(item, heartsBefore: heartsBeforeDelivery)
    }

    private func giveBuddy(_ item: Coins.Item) {
        let before = progress.buddy.hearts
        applyToBuddy(item)
        celebrate(item, heartsBefore: before)
    }

    private func applyToBuddy(_ item: Coins.Item) {
        update { $0.buddy.give(item); if item == .treat { $0.buddy.lastTreatAt = Date().timeIntervalSince1970 } }
    }

    private func celebrate(_ item: Coins.Item, heartsBefore before: Int) {
        haptics.complete()
        if item == .gift { sounds.play("gift_open", or: "heart") } else { sounds.play("buddy_yum", or: "buddy_munch") }
        heartsChanged(from: before)
    }

    /// How long a treat's puff lasts: a day for players of 13 and over. In gentle mode it is a short
    /// happy reaction, so nothing asks a child to come back in time.
    var puffSeconds: Double { isGentleMode ? BuddyState.puffSecondsGentle : BuddyState.puffSeconds }

    // MARK: - The Buddy's daily gift

    /// Once a day the Buddy holds a gift box of coins: by opt-in ad, or free in gentle mode.
    /// Waiting: the box is there today. Ready: it can be opened right now (a video is loaded if one is needed).
    var dailyGiftWaiting: Bool {
        guard buddyActive, progress.dailyGiftDay != today else { return false }
        if isGentleMode { return true }
        return progress.optInAds.canWatch(today: today, cap: config.optInAdsPerDay) && (ownsRemoveAds || config.adsEnabled)
    }

    var dailyGiftReady: Bool {
        dailyGiftWaiting && (isGentleMode || canOptIn(.dailyGift))
    }

    var dailyGiftNeedsVideo: Bool { !isGentleMode && !ownsRemoveAds }

    func takeDailyGift() {
        guard dailyGiftReady else { return }
        let grant: () -> Void = { [weak self] in
            guard let self else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                self.update { $0.dailyGiftDay = self.today; $0.wallet.earn(self.config.coins.dailyGift) }
                self.giftsOpened += 1
            }
            self.sounds.play("gift_open", or: "coin_shower")
            self.haptics.win()
            self.say("treat")
        }
        if isGentleMode { grant() } else { optIn(.dailyGift, granted: grant) }
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

    /// What a win paid. The pot is what the jars threw; the rest is added on the win card.
    struct WinSummary: Equatable {
        var pot = 0
        var starBonus = 0
        var streak = 0
        var streakBonus = 0
        var dailyBonus = 0
        /// Coins from today's stamp (stamps 1 to 6).
        var stampCoins = 0
        /// Today's stamp went on the card with this win; `stamps` is the card after it (0 = card just filled).
        var stamped = false
        var stamps = 0
        var firstClear = false
        var doubled = false
        /// The one soft Remove Ads line (after the 3rd interstitial ever, 13 and over).
        var offersRemoveAds = false
        /// The Buddy's free treat for this win: true = one more in the jar, false = the jar was full, nil = no Buddy yet.
        var treat: Bool?
        var buddyName = ""
        var total: Int { pot * (doubled ? 2 : 1) + starBonus + streakBonus + dailyBonus + stampCoins }
    }

    /// `pot` is what the level's jars threw on this attempt (0 on a replay).
    func won(index: Int, moves: Int, stars: Int, attempts: Int, playSeconds: Double, pot: Int) {
        let level = levels[index]
        let rules = config.coins
        // A level pays out once. Replays can raise the stars (and pay the
        // three-star bonus once) but never another capsule or more jar coins.
        let previousBest = progress.stars[level.id]
        let firstClear = previousBest == nil
        let extrasBefore = Extra.allCases.filter { isExtraUnlocked($0) }
        let worldWasComplete = isWorldComplete(level.file.world)
        var summary = WinSummary()
        summary.firstClear = firstClear
        summary.pot = firstClear ? pot : 0
        summary.starBonus = Coins.starBonus(stars: stars, previousBest: previousBest, rules: rules)
        let streak = Coins.nextStreak(current: progress.winStreak, firstClear: firstClear, attempts: attempts)
        if firstClear && !isGentleMode {
            summary.streak = streak
            summary.streakBonus = Coins.streakBonus(streak: streak, rules: rules)
        }
        summary.dailyBonus = progress.lastWinDay == today ? 0 : rules.firstWinOfDay
        summary.offersRemoveAds = RemoveAdsOffer.shouldShow(interstitialsShown: progress.cadence.interstitialsShown, group: ageGroup,
                                                            alreadyShown: progress.removeAdsOfferShown, ownsRemoveAds: ownsRemoveAds)
        // The first win of a day puts a stamp on the stamp card.
        var card = progress.stampCard
        var stampFillsBar = false
        // Not until level 3 has been won, so the first three win cards stay clean.
        let stampsOpen = progress.highestUnlocked >= 3
        if stampsOpen, let reward = card.stamp(today: today, rules: rules) {
            summary.stamped = true
            summary.stamps = card.stamps
            switch reward {
            case .coins(let amount): summary.stampCoins = amount
            case .capsuleStep: stampFillsBar = true
            }
        }
        if buddyActive {
            summary.treat = progress.buddy.treats < BuddyState.maxStoredTreats
            summary.buddyName = progress.buddy.name
        }
        let side = isSideLevel(index)
        var barFull = false
        update { p in
            p.stampCard = card
            if stampFillsBar { barFull = p.mystery.addStep() }
            p.wallet.earn(summary.total)
            p.winStreak = streak
            p.lastWinDay = today
            if summary.offersRemoveAds { p.removeAdsOfferShown = true }
            p.buddy.earnTreatForWin()
            p.stars[level.id] = max(previousBest ?? 0, stars)
            if side {
                p.christmasUnlocked = max(p.christmasUnlocked, min(level.file.index, LevelCatalog.levelCount(in: level.file.world) - 1))
            } else {
                p.highestUnlocked = max(p.highestUnlocked, min(index + 1, max(0, mainLevelCount - 1)))
            }
            AdCadence.recordPlayTime(playSeconds, &p.cadence)
            AdCadence.recordWin(&p.cadence)
        }
        lastWin = summary
        levelCheer = buddyLine(stars >= 3 ? "win_3star" : "win")
        let unlockedExtra = Extra.allCases.filter { isExtraUnlocked($0) } != extrasBefore
        lastWinHadReward = (firstClear && level.file.capsule) || unlockedExtra || barFull
        if unlockedExtra { sounds.play("unlock_new") }
        // Told when the player moves on from the win card. The Squish Room's card is queued
        // by the first capsule (see openCapsule), because that capsule is what unlocks it.
        if !worldWasComplete, isWorldComplete(level.file.world) {
            let order = LevelCatalog.worlds
            let next = order.firstIndex(of: level.file.world).flatMap { $0 + 1 < order.count ? order[$0 + 1] : nil }
            news.append(.worldComplete(world: level.file.world, next: next))
            update { $0.wallet.earn(config.coins.worldComplete) }
        }
        awardStarJars()
        // The Buddy is met in the first capsule itself ("Is this your Buddy?"), so it has no card.
        for extra in [Extra.mysteryBag, .maker] where isExtraUnlocked(extra) && !extrasBefore.contains(extra) {
            news.append(.unlocked(extra))
        }
        // A full capsule bar opens its capsule after the level's own, never on top of it.
        if barFull {
            let world = mysteryCapsuleWorld
            update { $0.pendingCapsules.append(world) }
        }
        if firstClear && level.file.capsule {
            openCapsule(world: level.file.world)
        } else {
            openPendingCapsule()
        }
    }

    /// Opens the next earned capsule that is still waiting, if nothing else is
    /// on screen. The queue is saved, and the capsule leaves it in the same save
    /// that adds its squishy to the book.
    private func openPendingCapsule() {
        guard capsule == nil, !askAge, progress.age != nil, let world = progress.pendingCapsules.first else { return }
        update { $0.pendingCapsules.removeFirst() }
        openCapsule(world: world)
    }

    private func openPendingCapsule(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.openPendingCapsule() }
    }

    /// The stamp card's seven rewards, for its full-size view.
    func stampReward(_ number: Int) -> StampCard.Reward { StampCard.reward(stamp: number, rules: config.coins) }

    /// "x2 coins" on the win card of a first clear: doubles the banked pot only.
    var offersDoubleCoins: Bool {
        lastWin.firstClear && lastWin.pot > 0 && !lastWin.doubled && canOptIn(.doubleCoins)
    }

    func doubleCoins() {
        guard offersDoubleCoins else { return }
        optIn(.doubleCoins) { [weak self] in
            guard let self, !self.lastWin.doubled else { return }
            self.update { $0.wallet.earn(self.lastWin.pot) }
            self.lastWin.doubled = true
            self.sounds.play("coin_shower")
        }
    }

    /// A jar of `kind` was completed. Commons join the book the first time.
    func jarSorted(kind: String) {
        guard let squishy = roster.collectible(kind) else { return }
        var added = false
        update { added = $0.collection.addSorted(squishy) }
        if added {
            joinedBook = squishy
            queueSecretIfWon(world: squishy.world)
        }
    }

    // MARK: - Boss levels

    /// The giant that guards a world's last level: the world's shape-shifter.
    func bossID(world: String) -> String {
        roster.collectibles.first { $0.world == world && $0.shapeshifter }?.id ?? "morphy"
    }

    /// The last level of a world: its finale.
    func isFinale(_ index: Int) -> Bool {
        guard levels.indices.contains(index) else { return false }
        let world = levels[index].file.world
        return levels.lastIndex { $0.file.world == world } == index
    }

    /// Levels still to win before the world's finale, counting from the level to play next: 3, 2 or 1.
    /// Nil when the finale is further off, is next, or is already won.
    func levelsToFinale(world: String) -> Int? {
        let own = levels.indices.filter { levels[$0].file.world == world }
        guard let last = own.last, progress.stars[levels[last].id] == nil,
              let next = own.first(where: { progress.stars[levels[$0].id] == nil }), isUnlocked(next) else { return nil }
        let left = last - next
        return (1...3).contains(left) ? left : nil
    }

    func bossSplashShown() {
        if !progress.bossSplashSeen { update { $0.bossSplashSeen = true } }
    }

    // MARK: - Collection

    static let secretMark = "#secret"

    /// Finding the last other squishy of a world brings its secret out: it is shown like a capsule
    /// find, straight after whatever is on screen now.
    private func queueSecretIfWon(world: String) {
        var state = progress.collection
        let mark = world + AppModel.secretMark
        guard !progress.pendingCapsules.contains(mark), state.awardSecret(world: world, roster: roster) != nil else { return }
        update { $0.pendingCapsules.insert(mark, at: 0) }
    }

    /// Owned squishies whose card has not been opened yet.
    var newSquishies: Int {
        roster.collectibles.filter { progress.collection.owns($0.id) && !progress.seenCards.contains($0.id) }.count
    }

    func cardSeen(_ id: String) {
        guard !progress.seenCards.contains(id) else { return }
        update { $0.seenCards.insert(id) }
    }

    func setGoalDone(_ goal: SetGoal, world: String) -> Bool {
        goal.isDone(world: world, roster: roster, state: progress.collection)
    }

    func setGoalClaimed(_ goal: SetGoal, world: String) -> Bool {
        progress.setGoalsClaimed.contains(goal.key(world: world))
    }

    /// Pays a finished set goal once. The whole-world goal pays nothing here: its prize is the secret squishy.
    @discardableResult
    func claimSetGoal(_ goal: SetGoal, world: String) -> Bool {
        guard goal.coins > 0, setGoalDone(goal, world: world), !setGoalClaimed(goal, world: world) else { return false }
        update {
            $0.setGoalsClaimed.insert(goal.key(world: world))
            $0.wallet.earn(goal.coins)
        }
        sounds.play("coin_shower")
        haptics.win()
        return true
    }

    /// Any set goal finished and not yet claimed, for the badge on the Collection button.
    var setGoalWaiting: Bool {
        for world in LevelCatalog.worlds + [ChristmasWorld.id] {
            for goal in SetGoal.allCases where goal.coins > 0 {
                if setGoalDone(goal, world: world) && !setGoalClaimed(goal, world: world) { return true }
            }
        }
        return false
    }

    /// "4 of 6" for the squishy's own set: commons with commons, rares with rares, the rest with the world.
    func setProgress(for squishy: Collectible) -> (goal: SetGoal, found: Int, of: Int) {
        let goal: SetGoal = squishy.rarity == .common ? .commons : (squishy.rarity == .rare ? .rares : .world)
        let p = goal.progress(world: squishy.world, roster: roster, state: progress.collection)
        return (goal, p.found, p.of)
    }

    /// Levels still to win before the next capsule level, counting from the level after `index`.
    /// 0 means the next level is a capsule level. Nil when the world path has none left.
    func levelsToNextCapsule(after index: Int) -> Int? {
        let end = isSideLevel(index) ? levels.count : mainLevelCount
        guard index + 1 < end else { return nil }
        return levels[(index + 1)..<end].firstIndex { $0.file.capsule }.map { $0 - index - 1 }
    }

    /// The lucky squishy's kind on this level for this player, if it has one and it still pays.
    func luckyKind(index: Int) -> Int? {
        let level = levels[index]
        guard progress.stars[level.id] == nil else { return nil }
        return Coins.luckyKind(levelNumber: isSideLevel(index) ? progress.stars.count + 1 : index + 1, levelID: level.id,
                               installSeed: progress.installID, kinds: level.kinds.count, rules: config.coins)
    }

    func failed(playSeconds: Double) {
        update { AdCadence.recordPlayTime(playSeconds, &$0.cadence) }
        sounds.play("stuck")
        levelCheer = buddyLine("fail")
    }

    func next(after index: Int) {
        let n = index + 1
        levelCheer = nil
        // The main path never rolls on into a side world.
        let samePath = isSideLevel(n) == isSideLevel(index)
        screen = samePath && isUnlocked(n) ? .level(n) : homeScreen
    }

    // MARK: - Capsules

    private func openCapsule(world waiting: String) {
        if waiting.hasSuffix(AppModel.secretMark) {
            // A secret is not in a capsule: it comes out of hiding when the rest of its world is found.
            let world = String(waiting.dropLast(AppModel.secretMark.count))
            var state = progress.collection
            if let secret = state.awardSecret(world: world, roster: roster) {
                update { $0.collection = state }
                capsuleIsNew = true
                capsuleSpares = nil
                capsule = secret
            }
            return
        }
        let golden = waiting.hasSuffix(AppModel.goldenMark)
        let world = golden ? String(waiting.dropLast(AppModel.goldenMark.count)) : waiting
        var state = progress.collection
        if let got = CapsuleDrops.open(world: world, roster: roster, state: &state, rng: &rng, odds: config.capsuleOdds,
                                       force: golden ? .ultra : nil) {
            capsuleIsNew = !progress.collection.owns(got.id)
            capsuleSpares = capsuleIsNew ? nil : state.spareCount
            let roomWasOpen = isExtraUnlocked(.squishRoom)
            update { $0.collection = state }
            capsule = got
            queueSecretIfWon(world: world)
            // The first capsule opens the Squish Room: its card is told at the next "Next".
            if !roomWasOpen, isExtraUnlocked(.squishRoom), !news.contains(.unlocked(.squishRoom)) {
                news.append(.unlocked(.squishRoom))
            }
        }
    }

    /// The odds shown in the book always come from the same config the drops use.
    var capsuleOddsPercent: (rare: Int, ultra: Int) {
        let total = max(1, config.capsuleOdds.rare + config.capsuleOdds.ultra)
        let rare = Int((Double(config.capsuleOdds.rare) / Double(total) * 100).rounded())
        return (rare, 100 - rare)
    }

    /// Closes the capsule screen. The birthday question after the first capsule
    /// waits for `capsuleDismissed`, because nothing can be presented while the
    /// cover is still closing.
    func capsuleClosed() {
        if capsule?.rarity == .ultra { ultraJustOpened = true }
        capsule = nil
    }

    /// Called by the capsule cover's onDismiss.
    func capsuleDismissed() {
        let ultra = ultraJustOpened
        ultraJustOpened = false
        if progress.age == nil {
            askAge = true
        } else if let ref = squeezeAfterCapsule {
            // "Squeeze me!" on the capsule: straight to the Squish Room with the new squishy.
            squeezeAfterCapsule = nil
            squeeze(ref)
        } else {
            openPendingCapsule()
            if ultra, capsule == nil { maybeAskForRating(at: .ultraCapsule) }
        }
    }

    /// "Squeeze me!" on the capsule screen, offered once the Squish Room is open and
    /// nothing else (good news, another capsule) is waiting to be shown.
    var offersSqueezeFromCapsule: Bool {
        isExtraUnlocked(.squishRoom) && progress.age != nil && news.isEmpty && progress.pendingCapsules.isEmpty
            && progress.buddy.squishy != nil
    }

    func squeezeFromCapsule(_ ref: String) {
        guard offersSqueezeFromCapsule else { capsuleClosed(); return }
        squeezeAfterCapsule = ref
        levelCheer = nil
        capsuleClosed()
    }

    func rerollSpares(world: String) -> Collectible? {
        var state = progress.collection
        let got = CapsuleDrops.rerollSpares(world: world, roster: roster, state: &state, rng: &rng, odds: config.capsuleOdds)
        if let got {
            update { $0.collection = state }
            // The swap's squishy arrives in a capsule, like any other rare find.
            capsuleIsNew = true
            capsuleSpares = nil
            capsule = got
            queueSecretIfWon(world: world)
        }
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
        // The age sheet has to finish closing before a waiting capsule can show.
        openPendingCapsule(after: 0.8)
    }

    /// A parent can switch to gentle mode at any time, no gate needed. Ad flags
    /// change at once and any ad loaded under the old flags is thrown away.
    func switchToGentleMode() {
        update { $0.age = AgeProfile(group: .child, source: .parentSetGentleMode, storefront: storefront) }
        ads.update(policy: currentAdPolicy)
    }

    /// Ads SDK and telemetry start only here, after the age step, with flags for the group.
    private func startServicesAfterAgeStep() {
        guard let age = progress.age, config.adsEnabled else { return }
        _ = age
        let policy = currentAdPolicy
        let muted = !progress.soundOn
        Task {
            await ads.start(policy: policy)
            ads.setMuted(muted)
        }
        // The first-open counter joins here with the backend; children send counts only.
    }

    // MARK: - Ads

    private var trackingAllowed: Bool { ATTrackingManager.trackingAuthorizationStatus == .authorized }

    var currentAdPolicy: AdRequestPolicy {
        AdPolicy.requestPolicy(profile: progress.age, storefront: storefront, consent: ads.consentStatus,
                               trackingAllowed: trackingAllowed)
    }

    /// Settings > Privacy choices: reopens Google's consent form, then applies the new answer.
    var showsPrivacyChoices: Bool { progress.age != nil && ads.privacyOptionsRequired }

    func showPrivacyChoices() {
        Task {
            await ads.showPrivacyOptions()
            ads.update(policy: currentAdPolicy)
        }
    }

    /// Apple's tracking prompt, once, for eligible players only (never gentle mode).
    /// Called when a board comes on screen. From level 7 the explainer line
    /// shows once, and its button leads to Apple's prompt.
    func levelStarted(number: Int) {
        guard !AppModel.isUITesting,
              AdPolicy.shouldAskTracking(profile: progress.age, storefront: storefront, levelStarting: number,
                                         alreadyAsked: progress.trackingAsked) else { return }
        trackingExplainer = true
    }

    func askTracking() {
        guard trackingExplainer else { return }
        trackingExplainer = false
        update { $0.trackingAsked = true }
        Task {
            _ = await ATTrackingManager.requestTrackingAuthorization()
            ads.update(policy: currentAdPolicy)
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
        // Good news comes first, and no ad ever follows it.
        if !news.isEmpty {
            afterNews = index
            let first = news.removeFirst()
            // The world complete screen brings its own fanfare.
            if case .worldComplete = first {} else { sounds.play("win_boss"); haptics.win() }
            showingNews = first
            return
        }
        showInterstitialThenNext(index: index, attempts: attempts)
    }

    /// The player has read a news card. `open` goes straight to the new place.
    func newsRead(open: Bool = false) {
        let read = showingNews
        // A trick just learned is done straight away, as soon as its card is closed.
        if case .trick(let number) = read { trickToShow = number }
        if case .worldComplete = read { maybeAskForRating(at: .worldComplete) }
        if open, case .unlocked(let extra) = read {
            news = []
            showingNews = nil
            afterNews = nil
            levelCheer = nil
            self.open(extra)
            return
        }
        if !news.isEmpty {
            showingNews = news.removeFirst()
            sounds.play("unlock_new")
            return
        }
        showingNews = nil
        if let index = afterNews {
            afterNews = nil
            next(after: index)
        }
    }

    private func showInterstitialThenNext(index: Int, attempts: Int) {
        let level = levels[index]
        // Ad tiers count every level cleared, on the main path and in side worlds.
        let win = LevelWin(level: max(progress.stars.count, isSideLevel(index) ? 0 : index + 1), attempts: attempts, isBoss: level.file.beat == .boss,
                           secondsIntoSession: Date().timeIntervalSince(sessionStart), hadReward: lastWinHadReward)
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

    /// Whether an opt-in reward can be offered now: right for the age group,
    /// under the daily cap, and either an ad is ready or the player owns Remove Ads.
    func canOptIn(_ reward: OptInReward) -> Bool {
        reward.isOffered(to: ageGroup) && progress.optInAds.canWatch(today: today, cap: config.optInAdsPerDay)
            && (ownsRemoveAds || canWatchRewarded)
    }

    /// Remove Ads owners get the reward with one tap and no ad, under the same daily cap.
    func optIn(_ reward: OptInReward, granted: @escaping () -> Void) {
        guard canOptIn(reward) else { return }
        if ownsRemoveAds {
            update { $0.optInAds.record(today: today) }
            granted()
            return
        }
        ads.showRewarded { [weak self] earned in
            guard let self, earned else { return }
            // A watched opt-in ad counts as the ad break.
            self.update { AdCadence.recordRewardedWatched(&$0.cadence); $0.optInAds.record(today: self.today) }
            granted()
            if !self.thankedForAdThisSession {
                self.thankedForAdThisSession = true
                self.toast = String(localized: "Thanks! No ad breaks for a while.")
            }
        }
    }

    /// Apple's star pop-up, once, at a happy moment. Never in gentle mode.
    private func maybeAskForRating(at moment: RatingPrompt.Moment) {
        guard RatingPrompt.shouldAsk(at: moment, group: ageGroup, alreadyAsked: progress.ratingAsked) else { return }
        update { $0.ratingAsked = true }
        askForRating()
    }

    private func askForRating() {
        guard !AppModel.isUITesting,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        AppStore.requestReview(in: scene)
    }

    // MARK: - Helpers

    var undoLimit: Int? { ownsRemoveAds ? nil : 5 }

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

    /// Ads are told when the game's sound is off, so they start muted too.
    func setSound(_ on: Bool) {
        update { $0.soundOn = on }
        sounds.enabled = on
        ads.setMuted(!on)
    }

    /// The Sounds slider. All the way down is the same as off, so ads start muted too.
    func setSoundLevel(_ level: Double) {
        let level = min(1, max(0, level))
        update { $0.soundLevel = level; $0.soundOn = level > 0 }
        sounds.level = Float(level)
        sounds.enabled = level > 0
        ads.setMuted(level <= 0)
    }

    func setMusicLevel(_ level: Double) {
        let level = min(1, max(0, level))
        update { $0.musicLevel = level; $0.musicOn = level > 0 }
        sounds.musicLevel = Float(level)
    }

    func setSquishSounds(_ on: Bool) {
        update { $0.squishSoundsOn = on }
        sounds.squishOn = on
    }

    func setBuddyVoice(_ on: Bool) {
        update { $0.buddyVoiceOn = on }
        sounds.buddyVoice = on
    }

    func setHaptics(_ on: Bool) {
        update { $0.hapticsOn = on }
        haptics.enabled = on
    }
}
