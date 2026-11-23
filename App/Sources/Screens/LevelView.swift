import SpriteKit
import SwiftUI
import SquishCore
import SquishLevels
import SquishPolicy

/// One attempt at a level: owns the GameSession and the SpriteKit scene.
@MainActor
final class LevelController: ObservableObject {
    enum Outcome: Equatable {
        case won(stars: Int)
        case stuck
    }

    let index: Int
    let level: Level
    let scene: BoardScene
    @Published private(set) var session: GameSession
    @Published private(set) var outcome: Outcome?
    /// Paid-for helper choice sheet: watch an ad or spend coins.
    @Published var choosing: Coins.Item?
    /// Coins the jars have thrown on this attempt. Banked on the win; a retry empties it.
    @Published private(set) var pot: LevelPot
    private var jarsDone = 0
    /// Squishy streak: moves that land on a match, one soon after another.
    private var chain: SortChain
    private var landsOnMatch = false
    /// Squish Fever: a streak of eight matching moves makes the next five moves free.
    static let feverStreak = SortChain.Word.onARoll
    static let feverMoves = 5
    @Published private(set) var feverLeft = 0
    private var feverCoins = 0
    private var lastMoveWasFever = false
    /// Free moves left before each move in the session's history, so undo gives them back.
    private var feverBefore: [Int] = []
    /// Shake-up: the move count at which the pieces are shuffled. Nil when there is none (left),
    /// or once a jar has been filled in time, which calls it off.
    @Published private(set) var shakeAt: Int?
    @Published private(set) var shaking = false
    /// The finale's giant: 0 watching, 1 gasp, 2 nervous (one jar to go), 3 cheer.
    @Published private(set) var bossMood = 0
    /// Shuffles used on this try: the first is free, the rest cost coins.
    @Published private(set) var shufflesUsed = 0
    /// The one opt-in video shuffle of this try has been used (offered on the stuck screen only).
    @Published private(set) var videoShuffleUsed = false
    /// A paid shuffle was tapped without enough coins.
    @Published private(set) var shuffleShort = false
    /// Moves left before the shake-up.
    var shakeIn: Int? { shakeAt.map { max(0, $0 - session.moveCount) } }
    /// Bonus levels are Coin Rush: every finished jar throws double on a first clear.
    private var jarMultiplier: Int { level.file.beat == .bonus ? 2 : 1 }
    /// The hint search is running.
    @Published private(set) var thinking = false
    /// The hint search found no way to win from here. Nothing is charged for that.
    @Published var noWayThrough = false
    /// The magic move on its way to the board, and whether coins pay for it.
    private var magicPending: (move: Move, paid: Bool)?
    /// Lucky bonuses: one from a finished jar and one magic shuffle at most in a try.
    private var luckyUsed = false
    private var rescueUsed = false
    /// The hint search ran out of room without an answer. Nothing is charged for that either.
    @Published var hintGaveUp = false
    /// A hint found for the current board, waiting to be paid for or shown.
    private var foundHint: (board: Board, move: Move)?
    private(set) var attempts = 1
    private var started = Date()
    private weak var model: AppModel?
    /// Moves over the best answer that still earn three stars on this level.
    let starSlack: Int

    init(index: Int, model: AppModel) {
        self.index = index
        self.model = model
        level = model.levels[index]
        starSlack = model.starSlack(index: index)
        session = GameSession(board: level.board, par: level.par, undoLimit: model.undoLimit, starSlack: starSlack)
        scene = BoardScene(board: level.board, kinds: level.kinds)
        scene.world = level.look
        scene.goldRims = level.file.beat == .boss
        chain = SortChain(timed: !model.isGentleMode)
        let lucky = model.luckyKind(index: index)
        pot = LevelPot(firstClear: !model.playingDaily && model.progress.stars[level.id] == nil, jars: level.kinds.count,
                       luckyKind: lucky, jarMultiplier: level.file.beat == .bonus ? 2 : 1, rules: model.config.coins)
        scene.luckyKind = lucky.map { UInt8($0) }
        scene.onPlay = { [weak self] move in self?.play(move) }
        scene.onLift = { [weak model] in
            model?.haptics.lift()
            model?.sounds.play("lift")
        }
        scene.onLidTwist = { [weak model] in
            model?.sounds.play("capsule_click")
            model?.haptics.land()
        }
        // Each kind of move has its own sound when a finished jar shows off.
        scene.onSignature = { [weak model] effect, sound in
            guard let model else { return }
            if let sound, Bundle.main.url(forResource: sound, withExtension: "wav") != nil { model.sounds.play(sound, volume: 0.8); return }
            let name: String
            switch effect {
            case "BURST": name = "pop"
            case "VORTEX": name = "combo_3"
            case "GLOW": name = "star_2"
            case "PUFF": name = "grow"
            case "MELT": name = "splat"
            case "LIFT", "SPLIT": name = "hop"
            case "LIMB", "ROPE": name = "squeak_high"
            case "SOUND": name = "squeak_low"
            default: name = "trick"
            }
            model.sounds.play(name, volume: 0.7)
        }
        scene.onCurtainDrum = { [weak model] in model?.sounds.play("drumroll", volume: 0.6) }
        scene.onCurtainUp = { [weak model] in
            model?.sounds.play("curtain")
            model?.sounds.play("star_2", volume: 0.7)
            model?.haptics.star()
        }
        scene.onBubblePop = { [weak model] in
            model?.sounds.play("bubble_pop")
            model?.haptics.star()
        }
        scene.onVineSnap = { [weak model] in
            model?.sounds.play("vine_snap")
            model?.haptics.star()
        }
        let bubbles = level.look == "bubblebath"
        scene.onReject = { [weak model] in
            model?.haptics.reject()
            model?.sounds.play("reject")
        }
        scene.onLand = { [weak self, weak model] result in
            model?.sounds.move(run: result.count)
            self?.landed()
            if !result.thawedJars.isEmpty { model?.sounds.play(bubbles ? "bubble_pop" : "thaw") }
            if result.duetLetGo { self?.duetLetGo(atJar: result.move.destination) }
            if let jar = result.completedJar {
                model?.haptics.complete()
                self?.jarCompleted(jar)
            } else {
                model?.haptics.land()
            }
        }
        scene.onMoveFinished = { [weak self] _ in
            self?.checkOutcome()
            self?.shakeUpIfDue()
        }
        shakeAt = model.shakeUpMove(index: index)
        // The very first board opens mid-move: one squishy already lifted and a
        // hand on the jar it belongs in, so the first tap finishes a jar.
        if index == 0, model.progress.stars.isEmpty, let first = level.solution.first {
            scene.tutorialMove = first
        }
    }

    /// A duet landed on its own kind and let go: "Encore!" and a few coins the first time through.
    private func duetLetGo(atJar jar: Int) {
        guard let model else { return }
        let duets = level.board.jars.joined().filter { $0.bondedAbove }.count
        let coins = pot.encore(duetsInLevel: duets)
        scene.popLabel(String(localized: "Encore!"), atJar: jar)
        model.sounds.play("duet", or: "double_pop")
        model.haptics.complete()
        if coins > 0 {
            scene.throwCoins(fromJar: jar, count: 3)
            model.sounds.coin()
        }
    }

    /// After a rule's demo, the hand shows a good first move on the real board.
    func pointAtFirstMove() {
        guard session.moveCount == 0, let first = level.solution.first else { return }
        scene.tutorialMove = first
        scene.reload(session.board)
    }

    private func play(_ move: Move) -> (MoveResult, Board)? {
        let ontoMatch = session.board.jars.indices.contains(move.destination) && !session.board.jars[move.destination].isEmpty
        let free = feverLeft > 0
        let before = feverLeft
        // A magic move is only used up (or paid for) when it really lands.
        let pending = magicPending
        magicPending = nil
        guard !shaking, let result = session.play(move, free: free) else { return nil }
        if let pending, pending.move == move, let model {
            if pending.paid { _ = model.spend(.hint) } else { model.useMagicMove() }
            model.sounds.play("trick", or: "star_2")
        }
        feverBefore.append(before)
        lastMoveWasFever = free
        if free { feverLeft -= 1 }
        landsOnMatch = ontoMatch
        // The game never looks ahead for the player: while a move is open it says nothing (Ian, 17 Nov).
        noWayThrough = false; hintGaveUp = false
        return (result, session.board)
    }

    /// A move has landed: it may earn a squishy streak word. Nothing shows when a streak ends.
    private func landed() {
        guard let model else { return }
        let earned = chain.move(ontoMatch: landsOnMatch, at: Date().timeIntervalSince(started))
        if lastMoveWasFever {
            // Each free pour rings a note higher. The last one ends the fever, after its jar has paid.
            model.sounds.star(LevelController.feverMoves - feverLeft)
            if feverLeft == 0 { DispatchQueue.main.async { [weak self] in self?.endFever() } }
        }
        guard let word = earned else { return }
        if word == LevelController.feverStreak, feverLeft == 0, !lastMoveWasFever {
            _ = pot.streakWord(word)
            startFever()
            return
        }
        let text: String
        switch word {
        case .nice: text = String(localized: "Nice!")
        case .streak: text = String(localized: "Squishy streak!")
        case .onARoll: text = String(localized: "On a roll!")
        case .unstoppable: text = String(localized: "Unstoppable!")
        }
        scene.popWord(text, size: 0.7 + 0.1 * CGFloat(word.rawValue))
        model.sounds.play("combo_\(word.rawValue)", or: "run_x3")
        // A stronger tap each step.
        switch word {
        case .nice: model.haptics.land()
        case .streak: model.haptics.complete()
        case .onARoll, .unstoppable: model.haptics.win()
        }
        // On a first clear the word adds to the level pot.
        let coins = pot.streakWord(word)
        if coins > 0 {
            scene.throwCoins(fromJar: 0, count: 2 + word.rawValue)
            model.sounds.coin()
        }
    }

    /// Now and then a finished jar brings a free surprise: a magic move or a hint. Never sold, never
    /// after an ad, the same for every player; not on the jar that wins the level.
    private func luckyBonus(atJar jar: Int) {
        guard let model, !AppModel.isUITesting, !model.playingDaily, !session.board.isWon else { return }
        var rng = SystemRandomNumberGenerator()
        guard let bonus = Coins.luckyBonus(levelNumber: index + 1, alreadyThisTry: luckyUsed,
                                           magicHeld: model.progress.magicMoves, rng: &rng) else { return }
        luckyUsed = true
        model.sounds.play("lucky")
        model.haptics.star()
        switch bonus {
        case .magicMove:
            model.grantMagicMove()
            scene.popLabel(String(localized: "Magic move!"), atJar: jar)
        case .hint:
            scene.popLabel(String(localized: "Lucky hint!"), atJar: jar)
            // Once the jar has settled, the next good move lights up. Nothing is charged.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.luckyHint() }
        }
    }

    private func luckyHint() {
        guard !thinking, !shaking, outcome == nil else { return }
        let board = session.board
        Task {
            let found = await Task.detached(priority: .userInitiated) { [level = self.level] in level.hint(for: board) }.value
            guard board == session.board, outcome == nil, case .move(let move) = found else { return }
            scene.showHint(move)
        }
    }

    /// Commons join the book the first time a jar of them is completed.
    private func jarCompleted(_ jar: Int) {
        guard let model, let piece = session.board.jars[jar].first, level.kinds.indices.contains(Int(piece.kind)) else { return }
        model.jarSorted(kind: level.kinds[Int(piece.kind)])
        jarsDone += 1
        model.sounds.jarComplete(number: jarsDone)
        luckyBonus(atJar: jar)
        // A jar filled before the countdown runs out calls the shake-up off for this try.
        if shakeAt != nil, !session.board.isWon { shakeStopped() }
        if level.file.beat == .boss {
            bossMood = 1
            let oneLeft = session.board.jars.indices.filter { session.board.isComplete($0) }.count == level.kinds.count - 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.bossMood == 1 else { return }
                self.bossMood = oneLeft ? 2 : 0
            }
        }
        // First clear: the jar throws its share of coins into the level pot.
        var payout = pot.jarCompleted(kind: Int(piece.kind), at: Date().timeIntervalSince(started))
        if lastMoveWasFever {
            // A jar finished in a fever pays double.
            let extra = pot.feverBonus(payout.coins)
            payout.coins += extra
            feverCoins += payout.coins
        }
        guard payout.coins > 0 else { return }
        scene.throwCoins(fromJar: jar, count: min(10, max(3, payout.coins / 6)))
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45 + 0.09 * Double(i)) { [weak model] in model?.sounds.coin() }
        }
        if payout.lucky {
            model.sounds.play("lucky")
            model.sounds.play("coin_shower")
            scene.popLabel(String(localized: "Lucky!"), atJar: jar)
        } else if payout.doublePop {
            model.sounds.play("double_pop")
            scene.popLabel(String(localized: "Double pop!"), atJar: jar)
        }
    }

    // MARK: - Squish Fever

    private func startFever() {
        guard let model else { return }
        feverLeft = LevelController.feverMoves
        feverCoins = 0
        scene.setFever(true)
        scene.popWord(String(localized: "SQUISH FEVER!"), size: 1.05)
        model.sounds.play("streak", or: "run_x3")
        model.haptics.win()
    }

    private func endFever() {
        guard feverLeft == 0, scene.feverOn else { return }
        scene.setFever(false)
        guard let model, feverCoins > 0, outcome == nil else { return }
        scene.popWord("+\(feverCoins)", size: 0.9)
        model.sounds.play("coin_shower")
    }

    // MARK: - Shake-up

    /// The pieces in unfinished jars land in new spots. The new layout is always one that can be
    /// solved, and the star limit starts again from it, so a shake-up never costs stars.
    private func shakeUpIfDue() {
        guard let at = shakeAt, session.moveCount >= at, session.status == .playing, !shaking else { return }
        shakeAt = nil
        shake(word: String(localized: "Shake-up!"), keepsStarLimit: false) { _ in }
    }

    private func shakeStopped() {
        shakeAt = nil
        scene.popWord(String(localized: "Shake-up stopped!"), size: 0.8)
        model?.sounds.play("star_2")
        model?.haptics.star()
    }

    /// Coins call the shake-up off too, for the price of a hint. Never offered in gentle mode:
    /// paying to dodge a setback is a pressure mechanic, and filling a jar stops it for free.
    var canPayToStopShake: Bool {
        guard let model, shakeAt != nil, outcome == nil, !shaking else { return false }
        return !model.isGentleMode && session.status == .playing
    }

    func payToStopShake() {
        guard let model, canPayToStopShake else { return }
        guard model.spend(.hint) else {
            // No shop offer from the board: just say what is in the purse.
            shuffleShort = true
            model.haptics.reject()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in self?.shuffleShort = false }
            return
        }
        shakeStopped()
    }

    /// The Shuffle button: the first shuffle on a level is free, later ones cost coins. The moves so far
    /// stay counted and the star limit does not move. Nothing is charged when no new layout is found.
    func shuffle() {
        guard let model, canShuffleNow else { return }
        let paid = shufflesUsed > 0
        if paid && !model.progress.wallet.canAfford(.shuffle) {
            // No shop offer from the board: just say what is in the purse.
            shuffleShort = true
            model.haptics.reject()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in self?.shuffleShort = false }
            return
        }
        shake(word: String(localized: "Shuffle!"), keepsStarLimit: true) { [weak self] done in
            guard let self, done else { return }
            if paid { _ = model.spend(.shuffle) }
            self.shufflesUsed += 1
        }
    }

    /// The shuffle works while playing and from the stuck screen, never after a win.
    private var canShuffleNow: Bool {
        if shaking { return false }
        if case .won = session.status { return false }
        if case .some(.won) = outcome { return false }
        return true
    }

    /// The next shuffle costs nothing (the first of a try).
    var shuffleIsFree: Bool { shufflesUsed == 0 }

    /// One opt-in video shuffle a try, from the stuck screen. Remove Ads owners get it without the video.
    func videoShuffle() {
        guard let model, canShuffleNow, !videoShuffleUsed else { return }
        model.optIn(.shuffle) { [weak self] in
            guard let self else { return }
            self.videoShuffleUsed = true
            self.shake(word: String(localized: "Shuffle!"), keepsStarLimit: true) { _ in }
        }
    }

    /// Everything trembles, then the pieces in unfinished jars fly to new spots.
    private func shake(word: String, keepsStarLimit: Bool, kindest: Bool = false, then: @escaping (Bool) -> Void) {
        guard let model else { return }
        shaking = true
        magicPending = nil
        chain.end()
        feverLeft = 0
        feverBefore = []
        scene.setFever(false)
        scene.clearSelection()
        model.sounds.play("drumroll")
        model.haptics.complete()
        scene.tremble(seconds: 1.1)
        let board = session.board
        // From the stuck screen the card steps aside while the pieces fly.
        let wasStuck = outcome == .stuck
        if wasStuck { outcome = nil }
        Task {
            let found: (board: Board, best: Int)? = await Task.detached(priority: .userInitiated) { () -> (board: Board, best: Int)? in
                var rng = SystemRandomNumberGenerator()
                // Never hold the board for long: stop looking after about a second and a half.
                let deadline = Date().addingTimeInterval(1.5)
                var best: (board: Board, best: Int)?
                for _ in 0..<14 {
                    if Date() > deadline { break }
                    let next = board.shakenUp(using: &rng)
                    if next == board || next.isWon || next.isStuck { continue }
                    if next.jars.indices.contains(where: { next.isComplete($0) && !board.isComplete($0) }) { continue }
                    if let result = Solver.solve(next, maxStates: 60_000), result.moves.count >= 2 {
                        // A magic shuffle keeps looking for the layout with the fewest moves left.
                        if !kindest { return (next, result.moves.count) }
                        if best == nil || result.moves.count < best!.best { best = (next, result.moves.count) }
                    }
                }
                return best
            }.value
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            shaking = false
            guard let found, session.board == board, outcome == nil else {
                if wasStuck, outcome == nil, session.board == board { outcome = .stuck }
                then(false)
                return
            }
            // Play time up to a stuck screen was already counted for the ad cadence.
            if wasStuck { started = Date() }
            if keepsStarLimit { session.shuffle(to: found.board) } else { session.shakeUp(to: found.board, bestFromHere: found.best) }
            foundHint = nil
            noWayThrough = false; hintGaveUp = false
            scene.reload(session.board, dropIn: true)
            scene.popWord(word, size: 0.95)
            // The first shake-up ever says what just happened, once.
            if !keepsStarLimit, !model.progress.rulesShown.contains("shakeup") {
                model.update { $0.rulesShown.insert("shakeup") }
                model.toast = String(localized: "Shake-up! Everyone swapped places. Your stars start fresh from here.")
            }
            model.sounds.play("splat", or: "land_soft")
            model.haptics.win()
            then(true)
        }
    }

    private func newPot() {
        guard let model else { return }
        pot = LevelPot(firstClear: !model.playingDaily && model.progress.stars[level.id] == nil, jars: level.kinds.count,
                       luckyKind: model.luckyKind(index: index), jarMultiplier: jarMultiplier, rules: model.config.coins)
        jarsDone = 0
        chain = SortChain(timed: !model.isGentleMode)
    }

    private func checkOutcome() {
        guard let model else { return }
        let seconds = Date().timeIntervalSince(started)
        switch session.status {
        case .won(let stars):
            outcome = .won(stars: stars)
            bossMood = 3
            model.sounds.stopMusic()
            scene.celebrate()
            model.haptics.win()
            model.sounds.play(level.file.beat == .boss ? "win_boss" : "win")
            model.won(index: index, moves: session.moveCount, stars: stars, attempts: attempts, playSeconds: seconds,
                      pot: pot.coins)
        case .stuck:
            // Now and then a free magic shuffle steps in: the pieces land in the kindest layout found,
            // and the try carries on. It is not counted as a fail.
            var rng = SystemRandomNumberGenerator()
            if !AppModel.isUITesting, !model.playingDaily,
               Coins.magicShuffle(levelNumber: index + 1, alreadyThisTry: rescueUsed, rng: &rng) {
                rescueUsed = true
                model.sounds.play("lucky")
                shake(word: String(localized: "Magic shuffle!"), keepsStarLimit: true, kindest: true) { [weak self] done in
                    guard let self, !done, self.outcome == nil, self.session.status == .stuck else { return }
                    self.outcome = .stuck
                    self.scene.sigh()
                    model.failed(playSeconds: seconds)
                }
                break
            }
            scene.sigh()
            model.failed(playSeconds: seconds)
            // The board stays in plain view for a moment first, so the player can see for
            // themselves that nothing can move before the card covers it.
            let board = session.board
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                if outcome == nil, session.board == board, session.status == .stuck { outcome = .stuck }
            }
        case .playing:
            break
        }
    }

    func undo() {
        guard !shaking, session.undo() else { return }
        chain.end()
        // The free moves of a fever come back with the move.
        if let before = feverBefore.popLast() {
            feverLeft = before
            scene.setFever(before > 0)
        }
        noWayThrough = false; hintGaveUp = false
        magicPending = nil
        outcome = nil
        scene.reload(session.board)
    }

    var canHint: Bool { !thinking }

    /// The player picked how to pay for a helper.
    func pay(for item: Coins.Item, withAd: Bool) {
        guard let model else { return }
        choosing = nil
        let grant: () -> Void = { [weak self] in
            switch item {
            case .hint: self?.showHint()
            case .theme, .treat, .gift, .shuffle: break
            }
        }
        if withAd {
            model.optIn(.hint, granted: grant)
        } else if model.spend(item) {
            grant()
        }
    }

    /// The hint is worked out first, off the main thread, and only charged for
    /// (free hint, coins or an ad) when there is a move to show.
    func hint() {
        guard !thinking, outcome == nil else { return }
        chain.end()
        thinking = true
        let board = session.board
        Task {
            let move = await Task.detached(priority: .userInitiated) { [level = self.level] in level.hint(for: board) }.value
            thinking = false
            guard let model, board == session.board, outcome == nil else { return }
            guard case .move(let move) = move else {
                if move == .unwinnable { noWayThrough = true } else { hintGaveUp = true }
                return
            }
            foundHint = (board, move)
            if model.hintsAvailable {
                model.useHint()
                showHint()
            } else {
                choosing = .hint
            }
        }
    }

    /// A magic move: the best next move is worked out and played for the player. Free with a magic
    /// move in hand, or for the price of a hint.
    func magic(paid: Bool = false) {
        guard let model, !thinking, !shaking, outcome == nil else { return }
        guard paid ? model.progress.wallet.canAfford(.hint) : model.progress.magicMoves > 0 else { return }
        chain.end()
        thinking = true
        let board = session.board
        Task {
            let found = await Task.detached(priority: .userInitiated) { [level = self.level] in level.hint(for: board) }.value
            thinking = false
            guard board == session.board, outcome == nil else { return }
            guard case .move(let move) = found else {
                if found == .unwinnable { noWayThrough = true } else { hintGaveUp = true }
                return
            }
            magicPending = (move, paid)
            if !scene.playForPlayer(move) { magicPending = nil }
        }
    }

    private func showHint() {
        guard let found = foundHint, found.board == session.board else { return }
        scene.showHint(found.move)
    }

    func retry() {
        model?.levelCheer = nil
        attempts += 1
        started = Date()
        // A retry empties the pot, so coins can't be farmed.
        newPot()
        feverLeft = 0
        feverBefore = []
        lastMoveWasFever = false
        scene.setFever(false)
        shakeAt = model?.shakeUpMove(index: index)
        session = GameSession(board: level.board, par: level.par, undoLimit: model?.undoLimit ?? 5, starSlack: starSlack)
        // Real walls soften: one extra jar after enough fails.
        if let soften = level.file.softenAfterFails, attempts > soften { session.addExtraJar() }
        videoShuffleUsed = false
        bossMood = 0
        shufflesUsed = 0
        luckyUsed = false
        rescueUsed = false
        magicPending = nil
        noWayThrough = false; hintGaveUp = false
        outcome = nil
        scene.reload(session.board)
    }
}

struct LevelView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var controller: LevelController
    @State private var nudge = false
    @State private var bossSplash: Bool
    /// The rule being shown before play, or replayed from the "?" button.
    @State private var ruleDemo: BoardRule?

    init(index: Int, model: AppModel) {
        _controller = StateObject(wrappedValue: LevelController(index: index, model: model))
        // A boss level opens with its splash (not on a level already won, and not in UI tests).
        let level = model.levels[index]
        _bossSplash = State(initialValue: level.file.beat == .boss && model.progress.stars[level.id] == nil && !AppModel.isUITesting)
    }

    /// The twists on this board, for the "?" that replays their demos.
    private var rules: [BoardRule] { BoardRule.rules(on: controller.level.board, look: controller.level.look) }

    /// The first rule on this board the player has not been shown yet.
    private func showNewRule() {
        guard !AppModel.isUITesting, ruleDemo == nil, controller.session.moveCount == 0 else { return }
        // "Only what fits moves" is taught from the fourth level on, to old and new players alike.
        if controller.index >= 3, !model.progress.rulesShown.contains(BoardRule.partial.rawValue) {
            ruleDemo = .partial
            return
        }
        ruleDemo = rules.first { !model.progress.rulesShown.contains($0.rawValue) }
    }

    private func closeRuleDemo() {
        guard let shown = ruleDemo else { return }
        ruleDemo = nil
        if !model.progress.rulesShown.contains(shown.rawValue) {
            model.update { $0.rulesShown.insert(shown.rawValue) }
            // Another new rule on the same board comes next; otherwise the hand shows a first move.
            showNewRule()
            if ruleDemo == nil { controller.pointAtFirstMove() }
        }
    }

    private var isBoss: Bool { controller.level.file.beat == .boss }
    private var isFinale: Bool { isBoss && model.isFinale(controller.index) }

    private var number: Int { model.levelNumber(controller.index) }
    /// Helpers and the tracking prompt follow the main path; a side world has them all.
    private var pathNumber: Int { model.isSideLevel(controller.index) ? 99 : controller.index + 1 }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                header
                // The board has the whole width, on an iPad too; the bars keep a comfortable one.
                SpriteView(scene: controller.scene, options: [.allowsTransparency])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) { if AppModel.isUITesting { testTaps } }
                helpers.frame(maxWidth: 620)
            }
            .padding(.horizontal, 12)
            if isFinale {
                // The giant peeks over the top corner and reacts.
                VStack {
                    HStack { Spacer(); BossPeek(world: controller.level.look, mood: controller.bossMood) }
                        .padding(.top, 84)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            if let joined = model.joinedBook {
                NewFindSticker(squishy: joined) { model.joinedBook = nil }
                    .id(joined.id)
            }
            if model.trackingExplainer && controller.outcome == nil {
                Color.black.opacity(0.15).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("Next, Apple asks if ads can be matched to you. Either answer is fine: you can play everything.")
                        .font(Theme.body(16)).foregroundStyle(Theme.plum)
                        .multilineTextAlignment(.center)
                    Button("Continue") { model.askTracking() }.buttonStyle(SquishButtonStyle())
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 28).fill(Theme.marshmallow))
                .padding(30)
                .frame(maxWidth: 520)
            }
            if let item = controller.choosing {
                // The hint's payment bubble.
                Color.black.opacity(0.15).ignoresSafeArea().onTapGesture { controller.choosing = nil }.zIndex(9)
                helperBubble(item).zIndex(10)
            }
            if (controller.noWayThrough || controller.hintGaveUp) && controller.outcome == nil {
                VStack {
                    Text(controller.noWayThrough ? LocalizedStringKey("No way through from here. Undo or shuffle.")
                         : LocalizedStringKey("This one is tricky! Try a move, then ask me again."))
                        .font(Theme.body(15)).foregroundStyle(Theme.plum)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(.white))
                        .padding(.top, 96)
                    Spacer()
                }
                .transition(.opacity)
                // It says its piece and goes: it must never stay pinned over a board that has moved on.
                .task {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    controller.noWayThrough = false
                    controller.hintGaveUp = false
                }
            }
            if let outcome = controller.outcome {
                Color.black.opacity(0.15).ignoresSafeArea()
                // The Buddy only speaks once the level is over.
                if let cheer = model.levelCheer, let ref = model.progress.buddy.squishy {
                    VStack {
                        HStack(alignment: .bottom, spacing: 6) {
                            SquishRefView(ref: ref).frame(width: 64, height: 64)
                            SpeechBubble(text: cheer)
                        }
                        .padding(.top, 70)
                        .padding(.horizontal, 20)
                        Spacer()
                    }
                }
                switch outcome {
                case .won(let stars):
                    Confetti(count: stars >= 3 ? 80 : 45, seconds: 3).ignoresSafeArea()
                    WinCard(stars: stars, showpiece: controller.level.file.beat == .showpiece,
                            summary: model.lastWin,
                            moves: controller.session.moveCount,
                            perfect: controller.session.moveCount <= controller.session.par,
                            threeStarMoves: Stars.moveLimit(forStars: 3, par: controller.session.par, slack: controller.starSlack),
                            // Not while good news is waiting behind the win card: that is told first.
                            retry: controller.index < 2 || !model.news.isEmpty || model.lastWin.dailyJar ? nil : { controller.retry() },
                            toCapsule: model.lastWin.dailyJar ? nil : model.levelsToNextCapsule(after: controller.index),
                            // The first two levels roll straight on after the celebration.
                            autoAdvance: controller.index < 2,
                            haptics: model.haptics, sounds: model.sounds,
                            doubleCoins: model.offersDoubleCoins ? { model.doubleCoins() } : nil,
                            doubleIsFree: model.ownsRemoveAds,
                            removeAds: model.lastWin.offersRemoveAds ? { model.screen = .shop } : nil) {
                        model.continueAfterWin(index: controller.index, attempts: controller.attempts)
                    }
                case .stuck:
                    StuckCard(boss: isBoss, canUndo: controller.session.canUndo,
                              free: controller.shuffleIsFree,
                              canPay: model.progress.wallet.canAfford(.shuffle),
                              video: !controller.videoShuffleUsed && model.canOptIn(.shuffle),
                              videoIsFree: model.ownsRemoveAds,
                              undo: controller.undo, shuffle: controller.shuffle, videoShuffle: controller.videoShuffle,
                              retry: controller.retry)
                }
            }
        }
        .background {
            ZStack {
                // The plain theme shows the world's own room; a bought theme paints over it.
                if model.boardTheme == .cream {
                    WorldBackdrop(world: controller.level.look)
                } else {
                    LinearGradient(colors: model.boardTheme.colors, startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                }
                if isBoss {
                    // Evening falls on a boss level, with a soft spotlight on the jars.
                    Theme.plum.opacity(0.42).ignoresSafeArea()
                    RadialGradient(colors: [Color.white.opacity(0.28), .clear], center: .center, startRadius: 20, endRadius: 320)
                        .ignoresSafeArea()
                }
            }
        }
        .overlay {
            if bossSplash {
                BossSplash(world: controller.level.look, finale: isFinale, canSkip: model.progress.bossSplashSeen) {
                    bossSplash = false
                    model.bossSplashShown()
                    model.sounds.startMusic("boss_loop")
                    showNewRule()
                }
                .zIndex(50)
            }
        }
        .overlay {
            if let rule = ruleDemo {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    RuleDemo(rule: rule, world: controller.level.look) { closeRuleDemo() }
                        .id(rule)
                }
                .transition(.opacity)
                .zIndex(40)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: ruleDemo)
        .onAppear {
            controller.scene.darkBackground = darkRoom
            if isBoss && !bossSplash && !AppModel.isUITesting { model.sounds.startMusic("boss_loop") }
            if !bossSplash { showNewRule() }
        }
        .onDisappear { model.sounds.stopMusic() }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.outcome)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.trackingExplainer)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: controller.choosing)
        .onAppear { model.levelStarted(number: pathNumber) }
        .onDisappear { model.joinedBook = nil }
    }

    /// Paying for a hint: the game's own bubble, not a system sheet.
    private func helperBubble(_ item: Coins.Item) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                if let ref = model.progress.buddy.squishy, model.buddyActive {
                    SquishRefView(ref: ref).frame(width: 56, height: 56)
                }
                SpeechBubble(text: String(localized: "Want a hint?"))
            }
            if model.canOptIn(.hint) {
                // Remove Ads owners get it with one tap and no ad.
                Button { controller.pay(for: item, withAd: true) } label: {
                    Label(model.ownsRemoveAds ? LocalizedStringKey("Free") : LocalizedStringKey("Watch an ad"),
                          systemImage: model.ownsRemoveAds ? "sparkles" : "play.rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.grape))
            }
            if model.progress.wallet.canAfford(item) {
                Button { controller.pay(for: item, withAd: false) } label: {
                    Label { Text("Use \(item.price) coins") } icon: { CoinIcon() }.frame(maxWidth: .infinity)
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                // Or have the move played for you, for the same coins.
                Button { controller.choosing = nil; controller.magic(paid: true) } label: {
                    Label { Text("Do it for me: \(item.price) coins") } icon: { Image(systemName: "wand.and.stars") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.sky, text: Theme.plum))
                .accessibilityIdentifier("helper-do-it")
            } else if !model.isGentleMode {
                // Under-13s never get a shop offer from the board.
                Button { controller.choosing = nil; model.screen = .shop } label: {
                    Label("Get coins", systemImage: "cart.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
            }
            Text("You have \(model.progress.wallet.balance) coins").font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.7))
            Button("Not now") { controller.choosing = nil }
                .font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
                .accessibilityIdentifier("helper-close")
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 28).fill(Theme.marshmallow))
        .padding(30)
        .frame(maxWidth: 520)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    /// The title column sits on the middle of the screen whatever buttons are at the edges.
    private var header: some View {
        ZStack(alignment: .top) {
            HStack {
                if model.showsCornerButtons {
                    IconButton(system: "house.fill") { model.screen = .home }
                    // Straight to the level map, without going by home.
                    IconButton(system: "circle.grid.3x3.fill") { model.screen = .map }
                        .accessibilityLabel(Text("Levels"))
                }
                Spacer()
                if let rule = rules.first ?? (controller.index >= 3 ? BoardRule.partial : nil), controller.outcome == nil {
                    // Replays the demo of this board's twist.
                    IconButton(system: "questionmark") { ruleDemo = rule }
                        .accessibilityLabel(Text("How this works"))
                        .accessibilityIdentifier("rule-help")
                }
                if model.showsCornerButtons {
                    IconButton(system: "book.fill") { model.screen = .book }
                    IconButton(system: "gearshape.fill") { model.screen = .settings }
                }
            }
            VStack(spacing: 2) {
                Group {
                // A pink jelly pill with the level, and the world's name under it.
                HStack(spacing: 6) {
                    if isBoss {
                        Image("boss-crown").resizable().scaledToFit().frame(height: 18)
                        Text("BOSS")
                    } else if model.playingDaily {
                        Text("Daily Jar")
                    } else {
                        Text("Level \(number)")
                    }
                }
                .font(Theme.title(20)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 5)
                    .background {
                        ZStack(alignment: .top) {
                            Capsule().fill(Color(hex: 0xE5609B)).offset(y: 3)
                            Capsule().fill(LinearGradient(colors: [Color(hex: 0xFFA3CB), Color(hex: 0xFF7EB6)], startPoint: .top, endPoint: .bottom))
                            Capsule().fill(Color.white.opacity(0.35)).frame(height: 8).padding(.horizontal, 10).padding(.top, 3)
                        }
                    }
                Text(model.playingDaily ? LocalizedStringKey("One a day")
                     : controller.level.file.world == "christmas" ? AppModel.christmasWorldName : AppModel.worldName(controller.level.file.world))
                    .font(Theme.body(13)).foregroundStyle(darkRoom ? Color.white.opacity(0.9) : Theme.plum.opacity(0.75))
                if controller.level.file.beat == .bonus {
                    // Coin Rush: every finished jar throws double coins the first time through.
                    Text("BONUS x2").font(Theme.body(13)).foregroundStyle(Theme.plum)
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.butter))
                } else if controller.level.file.beat == .showpiece {
                    // Looks big, solves fast: not "hard".
                    Text("BIG ONE").font(Theme.body(13)).foregroundStyle(Theme.bubblegum)
                } else if controller.level.file.beat == .tension {
                    Text("HARD").font(Theme.body(13)).foregroundStyle(Theme.bubblegum)
                }
                // The stars still to be won, and the moves left before the next one goes.
                StarMeter(moves: controller.session.moveCount, par: controller.session.par, slack: controller.starSlack,
                          gentle: model.isGentleMode, haptics: model.haptics, sounds: model.sounds)
                if controller.feverLeft > 0 {
                    Label { Text("\(controller.feverLeft) free moves") } icon: { Image(systemName: "flame.fill") }
                        .font(Theme.body(14)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xFFB13D), Color(hex: 0xFF7EB6)], startPoint: .leading, endPoint: .trailing)))
                        .transition(.scale.combined(with: .opacity))
                }
                }
                .allowsHitTesting(false)
                if controller.feverLeft == 0, let left = controller.shakeIn {
                    // The countdown, and under it the way to call the shake-up off.
                    VStack(spacing: 0) {
                        Label { Text("Shake-up in \(left)") } icon: { Image(systemName: "tornado") }
                            .font(Theme.body(13))
                        Text("Fill a jar to stop it").font(Theme.body(10)).opacity(0.75)
                    }
                    .foregroundStyle(Theme.plum).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 12).padding(.vertical, 3)
                    .background(Capsule().fill(left <= 3 ? Theme.butter : Color.white.opacity(0.7)))
                    .accessibilityElement(children: .combine)
                    .allowsHitTesting(false)
                    // Or coins stop it, for the price of a hint. Not in gentle mode.
                    if controller.canPayToStopShake {
                        Button { controller.payToStopShake() } label: {
                            Label { Text("Stop it: \(Coins.Item.hint.price) coins") } icon: { CoinIcon() }
                                .font(Theme.body(12)).foregroundStyle(Theme.plum).lineLimit(1).minimumScaleFactor(0.7)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(Capsule().fill(Theme.butter))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("stop-shake")
                    }
                }
                Group {
                // The level pot: coins thrown by finished jars, banked on the win.
                if controller.pot.paysCoins {
                    // Says what it is until the first jar pays, then just the number.
                    Label { controller.pot.coins == 0 ? Text("Level coins") : Text(verbatim: "\(controller.pot.coins)") } icon: { CoinIcon() }
                        .font(Theme.body(14)).foregroundStyle(Theme.plum)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.butter.opacity(0.6)))
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: controller.pot.coins)
                        .accessibilityIdentifier("level-pot")
                }
                }
                .allowsHitTesting(false)
            }
            .foregroundStyle(Theme.plum)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }

    /// A night scene behind the jars: they glow, and loose words turn white.
    private var darkRoom: Bool {
        model.boardTheme == .night || isBoss
            || (model.boardTheme == .cream && WorldBackdrop.isDark(controller.level.look))
    }

    /// Three stars are out of reach on this try. Players of 13 and over get a nudge to start again;
    /// gentle mode is never pushed.
    private var starsSlipped: Bool {
        let moves = controller.session.moveCount
        return moves > 0 && !model.isGentleMode && controller.index >= 2
            && Stars.rating(moves: moves, par: controller.session.par, slack: controller.starSlack) < 3
    }

    // Undo appears after level 2, Hint after 4, Shuffle after 7.
    private var helpers: some View {
        HStack(spacing: 8) {
            if pathNumber >= 2 {
                helper(String(localized: "Undo"), "arrow.uturn.backward", .white, enabled: controller.session.canUndo,
                       badge: controller.session.undosLeft) { controller.undo() }
            }
            if pathNumber >= 7 {
                // One free shuffle a level, then coins. Too few coins: the price fades and a tap says what you have.
                let paid = controller.shufflesUsed > 0
                helper(String(localized: "Shuffle"), "shuffle", Theme.mint, enabled: !controller.shaking,
                       tag: paid ? "\(Coins.Item.shuffle.price)" : String(localized: "Free"),
                       tagFaded: paid && !model.progress.wallet.canAfford(.shuffle)) { controller.shuffle() }
                    .accessibilityIdentifier("helper-shuffle")
            }
            if pathNumber >= 4 {
                if model.progress.magicMoves > 0 {
                    // Magic moves in hand: the button plays the best next move itself, and counts them down.
                    helper(String(localized: "Magic"), "wand.and.stars", Theme.sky, enabled: controller.canHint,
                           badge: model.progress.magicMoves) { controller.magic() }
                        .accessibilityIdentifier("helper-magic")
                } else {
                    helper(String(localized: "Hint"), "lightbulb.fill", Theme.butter, enabled: controller.canHint) { controller.hint() }
                }
            }
            if starsSlipped {
                // A nudge, never a loss: the level can still be finished as it is.
                helper(String(localized: "Go for 3 stars"), "star.fill", Theme.butter, enabled: true) { controller.retry() }
                    .scaleEffect(nudge ? 1.06 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: nudge)
                    .onAppear { nudge = true }
                    .onDisappear { nudge = false }
            } else {
                helper(String(localized: "Restart"), "arrow.clockwise", .white, enabled: true) { controller.retry() }
            }
        }
        .padding(.bottom, 8)
        .overlay(alignment: .top) {
            if controller.shuffleShort {
                Label { Text("You have \(model.progress.wallet.balance) coins") } icon: { CoinIcon() }
                    .font(Theme.body(14)).foregroundStyle(Theme.plum)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(.white))
                    .offset(y: -40)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: controller.shuffleShort)
    }

    /// Every helper is the same size, with its picture over its name, so the row lines up in any language.
    private func helper(_ title: String, _ icon: String, _ fill: Color, enabled: Bool, badge: Int? = nil,
                        tag: String? = nil, tagFaded: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18, weight: .bold))
                Text(verbatim: title).font(Theme.body(13)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(Theme.plum)
            .frame(maxWidth: .infinity, minHeight: 62)
            .padding(.horizontal, 4)
            .opacity(enabled ? 1 : 0.45)
            .overlay(alignment: .topTrailing) {
                // How many are left, as a badge on the corner rather than in the name.
                if let badge {
                    Text(verbatim: "\(badge)").font(Theme.body(12)).monospacedDigit().foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(badge > 0 ? Theme.grape : Theme.plum.opacity(0.4)))
                        .overlay(Capsule().stroke(.white, lineWidth: 2))
                        .offset(x: 4, y: -6)
                } else if let tag {
                    Text(verbatim: tag).font(Theme.body(11)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 6).frame(minHeight: 20)
                        .background(Capsule().fill(Theme.grape))
                        .overlay(Capsule().stroke(.white, lineWidth: 2))
                        .opacity(tagFaded ? 0.45 : 1)
                        .offset(x: 4, y: -6)
                }
            }
        }
        .buttonStyle(JellyButtonStyle(colors: [fill, fill], rim: jellyRim(fill), radius: 22))
        .opacity(enabled ? 1 : 0.6)
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: badge.map { "\(title) \($0)" } ?? tag.map { "\(title) \($0)" } ?? title))
    }

    /// The darker lip under a jelly button of this colour.
    private func jellyRim(_ fill: Color) -> Color {
        if fill == Theme.mint { return Color(hex: 0x4FBF9F) }
        if fill == Theme.butter { return Color(hex: 0xE0B13A) }
        if fill == Theme.sky { return Color(hex: 0x6FA9D6) }
        return Color(hex: 0xD9C9D6)
    }

    /// Invisible-ish jar buttons so UI tests can play without pixel maths.
    private var testTaps: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(0..<controller.scene.board.jarCount, id: \.self) { j in
                    Button("jar-\(j)") { controller.scene.tapJar(j) }
                        .font(.system(size: 6))
                        .frame(width: 28, height: 14)
                        .background(Color.white)
                        .accessibilityIdentifier("jar-\(j)")
                }
            }
            if controller.scene.board.floats {
                HStack(spacing: 2) {
                    ForEach(0..<controller.scene.board.jarCount, id: \.self) { j in
                        Button("bubble-\(j)") { controller.scene.tapBubble(j) }
                            .font(.system(size: 6))
                            .frame(width: 28, height: 14)
                            .background(Color.white)
                            .accessibilityIdentifier("bubble-\(j)")
                    }
                }
            }
            // What the scene thinks is going on, for failing UI tests.
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                Text(controller.scene.debugState + " status=\(String(describing: controller.session.status))")
                    .font(.system(size: 6))
                    .accessibilityIdentifier("scene-state")
            }
        }
    }
}

struct IconButton: View {
    let system: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.plum)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(system)
    }
}

/// The move counter in the level header: the moves made, the most that still keep the stars shown,
/// and the stars themselves. As the limit gets near the counter turns pink and throbs; when it is
/// passed a star drops off, so the player can see a better run was possible.
struct StarMeter: View {
    let moves: Int
    let par: Int
    var slack: Int?
    /// Gentle mode: stars and a plain move count only. No limit, no warning colour, no falling star.
    var gentle = false
    var haptics: Haptics?
    var sounds: SoundService?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var falling: Int?
    @State private var fell = false

    var body: some View {
        let lit = Stars.rating(moves: moves, par: par, slack: slack)
        let limit = gentle ? nil : Stars.moveLimit(forStars: lit, par: par, slack: slack)
        let near = !gentle && moves > 0 && (limit.map { $0 - moves <= 2 } ?? false)
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Text("Moves").font(Theme.body(13)).opacity(0.7)
                Group {
                    if let limit { Text(verbatim: "\(moves)/\(limit)") } else { Text(verbatim: "\(moves)") }
                }
                .font(Theme.title(15)).monospacedDigit()
                .accessibilityIdentifier("move-count")
            }
            .foregroundStyle(near ? Color.white : Theme.plum)
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(Capsule().fill(near ? Theme.bubblegum : Color.white.opacity(0.7)))
            .scaleEffect(near && !reduceMotion ? 1.08 : 1)
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < lit ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(i < lit ? Theme.butter : Theme.plum.opacity(0.18))
                        .shadow(color: Theme.plum.opacity(i < lit ? 0.35 : 0), radius: 0.5)
                        .scaleEffect(i < lit ? 1 : 0.8)
                        .overlay {
                            if falling == i {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(Theme.butter)
                                    .rotationEffect(.degrees(fell ? 140 : 0))
                                    .offset(x: fell ? 10 : 0, y: fell ? 46 : 0)
                                    .opacity(fell ? 0 : 1)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: moves)
        .onChange(of: lit) { old, new in
            guard new < old, moves > 0, !gentle else { return }
            sounds?.play("star_lost", or: "lift")
            haptics?.star()
            guard !reduceMotion else { return }
            fell = false
            falling = new
            withAnimation(.easeIn(duration: 0.6)) { fell = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { if falling == new { falling = nil } }
        }
    }
}

struct WinCard: View {
    let stars: Int
    let showpiece: Bool
    let summary: AppModel.WinSummary
    /// Levels still to win before the next capsule (0 = the next level has one).
    var moves: Int?
    /// Won in the fewest moves possible.
    var perfect = false
    /// The most moves that still earn three stars, for the line under a win with fewer.
    var threeStarMoves: Int?
    /// "Go for 3 stars": play the level again. Nil where it isn't offered.
    var retry: (() -> Void)?
    var toCapsule: Int?
    var autoAdvance = false
    var haptics: Haptics?
    var sounds: SoundService?
    /// "x2 coins" by opt-in ad (one tap for Remove Ads owners). Nil when not offered.
    var doubleCoins: (() -> Void)?
    var doubleIsFree = false
    /// The one soft Remove Ads line. Nil when it isn't due.
    var removeAds: (() -> Void)?
    let next: () -> Void
    @State private var shown = 0
    @State private var coinsShown = 0
    @State private var streakShown = false
    @State private var left = false

    var body: some View {
        VStack(spacing: 14) {
            Text(summary.dailyJar ? LocalizedStringKey("Daily Jar done!") : showpiece ? LocalizedStringKey("Genius!") : LocalizedStringKey("Sorted!")).font(Theme.title(34)).foregroundStyle(Theme.plum)
            HStack(spacing: 10) {
                ForEach(0..<3) { i in
                    Image(systemName: i < shown ? "star.fill" : "star")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(i < shown ? Theme.butter : Theme.plum.opacity(0.25))
                        .scaleEffect(i < shown ? 1 : 0.7)
                        .rotationEffect(.degrees(i < shown ? 0 : -25))
                }
            }
            if perfect && shown >= 3 {
                Text("Perfect!").font(Theme.title(20)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.bubblegum))
                    .rotationEffect(.degrees(-6))
                    .transition(.scale(scale: 2.2).combined(with: .opacity))
                    .accessibilityIdentifier("win-perfect")
            } else if stars < 3, let threeStarMoves {
                VStack(spacing: 2) {
                    if let moves { Text("Your moves: \(moves)").font(Theme.body(15)).foregroundStyle(Theme.plum) }
                    Text("3 stars: \(threeStarMoves) moves or fewer").font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.7))
                }
            }
            if summary.total > 0 {
                HStack(spacing: 10) {
                    Label { Text("+\(coinsShown)") } icon: { CoinIcon() }.font(Theme.title(22)).foregroundStyle(Theme.plum)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("win-coins")
                }
                if summary.streak >= 2 && streakShown {
                    // First-try streak, on its own line after the coins. Never shown when it breaks, never in gentle mode.
                    Label("\(summary.streak) in a row! +\(summary.streakBonus)", systemImage: "flame.fill")
                        .font(Theme.body(16)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.bubblegum))
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
                if summary.magicEarned > 0 {
                    // Earned by a first-try streak or a boss: the game will play that many moves for you.
                    Label("Magic moves +\(summary.magicEarned)", systemImage: "wand.and.stars")
                        .font(Theme.body(16)).foregroundStyle(Theme.plum)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.sky))
                        .accessibilityIdentifier("win-magic")
                }
                if summary.dailyBonus > 0 {
                    Text("First win today: +\(summary.dailyBonus)").font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.7))
                }
            }
            if summary.stamped {
                // Today's stamp: one for the first win of each day, seven to a card.
                HStack(spacing: 5) {
                    let filled = summary.stamps == 0 ? StampCard.size : summary.stamps
                    ForEach(0..<StampCard.size, id: \.self) { i in
                        Image(systemName: i < filled ? "seal.fill" : "circle.dotted")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(i < filled ? Theme.bubblegum : Theme.plum.opacity(0.3))
                            .scaleEffect(i == filled - 1 && shown > 0 ? 1.35 : 1)
                    }
                    if summary.stamps == 0 { Text("Card full!") } else { Text("Stamp \(summary.stamps) of 7!") }
                }
                .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.7))
                .accessibilityElement(children: .combine)
            }
            if let treat = summary.treat {
                // Where the Buddy's treats come from: one for every win, three to a jar.
                Label {
                    if treat { Text("+1 treat for \(summary.buddyName)") } else { Text("Treat jar full") }
                } icon: {
                    Image(systemName: "birthday.cake.fill")
                }
                .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.75))
            }
            if let fill = summary.piggyFill {
                // The piggy bank fills a little with every win. A bar only: it is opened in the shop.
                HStack(spacing: 8) {
                    Text(verbatim: "🐷").font(.system(size: 16))
                    PiggyBar(fill: fill).frame(width: 120)
                    if fill >= 1 { Text("Piggy bank full!").font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.7)) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Piggy bank"))
            }
            if let toCapsule {
                Label {
                    if toCapsule == 0 { Text("Capsule next level!") } else { Text("Next capsule: \(toCapsule + 1) more") }
                } icon: {
                    Image(systemName: "gift.fill")
                }
                .font(Theme.body(14)).foregroundStyle(Theme.grape)
            }
            if let doubleCoins {
                Button(action: doubleCoins) {
                    Label("x2 coins", systemImage: doubleIsFree ? "sparkles" : "play.rectangle.fill")
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.grape))
            }
            Button("Next") { go() }.buttonStyle(SquishButtonStyle()).font(Theme.title(22))
                .accessibilityIdentifier("win-next")
            if stars < 3, let retry {
                Button { guard !left else { return }; left = true; retry() } label: {
                    Label("Go for 3 stars", systemImage: "star.fill")
                }
                .font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.75))
                .accessibilityIdentifier("win-retry")
            }
            if let removeAds {
                Button("Like playing without breaks? Remove Ads is in the shop.", action: removeAds)
                    .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(Theme.marshmallow))
        .padding(30)
        .onChange(of: summary.total) { _, total in
            // Doubled: the number jumps up with the coin shower.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { coinsShown = total }
        }
        .task {
            // Stars slam in one by one, each with a tap you can feel and hear.
            for i in 1...max(1, stars) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { shown = i }
                haptics?.land()
                sounds?.star(i)
            }
            // Coins count up into the total.
            let total = summary.total
            if total > 0 {
                let steps = min(total, 18)
                for n in 1...steps {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    withAnimation(.easeOut(duration: 0.05)) { coinsShown = total * n / steps }
                    if n % 3 == 0 { sounds?.coin() }
                }
                haptics?.complete()
                if summary.streak >= 2 {
                    sounds?.play("streak")
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { streakShown = true }
                }
            }
            if summary.stamped {
                sounds?.play("new_stamp")
                if summary.stamps == 0 { sounds?.play("unlock_new") }
            }
            if autoAdvance {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if !Task.isCancelled { go() }
            }
        }
    }

    /// Next runs once, whether tapped or reached by the automatic roll-on.
    private func go() {
        guard !left else { return }
        left = true
        next()
    }
}

/// Nothing can move: a shuffle gets the board going again (free the first time, then coins or one
/// opt-in video), or undo, or start again. Never a shop offer here.
struct StuckCard: View {
    var boss = false
    let canUndo: Bool
    /// The first shuffle of a try costs nothing.
    let free: Bool
    let canPay: Bool
    /// The opt-in video shuffle is on offer.
    let video: Bool
    let videoIsFree: Bool
    let undo: () -> Void
    let shuffle: () -> Void
    let videoShuffle: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(boss ? LocalizedStringKey("So close! Rematch?") : LocalizedStringKey("Nothing can move"))
                .font(Theme.title(28)).foregroundStyle(Theme.plum).multilineTextAlignment(.center)
            Text("No squishy has a jar it can go to. A shuffle gets things moving again.")
                .font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7)).multilineTextAlignment(.center)
            if free || canPay {
                Button(action: shuffle) {
                    HStack(spacing: 8) {
                        Image(systemName: "shuffle")
                        Text("Shuffle")
                        if free {
                            Text("Free").font(Theme.body(14)).padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(.white.opacity(0.3)))
                        } else {
                            Label { Text(verbatim: "\(Coins.Item.shuffle.price)") } icon: { CoinIcon() }.font(Theme.body(15))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.grape)).font(Theme.title(22))
                .accessibilityIdentifier("stuck-shuffle")
            }
            if video && !free {
                Button(action: videoShuffle) {
                    Label(videoIsFree ? LocalizedStringKey("Free shuffle") : LocalizedStringKey("Watch a video to shuffle"),
                          systemImage: videoIsFree ? "sparkles" : "play.rectangle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.mint, text: Theme.plum))
            }
            HStack {
                if canUndo { Button("Undo", action: undo).buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum)) }
                Button("Try again", action: retry).buttonStyle(SquishButtonStyle())
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(Theme.marshmallow))
        .padding(30)
        .frame(maxWidth: 560)
    }
}
