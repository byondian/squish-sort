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
    /// Coins the last win paid (0 on a replay), for the win card.
    @Published private(set) var earnedCoins = 0
    /// The hint search is running.
    @Published private(set) var thinking = false
    /// The hint search found no way to win from here. Nothing is charged for that.
    @Published var noWayThrough = false
    /// A hint found for the current board, waiting to be paid for or shown.
    private var foundHint: (board: Board, move: Move)?
    private(set) var attempts = 1
    private var started = Date()
    private weak var model: AppModel?

    init(index: Int, model: AppModel) {
        self.index = index
        self.model = model
        level = model.levels[index]
        session = GameSession(board: level.board, par: level.par, undoLimit: model.undoLimit)
        scene = BoardScene(board: level.board, kinds: level.kinds)
        scene.onPlay = { [weak self] move in self?.play(move) }
        scene.onLift = { [weak model] in model?.haptics.lift() }
        scene.onReject = { [weak model] in model?.haptics.reject() }
        scene.onLand = { [weak model] result in
            if result.completedJar != nil { model?.haptics.complete() } else { model?.haptics.land() }
        }
        scene.onMoveFinished = { [weak self] _ in self?.checkOutcome() }
        // The very first board opens mid-move: one squishy already lifted and a
        // hand on the jar it belongs in, so the first tap finishes a jar.
        if index == 0, model.progress.stars.isEmpty, let first = level.solution.first {
            scene.tutorialMove = first
        }
    }

    private func play(_ move: Move) -> (MoveResult, Board)? {
        guard let result = session.play(move) else { return nil }
        noWayThrough = false
        return (result, session.board)
    }

    private func checkOutcome() {
        guard let model else { return }
        let seconds = Date().timeIntervalSince(started)
        switch session.status {
        case .won(let stars):
            outcome = .won(stars: stars)
            earnedCoins = model.coinsForWin(index: index, stars: stars)
            scene.celebrate()
            model.haptics.win()
            model.won(index: index, moves: session.moveCount, stars: stars, attempts: attempts, playSeconds: seconds)
        case .stuck:
            outcome = .stuck
            scene.sigh()
            model.failed(playSeconds: seconds)
        case .playing:
            break
        }
    }

    func undo() {
        guard session.undo() else { return }
        noWayThrough = false
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
            model.watchRewarded(grant)
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
        thinking = true
        let board = session.board
        Task {
            let move = await Task.detached(priority: .userInitiated) { Solver.hint(board) }.value
            thinking = false
            guard let model, board == session.board, outcome == nil else { return }
            guard let move else {
                noWayThrough = true
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
        session = GameSession(board: level.board, par: level.par, undoLimit: model?.undoLimit ?? 5)
        // Real walls soften: one extra jar after enough fails.
        if let soften = level.file.softenAfterFails, attempts > soften { session.addExtraJar() }
        extraJarUsed = false
        noWayThrough = false
        outcome = nil
        scene.reload(session.board)
    }
}

struct LevelView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var controller: LevelController

    init(index: Int, model: AppModel) {
        _controller = StateObject(wrappedValue: LevelController(index: index, model: model))
    }

    private var number: Int { controller.index + 1 }

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
            if controller.noWayThrough && controller.outcome == nil {
                VStack {
                    Text("No way through from here. Undo a few moves.")
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
                    WinCard(stars: stars, showpiece: controller.level.file.beat == .showpiece,
                            coins: controller.earnedCoins,
                            toCapsule: model.levelsToNextCapsule(after: controller.index),
                            // The first two levels roll straight on after the celebration.
                            autoAdvance: controller.index < 2,
                            haptics: model.haptics,
                            gift: model.giftOffered ? { model.openGift() } : nil) {
                        model.continueAfterWin(index: controller.index, attempts: controller.attempts)
                    }
                case .stuck:
                    StuckCard(canUndo: controller.session.canUndo,
                              canExtraJar: controller.canExtraJar,
                              undo: controller.undo, extraJar: controller.extraJar, retry: controller.retry)
                }
            }
        }
        .background(LinearGradient(colors: model.boardTheme.colors, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.outcome)
        .confirmationDialog(Text(controller.choosing == .hint ? "Hint" : "Extra jar"),
                            isPresented: Binding(get: { controller.choosing != nil }, set: { if !$0 { controller.choosing = nil } }),
                            titleVisibility: .visible) {
            if let item = controller.choosing {
                if model.canWatchRewarded {
                    Button("Watch an ad") { controller.pay(for: item, withAd: true) }
                }
                if model.progress.wallet.canAfford(item) {
                    Button("Use \(item.price) coins") { controller.pay(for: item, withAd: false) }
                }
                // Under-13s never get a shop pop-up from the board.
                if !model.isGentleMode && !model.progress.wallet.canAfford(item) {
                    Button("Get coins") { controller.choosing = nil; model.screen = .shop }
                }
            }
        } message: {
            Text("You have \(model.progress.wallet.balance) coins")
        }
    }

    private var header: some View {
        HStack {
            if model.showsCornerButtons {
                IconButton(system: "house.fill") { model.screen = .home }
            }
            Spacer()
            VStack(spacing: 2) {
                Text("Level \(number)").font(Theme.title(22))
                if controller.level.file.beat == .boss {
                    Text("BOSS 👑").font(Theme.body(13))
                } else if controller.level.file.beat == .showpiece {
                    Text("HARD").font(Theme.body(13)).foregroundStyle(Theme.bubblegum)
                }
                // Three stars that dim as the move count passes each limit.
                HStack(spacing: 4) {
                    let lit = Stars.rating(moves: controller.session.moveCount, par: controller.level.par)
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "star.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(i < lit ? Theme.butter : Theme.plum.opacity(0.18))
                            .scaleEffect(i < lit ? 1 : 0.8)
                    }
                    Text("\(controller.session.moveCount)").font(Theme.body(14)).opacity(0.7)
                        .accessibilityIdentifier("move-count")
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: controller.session.moveCount)
            }
            .foregroundStyle(Theme.plum)
            Spacer()
            if model.showsCornerButtons {
                IconButton(system: "book.fill") { model.screen = .book }
                IconButton(system: "gearshape.fill") { model.screen = .settings }
            }
        }
        .padding(.top, 8)
    }

    // Undo appears after level 2, Hint after 4, Extra jar after 7 (game design doc).
    private var helpers: some View {
        HStack(spacing: 10) {
            if number >= 2 {
                Button { controller.undo() } label: {
                    Label(undoLabel, systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                .disabled(!controller.session.canUndo)
            }
            if number >= 7 {
                Button { controller.extraJar() } label: { Label("Extra jar", systemImage: "plus") }
                    .buttonStyle(SquishButtonStyle(fill: Theme.mint, text: Theme.plum))
                    .disabled(!controller.canExtraJar)
            }
            if number >= 4 {
                Button { controller.hint() } label: { Label("Hint", systemImage: "lightbulb.fill") }
                    .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                    .disabled(!controller.canHint)
            }
            Button { controller.retry() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
        }
        .labelStyle(.titleAndIcon)
        .font(Theme.body(15))
        .padding(.bottom, 8)
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

    private var undoLabel: String {
        if let left = controller.session.undosLeft { return String(localized: "Undo \(left)") }
        return String(localized: "Undo")
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

struct WinCard: View {
    let stars: Int
    let showpiece: Bool
    var coins = 0
    /// Levels still to win before the next capsule (0 = the next level has one).
    var toCapsule: Int?
    var autoAdvance = false
    var haptics: Haptics?
    /// Opt-in bonus gift box (rewarded ad). Nil when not offered.
    var gift: (() -> Void)?
    let next: () -> Void
    @State private var shown = 0
    @State private var coinsShown = 0
    @State private var left = false

    var body: some View {
        VStack(spacing: 16) {
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
            if coins > 0 {
                Label("+\(coinsShown)", systemImage: "circle.hexagongrid.fill").font(Theme.title(20)).foregroundStyle(Theme.plum)
                    .contentTransition(.numericText())
            }
            if let toCapsule {
                Label {
                    if toCapsule == 0 { Text("Capsule next level!") } else { Text("Next capsule: \(toCapsule + 1) more") }
                } icon: {
                    Image(systemName: "gift.fill")
                }
                .font(Theme.body(14)).foregroundStyle(Theme.grape)
            }
            if let gift {
                Button(action: gift) { Label("Bonus gift", systemImage: "gift.fill") }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
            }
            Button("Next") { go() }.buttonStyle(SquishButtonStyle()).font(Theme.title(22))
                .accessibilityIdentifier("win-next")
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(Theme.marshmallow))
        .padding(30)
        .task {
            // Stars slam in one by one, each with a tap you can feel.
            for i in 1...max(1, stars) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { shown = i }
                haptics?.land()
            }
            // Coins count up.
            if coins > 0 {
                for n in 1...coins {
                    try? await Task.sleep(nanoseconds: 45_000_000)
                    withAnimation(.easeOut(duration: 0.05)) { coinsShown = n }
                }
                haptics?.complete()
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
