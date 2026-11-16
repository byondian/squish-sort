import SpriteKit
import SwiftUI
import SquishCore
import SquishLevels

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
    }

    private func play(_ move: Move) -> (MoveResult, Board)? {
        guard let result = session.play(move) else { return nil }
        return (result, session.board)
    }

    private func checkOutcome() {
        guard let model else { return }
        let seconds = Date().timeIntervalSince(started)
        switch session.status {
        case .won(let stars):
            outcome = .won(stars: stars)
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
        outcome = nil
        scene.reload(session.board)
    }

    var canExtraJar: Bool {
        guard let model else { return false }
        return model.canUseFreeExtraJar(usedThisLevel: extraJarUsed) || (!extraJarUsed && model.canWatchRewarded)
    }

    var canHint: Bool {
        guard let model else { return false }
        return model.hintsAvailable || model.canWatchRewarded
    }

    func extraJar() {
        guard let model else { return }
        if model.canUseFreeExtraJar(usedThisLevel: extraJarUsed) {
            model.useFreeExtraJar()
            addJar()
        } else if !extraJarUsed && model.canWatchRewarded {
            model.watchRewarded { [weak self] in self?.addJar() }
        }
    }

    private func addJar() {
        extraJarUsed = true
        session.addExtraJar()
        outcome = nil
        scene.reload(session.board)
    }

    func hint() {
        guard let model else { return }
        if model.hintsAvailable {
            model.useHint()
            showHint()
        } else if model.canWatchRewarded {
            model.watchRewarded { [weak self] in self?.showHint() }
        }
    }

    private func showHint() {
        if let move = Solver.hint(session.board) { scene.showHint(move) }
    }

    func retry() {
        attempts += 1
        started = Date()
        session = GameSession(board: level.board, par: level.par, undoLimit: model?.undoLimit ?? 5)
        // Real walls soften: one extra jar after enough fails.
        if let soften = level.file.softenAfterFails, attempts > soften { session.addExtraJar() }
        extraJarUsed = false
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
            if let outcome = controller.outcome {
                Color.black.opacity(0.15).ignoresSafeArea()
                switch outcome {
                case .won(let stars):
                    WinCard(stars: stars, showpiece: controller.level.file.beat == .showpiece) {
                        model.continueAfterWin(index: controller.index, attempts: controller.attempts)
                    }
                case .stuck:
                    StuckCard(canUndo: controller.session.canUndo,
                              canExtraJar: controller.canExtraJar,
                              undo: controller.undo, extraJar: controller.extraJar, retry: controller.retry)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.outcome)
    }

    private var header: some View {
        HStack {
            if model.showsCornerButtons {
                IconButton(system: "map.fill") { model.screen = .map }
            }
            Spacer()
            VStack(spacing: 2) {
                Text("Level \(number)").font(Theme.title(22))
                if controller.level.file.beat == .boss {
                    Text("BOSS 👑").font(Theme.body(13))
                } else if controller.level.file.beat == .showpiece {
                    Text("HARD").font(Theme.body(13)).foregroundStyle(Theme.bubblegum)
                }
                Text("Moves \(controller.session.moveCount) · Par \(controller.level.par)").font(Theme.body(14)).opacity(0.7)
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
        HStack(spacing: 2) {
            ForEach(0..<controller.scene.board.jarCount, id: \.self) { j in
                Button("jar-\(j)") { controller.scene.tapJar(j) }
                    .font(.system(size: 6))
                    .frame(width: 24, height: 12)
                    .opacity(0.05)
                    .accessibilityIdentifier("jar-\(j)")
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
    }
}

struct WinCard: View {
    let stars: Int
    let showpiece: Bool
    let next: () -> Void
    @State private var shown = 0

    var body: some View {
        VStack(spacing: 16) {
            Text(showpiece ? "Genius!" : "Sorted!").font(Theme.title(34)).foregroundStyle(Theme.plum)
            HStack(spacing: 10) {
                ForEach(0..<3) { i in
                    Image(systemName: i < shown ? "star.fill" : "star")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(i < shown ? Theme.butter : Theme.plum.opacity(0.25))
                        .scaleEffect(i < shown ? 1 : 0.7)
                }
            }
            Button("Next", action: next).buttonStyle(SquishButtonStyle()).font(Theme.title(22))
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 32).fill(Theme.marshmallow))
        .padding(30)
        .task {
            for i in 1...stars {
                try? await Task.sleep(nanoseconds: 350_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { shown = i }
            }
        }
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
