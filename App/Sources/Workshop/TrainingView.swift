import SwiftUI
import SquishPolicy
import SquishWorkshop

/// Teach a made squishy a move (Workshop Pro): drag it about to show it, and it copies. The first
/// showing is the move; it copies clumsily, then better, and has learned it on the third try.
/// Practice never costs or earns anything and never runs out of time between tries.
struct TrainingView: View {
    @EnvironmentObject var model: AppModel
    let made: MadeSquishy
    let close: () -> Void

    @State private var moves: [TaughtMove] = []
    /// The move being taught or practised.
    @State private var active: String?
    @State private var raw: [WorkshopPoint] = []
    @State private var startedAt: Date?
    @State private var spot = TrainingView.home
    @State private var held = false
    @State private var replay: [WorkshopPoint] = []
    @State private var replayStart: Date?
    @State private var replaySeconds = 1.0
    @State private var cheer = false

    private static let home = WorkshopPoint(x: 0.5, y: 0.62)
    private let clock = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    private var current: TaughtMove? { moves.first { $0.id == active } }
    private var playing: Bool { replayStart != nil }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Teach a trick").font(Theme.title(22)).foregroundStyle(Theme.plum)
                Spacer()
                IconButton(system: "xmark", action: close)
            }
            Text(prompt).font(Theme.title(20)).foregroundStyle(Theme.bubblegum)
                .accessibilityIdentifier("ws-train-say")
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    RoundedRectangle(cornerRadius: 28).fill(Color.white.opacity(0.7))
                    if let move = current {
                        // The move so far, as a dotted trail.
                        DrawnStrokes(strokes: [move.path])
                            .stroke(Theme.grape.opacity(0.35), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 10]))
                    }
                    MadeSquishyView(made: made, squash: held ? 0.35 : 0)
                        .frame(width: 130, height: 130)
                        .position(x: size.width * CGFloat(spot.x), y: size.height * CGFloat(spot.y))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in drag(to: value.location, in: size) }
                        .onEnded { _ in letGo() }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: made.name))
                .accessibilityIdentifier("ws-train-pad")
            }
            chips
        }
        .padding(16)
        .background(Theme.marshmallow.ignoresSafeArea())
        .onAppear { moves = made.design?.moves ?? [] }
        .onReceive(clock) { now in tick(now) }
    }

    private var prompt: LocalizedStringKey {
        if cheer { return "It learned a trick!" }
        if let move = current, !move.learned { return "Again!" }
        return "Show me!"
    }

    /// One chip per move: its picture when learned, dots for the tries so far, and a whistle for a new one.
    private var chips: some View {
        HStack(spacing: 10) {
            ForEach(Array(moves.enumerated()), id: \.element.id) { index, move in
                Button {
                    active = move.id
                    cheer = false
                    if move.learned { play(move) }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: TrainingView.symbol(move.icon)).font(.system(size: 20, weight: .bold))
                        HStack(spacing: 3) {
                            ForEach(0..<TrickTraining.triesToLearn, id: \.self) { n in
                                Circle().fill(n < move.tries ? Theme.bubblegum : Theme.plum.opacity(0.2)).frame(width: 6, height: 6)
                            }
                        }
                    }
                    .foregroundStyle(active == move.id ? Color.white : Theme.plum)
                    .frame(width: 64, height: 56)
                    .background(RoundedRectangle(cornerRadius: 16).fill(active == move.id ? Theme.grape : Color.white))
                }
                .buttonStyle(PressSquish())
                .accessibilityLabel(Text("Teach a trick"))
                .accessibilityValue(Text(verbatim: "\(index + 1)"))
                .accessibilityIdentifier("ws-train-move-\(index + 1)")
            }
            if moves.count < TrickTraining.maxMoves {
                Button {
                    active = nil
                    cheer = false
                } label: {
                    Image(systemName: "plus").font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(active == nil ? Color.white : Theme.plum)
                        .frame(width: 64, height: 56)
                        .background(RoundedRectangle(cornerRadius: 16).fill(active == nil ? Theme.grape : Color.white))
                }
                .buttonStyle(PressSquish())
                .accessibilityLabel(Text("New"))
                .accessibilityIdentifier("ws-train-new")
            }
            Spacer()
            if let move = current, move.learned {
                // The player picks the picture for a move it has learned.
                ForEach(TrickTraining.icons, id: \.self) { icon in
                    Button {
                        change(move.id) { $0.icon = icon }
                    } label: {
                        Image(systemName: TrainingView.symbol(icon)).font(.system(size: 15, weight: .bold))
                            .foregroundStyle(move.icon == icon ? Theme.bubblegum : Theme.plum.opacity(0.5))
                            .frame(width: 34, height: 34).background(Circle().fill(.white))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ws-train-icon-\(icon)")
                }
            }
        }
    }

    static func symbol(_ icon: String) -> String {
        switch icon {
        case "heart": return "heart.fill"
        case "loop": return "arrow.triangle.2.circlepath"
        case "zigzag": return "bolt.fill"
        default: return "star.fill"
        }
    }

    private func drag(to location: CGPoint, in size: CGSize) {
        guard !playing, size.width > 0, size.height > 0 else { return }
        let now = Date()
        if startedAt == nil {
            startedAt = now
            raw = []
            held = true
            cheer = false
            model.haptics.lift()
        }
        // Four seconds is the longest move: after that the squishy stays put until the finger lifts.
        guard let startedAt, now.timeIntervalSince(startedAt) <= TrickTraining.maxSeconds else { return }
        let p = WorkshopPoint(x: min(1, max(0, Double(location.x / size.width))), y: min(1, max(0, Double(location.y / size.height))))
        raw.append(p)
        spot = p
    }

    private func letGo() {
        guard let startedAt else { return }
        let seconds = min(TrickTraining.maxSeconds, Date().timeIntervalSince(startedAt))
        self.startedAt = nil
        held = false
        if let move = current, !move.learned {
            // A second or third showing: whatever was done, it copies the first one a little better.
            change(move.id) { $0.tries += 1 }
        } else if current == nil, moves.count < TrickTraining.maxMoves, let fresh = TrickTraining.record(raw, seconds: seconds) {
            moves.append(fresh)
            active = fresh.id
            save()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { spot = TrainingView.home }
            return
        }
        if let move = current {
            if move.learned {
                cheer = true
                model.sounds.play("trick")
                model.haptics.win()
            }
            play(move)
        }
    }

    private func play(_ move: TaughtMove) {
        replay = TrickTraining.replay(move, seed: Int.random(in: 0..<10_000))
        replaySeconds = max(0.4, move.seconds)
        replayStart = Date()
        model.sounds.play("hop")
    }

    private func tick(_ now: Date) {
        guard let replayStart, !replay.isEmpty else { return }
        let t = now.timeIntervalSince(replayStart) / replaySeconds
        if t >= 1 {
            self.replayStart = nil
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { spot = TrainingView.home }
            return
        }
        spot = replay[min(replay.count - 1, Int(t * Double(replay.count)))]
    }

    private func change(_ id: String, _ edit: (inout TaughtMove) -> Void) {
        guard let i = moves.firstIndex(where: { $0.id == id }) else { return }
        edit(&moves[i])
        save()
    }

    /// Kept with the squishy at once, so a half-learned move is never lost.
    private func save() {
        guard var design = made.design else { return }
        design.moves = moves
        var copy = made
        copy.design = design
        _ = model.saveMade(copy)
    }
}
