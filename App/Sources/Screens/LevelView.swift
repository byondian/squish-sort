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
    @Published private(set) var extraJarUsed = false
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
    /// Shake-up: the move count at which the pieces are shuffled. Nil when there is none (left).
    @Published private(set) var shakeAt: Int?
    @Published private(set) var shaking = false
    /// Moves left before the shake-up.
    var shakeIn: Int? { shakeAt.map { max(0, $0 - session.history.count) } }
    /// Bonus levels are Coin Rush: every finished jar throws double on a first clear.
    private var jarMultiplier: Int { level.file.beat == .bonus ? 2 : 1 }
    /// The hint search is running.
    @Published private(set) var thinking = false
    /// The hint search found no way to win from here. Nothing is charged for that.
    @Published var noWayThrough = false
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
        shakeAt = model.shakeUpMove(index: index)
        session = GameSession(board: level.board, par: level.par, undoLimit: model.undoLimit, starSlack: starSlack)
        scene = BoardScene(board: level.board, kinds: level.kinds)
        scene.world = level.file.world
        chain = SortChain(timed: !model.isGentleMode)
        let lucky = model.luckyKind(index: index)
        pot = LevelPot(firstClear: model.progress.stars[level.id] == nil, jars: level.kinds.count,
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
        scene.onReject = { [weak model] in
            model?.haptics.reject()
            model?.sounds.play("reject")
        }
        scene.onLand = { [weak self, weak model] result in
            model?.sounds.move(run: result.count)
            self?.landed()
            if !result.thawedJars.isEmpty { model?.sounds.play("thaw") }
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
        // The very first board opens mid-move: one squishy already lifted and a
        // hand on the jar it belongs in, so the first tap finishes a jar.
        if index == 0, model.progress.stars.isEmpty, let first = level.solution.first {
            scene.tutorialMove = first
        }
    }

    private func play(_ move: Move) -> (MoveResult, Board)? {
        let ontoMatch = session.board.jars.indices.contains(move.to) && !session.board.jars[move.to].isEmpty
        let free = feverLeft > 0
        let before = feverLeft
        guard !shaking, let result = session.play(move, free: free) else { return nil }
        feverBefore.append(before)
        lastMoveWasFever = free
        if free { feverLeft -= 1 }
        landsOnMatch = ontoMatch
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

    /// Commons join the book the first time a jar of them is completed.
    private func jarCompleted(_ jar: Int) {
        guard let model, let piece = session.board.jars[jar].first, level.kinds.indices.contains(Int(piece.kind)) else { return }
        model.jarSorted(kind: level.kinds[Int(piece.kind)])
        jarsDone += 1
        model.sounds.jarComplete(number: jarsDone)
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
        guard let model, let at = shakeAt, session.history.count >= at, session.status == .playing, !shaking else { return }
        shakeAt = nil
        shaking = true
        chain.end()
        feverLeft = 0
        feverBefore = []
        scene.setFever(false)
        scene.clearSelection()
        model.sounds.play("drumroll")
        model.haptics.complete()
        scene.tremble(seconds: 1.1)
        let board = session.board
        Task {
            let found: (board: Board, best: Int)? = await Task.detached(priority: .userInitiated) {
                var rng = SystemRandomNumberGenerator()
                for _ in 0..<14 {
                    let next = board.shakenUp(using: &rng)
                    if next == board || next.isWon || next.isStuck { continue }
                    if next.jars.indices.contains(where: { next.isComplete($0) && !board.isComplete($0) }) { continue }
                    if let result = Solver.solve(next, maxStates: 120_000), result.moves.count >= 2 {
                        return (next, result.moves.count)
                    }
                }
                return nil
            }.value
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            shaking = false
            guard let found, session.board == board, outcome == nil else { return }
            session.shakeUp(to: found.board, bestFromHere: found.best)
            foundHint = nil
            noWayThrough = false; hintGaveUp = false
            scene.reload(session.board, dropIn: true)
            scene.popWord(String(localized: "Shake-up!"), size: 0.95)
            model.sounds.play("splat", or: "land_soft")
            model.haptics.win()
        }
    }

    private func newPot() {
        guard let model else { return }
        pot = LevelPot(firstClear: model.progress.stars[level.id] == nil, jars: level.kinds.count,
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
            scene.celebrate()
            model.haptics.win()
            model.sounds.play(level.file.beat == .boss ? "win_boss" : "win")
            model.won(index: index, moves: session.moveCount, stars: stars, attempts: attempts, playSeconds: seconds,
                      pot: pot.coins)
        case .stuck:
            outcome = .stuck
            scene.sigh()
            model.failed(playSeconds: seconds)
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
        outcome = nil
        scene.reload(session.board)
    }

    var canExtraJar: Bool { !extraJarUsed }
    var canHint: Bool { !thinking }

    func extraJar() {
        guard let model, !extraJarUsed else { return }
        if model.canUseFreeExtraJar(usedThisLevel: extraJarUsed) {
            model.useFreeExtraJar()
            addJar()
        } else {
            choosing = .extraJar
        }
    }

    /// The player picked how to pay for a helper.
    func pay(for item: Coins.Item, withAd: Bool) {
        guard let model else { return }
        choosing = nil
        let grant: () -> Void = { [weak self] in
            switch item {
            case .hint: self?.showHint()
            case .extraJar: self?.addJar()
            case .theme, .treat, .gift: break
            }
        }
        if withAd {
            model.optIn(item == .hint ? .hint : .extraJar, granted: grant)
        } else if model.spend(item) {
            grant()
        }
    }

    private func addJar() {
        extraJarUsed = true
        session.addExtraJar()
        outcome = nil
        scene.reload(session.board)
    }

    /// The hint is worked out first, off the main thread, and only charged for
    /// (free hint, coins or an ad) when there is a move to show.
    func hint() {
        guard !thinking, outcome == nil else { return }
        chain.end()
        thinking = true
        let board = session.board
        Task {
            let move = await Task.detached(priority: .userInitiated) { Solver.hint(board) }.value
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
        extraJarUsed = false
        noWayThrough = false; hintGaveUp = false
        outcome = nil
        scene.reload(session.board)
    }
}

struct LevelView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var controller: LevelController
    @State private var nudge = false

    init(index: Int, model: AppModel) {
        _controller = StateObject(wrappedValue: LevelController(index: index, model: model))
    }

    private var number: Int { model.levelNumber(controller.index) }
    /// Helpers and the tracking prompt follow the main path; a side world has them all.
    private var pathNumber: Int { model.isSideLevel(controller.index) ? 99 : controller.index + 1 }

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                header
                SpriteView(scene: controller.scene, options: [.allowsTransparency])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) { if AppModel.isUITesting { testTaps } }
                helpers
            }
            .padding(.horizontal, 12)
            if let joined = model.joinedBook {
                JoinedBookSticker(squishy: joined, name: joined.name(in: model.language)) { model.joinedBook = nil }
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
            }
            if let item = controller.choosing {
                // Above the stuck card too: its extra jar button leads here.
                Color.black.opacity(0.15).ignoresSafeArea().onTapGesture { controller.choosing = nil }.zIndex(9)
                helperBubble(item).zIndex(10)
            }
            if (controller.noWayThrough || controller.hintGaveUp) && controller.outcome == nil {
                VStack {
                    Text(controller.noWayThrough ? LocalizedStringKey("No way through from here. Undo a few moves.")
                         : LocalizedStringKey("This one is tricky! Try a move, then ask me again."))
                        .font(Theme.body(15)).foregroundStyle(Theme.plum)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(.white))
                        .padding(.top, 96)
                    Spacer()
                }
                .transition(.opacity)
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
                            retry: controller.index < 2 || !model.news.isEmpty ? nil : { controller.retry() },
                            toCapsule: model.levelsToNextCapsule(after: controller.index),
                            // The first two levels roll straight on after the celebration.
                            autoAdvance: controller.index < 2,
                            haptics: model.haptics, sounds: model.sounds,
                            doubleCoins: model.offersDoubleCoins ? { model.doubleCoins() } : nil,
                            doubleIsFree: model.ownsRemoveAds,
                            removeAds: model.lastWin.offersRemoveAds ? { model.screen = .shop } : nil) {
                        model.continueAfterWin(index: controller.index, attempts: controller.attempts)
                    }
                case .stuck:
                    StuckCard(canUndo: controller.session.canUndo,
                              canExtraJar: controller.canExtraJar,
                              undo: controller.undo, extraJar: controller.extraJar, retry: controller.retry)
                }
            }
        }
        .background {
            // The plain theme shows the world's own room; a bought theme paints over it.
            if model.boardTheme == .cream {
                WorldBackdrop(world: controller.level.file.world)
            } else {
                LinearGradient(colors: model.boardTheme.colors, startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            }
        }
        .onAppear { controller.scene.darkBackground = darkRoom }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.outcome)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.trackingExplainer)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: controller.choosing)
        .onAppear { model.levelStarted(number: pathNumber) }
        .onDisappear { model.joinedBook = nil }
    }

    /// Paying for a hint or an extra jar: the game's own bubble, not a system sheet.
    private func helperBubble(_ item: Coins.Item) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 8) {
                if let ref = model.progress.buddy.squishy, model.buddyActive {
                    SquishRefView(ref: ref).frame(width: 56, height: 56)
                }
                SpeechBubble(text: item == .hint ? String(localized: "Want a hint?") : String(localized: "Need one more jar?"))
            }
            // Gentle mode is offered the extra jar ad only from the stuck screen.
            if model.canOptIn(item == .hint ? .hint : .extraJar)
                && (item == .hint || !model.isGentleMode || controller.outcome == .stuck) {
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
                if model.showsCornerButtons {
                    IconButton(system: "book.fill") { model.screen = .book }
                    IconButton(system: "gearshape.fill") { model.screen = .settings }
                }
            }
            VStack(spacing: 2) {
                // A pink jelly pill with the level, and the world's name under it.
                Text("Level \(number)").font(Theme.title(20)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 5)
                    .background {
                        ZStack(alignment: .top) {
                            Capsule().fill(Color(hex: 0xE5609B)).offset(y: 3)
                            Capsule().fill(LinearGradient(colors: [Color(hex: 0xFFA3CB), Color(hex: 0xFF7EB6)], startPoint: .top, endPoint: .bottom))
                            Capsule().fill(Color.white.opacity(0.35)).frame(height: 8).padding(.horizontal, 10).padding(.top, 3)
                        }
                    }
                Text(controller.level.file.world == "christmas" ? AppModel.christmasWorldName : AppModel.worldName(controller.level.file.world))
                    .font(Theme.body(13)).foregroundStyle(darkRoom ? Color.white.opacity(0.9) : Theme.plum.opacity(0.75))
                if controller.level.file.beat == .boss {
                    Text("BOSS 👑").font(Theme.body(13))
                } else if controller.level.file.beat == .bonus {
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
                } else if let left = controller.shakeIn {
                    Label { Text("Shake-up in \(left)") } icon: { Image(systemName: "tornado") }
                        .font(Theme.body(13)).foregroundStyle(Theme.plum)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(left <= 3 ? Theme.butter : Color.white.opacity(0.7)))
                }
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
            .foregroundStyle(Theme.plum)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
        }
        .padding(.top, 8)
    }

    /// A night scene behind the jars: they glow, and loose words turn white.
    private var darkRoom: Bool {
        model.boardTheme == .night || (model.boardTheme == .cream && WorldBackdrop.isDark(controller.level.file.world))
    }

    /// Three stars are out of reach on this try. Players of 13 and over get a nudge to start again;
    /// gentle mode is never pushed.
    private var starsSlipped: Bool {
        let moves = controller.session.moveCount
        return moves > 0 && !model.isGentleMode && controller.index >= 2
            && Stars.rating(moves: moves, par: controller.session.par, slack: controller.starSlack) < 3
    }

    // Undo appears after level 2, Hint after 4, Extra jar after 7 (game design doc).
    private var helpers: some View {
        HStack(spacing: 8) {
            if pathNumber >= 2 {
                helper(String(localized: "Undo"), "arrow.uturn.backward", .white, enabled: controller.session.canUndo,
                       badge: controller.session.undosLeft) { controller.undo() }
            }
            if pathNumber >= 7 {
                helper(String(localized: "Extra jar"), "plus", Theme.mint, enabled: controller.canExtraJar) { controller.extraJar() }
            }
            if pathNumber >= 4 {
                helper(String(localized: "Hint"), "lightbulb.fill", Theme.butter, enabled: controller.canHint) { controller.hint() }
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
    }

    /// Every helper is the same size, with its picture over its name, so the row lines up in any language.
    private func helper(_ title: String, _ icon: String, _ fill: Color, enabled: Bool, badge: Int? = nil,
                        action: @escaping () -> Void) -> some View {
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
                }
            }
        }
        .buttonStyle(JellyButtonStyle(colors: [fill, fill], rim: jellyRim(fill), radius: 22))
        .opacity(enabled ? 1 : 0.6)
        .disabled(!enabled)
        .accessibilityLabel(Text(verbatim: badge.map { "\(title) \($0)" } ?? title))
    }

    /// The darker lip under a jelly button of this colour.
    private func jellyRim(_ fill: Color) -> Color {
        if fill == Theme.mint { return Color(hex: 0x4FBF9F) }
        if fill == Theme.butter { return Color(hex: 0xE0B13A) }
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

/// "<Name> joined your book!": the sticker pops up, then flies to the book corner.
struct JoinedBookSticker: View {
    let squishy: Collectible
    let name: String
    let done: () -> Void
    @State private var phase = 0

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                SquishyView(id: squishy.id, rarity: squishy.rarity).frame(width: 44, height: 44)
                Text("\(name) joined your book!").font(Theme.body(15)).foregroundStyle(Theme.plum)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(Theme.butter, lineWidth: 3))
            .scaleEffect(phase == 0 ? 0.3 : (phase == 1 ? 1 : 0.2), anchor: phase == 2 ? .topTrailing : .center)
            .opacity(phase == 1 ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: phase == 2 ? .trailing : .center)
            .padding(.top, phase == 2 ? 8 : 92)
            .padding(.horizontal, 12)
            Spacer()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .task {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { phase = 1 }
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            withAnimation(.easeIn(duration: 0.35)) { phase = 2 }
            try? await Task.sleep(nanoseconds: 400_000_000)
            done()
        }
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
            Text(showpiece ? "Genius!" : "Sorted!").font(Theme.title(34)).foregroundStyle(Theme.plum)
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

struct StuckCard: View {
    let canUndo: Bool
    let canExtraJar: Bool
    let undo: () -> Void
    let extraJar: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("No moves left").font(Theme.title(28)).foregroundStyle(Theme.plum)
            if canExtraJar {
                Text("An extra jar gives you room to keep going.").font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
            }
            Button("Try again", action: retry).buttonStyle(SquishButtonStyle()).font(Theme.title(22))
            HStack {
                if canUndo { Button("Undo", action: undo).buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum)) }
                if canExtraJar { Button("Extra jar", action: extraJar).buttonStyle(SquishButtonStyle(fill: Theme.mint, text: Theme.plum)) }
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(Theme.marshmallow))
        .padding(30)
    }
}
