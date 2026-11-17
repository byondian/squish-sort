import SwiftUI
import SquishCore
import SquishPolicy

/// The twists a board can have. Each is shown once, on the first level that has it.
enum BoardRule: String, CaseIterable {
    case wrapped, duet, frozen, curtain
    /// Not a twist of one world: a run only moves as far as there is room. Taught early in Toy Shop.
    case partial

    /// The rules on this board, in the order they are taught.
    static func rules(on board: Board) -> [BoardRule] {
        var found: Set<BoardRule> = []
        for jar in board.jars {
            for piece in jar {
                if piece.hidden { found.insert(.wrapped) }
                if piece.bondedAbove { found.insert(.duet) }
                if piece.frozen > 0 { found.insert(.frozen) }
            }
        }
        if !board.curtains.isEmpty { found.insert(.curtain) }
        return BoardRule.allCases.filter { found.contains($0) }
    }

    var line: String {
        switch self {
        case .wrapped: return String(localized: "Hidden! Move the one above to unwrap it.")
        case .duet: return String(localized: "Duet! They move together. Land the bottom one on its own kind and they let go.")
        case .frozen: return String(localized: "Frozen! Moves next to it melt the ice.")
        case .partial: return String(localized: "Only what fits moves!")
        case .curtain: return String(localized: "Finish the jar next door to raise the curtain!")
        }
    }
}

/// Show, don't tell: a little stage where a pointing hand plays the rule out, with one line under it.
/// It loops until the player taps "Got it!".
struct RuleDemo: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let rule: BoardRule
    let world: String
    let done: () -> Void
    @State private var step = 0

    private static let xs: [CGFloat] = [50, 130, 210]
    private static let ys: [CGFloat] = [126, 94, 62, 22]

    /// Two of the world's own commons play the parts.
    private var actors: [String] {
        let commons = model.roster.world(world, .common).map(\.id)
        return [commons.first ?? "peach-bun", commons.dropFirst().first ?? commons.first ?? "peach-bun"]
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ForEach(0..<3, id: \.self) { j in jar(j) }
                stage
                hand
            }
            .frame(width: 260, height: 170)
            .background(RoundedRectangle(cornerRadius: 22).fill(Theme.sky.opacity(0.25)))
            Text(verbatim: rule.line).font(Theme.body(17)).foregroundStyle(Theme.plum)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(action: done) { Text("Got it!").frame(maxWidth: 200) }
                .buttonStyle(SquishButtonStyle()).font(Theme.title(20))
                .accessibilityIdentifier("rule-demo-done")
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 30).fill(Theme.marshmallow))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.butter, lineWidth: 4))
        .padding(26)
        .task { await play() }
    }

    @MainActor
    private func play() async {
        // With Reduce Motion the end of the demo is simply shown.
        if reduceMotion { step = 5; return }
        while !Task.isCancelled {
            for s in 0...5 {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { step = s }
                if s == 2 || s == 4 { model.sounds.play("land_soft", volume: 0.5) }
                try? await Task.sleep(nanoseconds: s == 5 ? 1_400_000_000 : 750_000_000)
                if Task.isCancelled { return }
            }
        }
    }

    private func jar(_ j: Int) -> some View {
        // The middle jar shakes its head when a duet does not fit.
        let no = rule == .duet && step == 2 && j == 1
        return RoundedRectangle(cornerRadius: 14)
            .stroke(Theme.plum.opacity(0.35), lineWidth: 3)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.6)))
            .frame(width: 48, height: 106)
            .position(x: RuleDemo.xs[j] + (no ? 5 : 0), y: 96)
            .animation(no ? .easeInOut(duration: 0.07).repeatCount(5, autoreverses: true) : .default, value: step)
    }

    @ViewBuilder
    private var stage: some View {
        switch rule {
        case .wrapped: wrappedStage
        case .duet: duetStage
        case .frozen: frozenStage
        case .partial: partialStage
        case .curtain: curtainStage
        }
    }

    // Curtain: the last one hops in next door, the jar is finished, and the curtain goes up.
    private var curtainStage: some View {
        let moved = step >= 3
        let open = step >= 4
        return ZStack {
            blob(actors[0], x: RuleDemo.xs[0], y: RuleDemo.ys[0])
            blob(actors[0], x: RuleDemo.xs[0], y: RuleDemo.ys[1])
            blob(actors[1], x: RuleDemo.xs[1], y: RuleDemo.ys[0])
            blob(actors[1], x: RuleDemo.xs[1], y: RuleDemo.ys[1])
            blob(actors[1], x: RuleDemo.xs[2], y: RuleDemo.ys[0])
            blob(actors[0], x: moved ? RuleDemo.xs[0] : RuleDemo.xs[2],
                 y: moved ? RuleDemo.ys[2] : (step == 2 ? RuleDemo.ys[3] : RuleDemo.ys[1]))
            if moved {
                // The finished jar gets its lid.
                Capsule().fill(Theme.butter).frame(width: 54, height: 9)
                    .position(x: RuleDemo.xs[0], y: 40)
                    .transition(.scale.combined(with: .opacity))
            }
            RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.69, green: 0.13, blue: 0.33))
                .overlay(Text(verbatim: "★").font(Theme.title(18)).foregroundStyle(Theme.butter))
                .frame(width: 56, height: 112)
                .scaleEffect(x: 1, y: open ? 0.05 : 1, anchor: .top)
                .opacity(open ? 0 : 1)
                .position(x: RuleDemo.xs[1], y: 96)
            Capsule().fill(Theme.butter).frame(width: 62, height: 8).position(x: RuleDemo.xs[1], y: 40)
                .opacity(step >= 5 ? 0 : 1)
        }
    }

    private func blob(_ id: String, x: CGFloat, y: CGFloat) -> some View {
        SquishyView(id: id).frame(width: 34, height: 34).position(x: x, y: y)
    }

    // Wrapped: the one on top moves away and the wrapper falls off the one below.
    private var wrappedStage: some View {
        let moved = step >= 3
        let lifted = step == 2
        let open = step >= 4
        return ZStack {
            blob(actors[0], x: RuleDemo.xs[2], y: RuleDemo.ys[0])
            blob(actors[1], x: RuleDemo.xs[0], y: RuleDemo.ys[0])
            RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .wrapper))
                .overlay(Text(verbatim: "?").font(Theme.title(18)).foregroundStyle(Theme.plum.opacity(0.6)))
                .frame(width: 36, height: 34)
                .position(x: RuleDemo.xs[0], y: RuleDemo.ys[0])
                .scaleEffect(open ? 1.5 : 1).opacity(open ? 0 : 1)
            blob(actors[0], x: moved ? RuleDemo.xs[2] : RuleDemo.xs[0],
                 y: moved ? RuleDemo.ys[1] : (lifted ? RuleDemo.ys[3] : RuleDemo.ys[1]))
        }
    }

    // Duet: two different squishies move as one. The wrong kind turns them away; on the bottom
    // member's own kind they land and let go.
    private var duetStage: some View {
        let moved = step >= 4
        let trying = step == 2
        let x = moved ? RuleDemo.xs[2] : (trying ? (RuleDemo.xs[0] + RuleDemo.xs[1]) / 2 : RuleDemo.xs[0])
        let lift: CGFloat = trying ? -64 : 0
        let low = moved ? RuleDemo.ys[1] : RuleDemo.ys[0] + lift
        let high = moved ? RuleDemo.ys[2] : RuleDemo.ys[1] + lift
        return ZStack {
            blob(actors[1], x: RuleDemo.xs[1], y: RuleDemo.ys[0])
            blob(actors[0], x: RuleDemo.xs[2], y: RuleDemo.ys[0])
            if trying {
                Text(verbatim: "✕").font(Theme.title(22)).foregroundStyle(Theme.bubblegum)
                    .position(x: RuleDemo.xs[1], y: RuleDemo.ys[1])
            }
            // The pair shares one glow until it lets go.
            Capsule().fill(Theme.grape.opacity(0.3))
                .frame(width: 44, height: 72)
                .position(x: x, y: (low + high) / 2)
                .opacity(moved ? 0 : 1)
            blob(actors[0], x: x, y: low)
            blob(actors[1], x: x, y: high)
        }
    }

    // Frozen: each move in or out of the jar next door melts one layer of ice.
    private var frozenStage: some View {
        let ice = step >= 4 ? 0 : (step >= 2 ? 1 : 2)
        let inMiddle = step >= 2 && step < 4
        return ZStack {
            blob(actors[1], x: RuleDemo.xs[0], y: RuleDemo.ys[0])
            if ice > 0 {
                RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .ice).opacity(0.85))
                    .overlay(Text(verbatim: "\(ice)").font(Theme.title(16)).foregroundStyle(Theme.plum))
                    .frame(width: 38, height: 36)
                    .position(x: RuleDemo.xs[0], y: RuleDemo.ys[0])
                    .transition(.scale(scale: 1.5).combined(with: .opacity))
            }
            blob(actors[0], x: RuleDemo.xs[1], y: RuleDemo.ys[0])
            blob(actors[0], x: RuleDemo.xs[2], y: RuleDemo.ys[0])
            blob(actors[0], x: inMiddle ? RuleDemo.xs[1] : RuleDemo.xs[2], y: RuleDemo.ys[1])
        }
    }

    // Only what fits: two of a kind on top, one space next door. One hops over, the other stays and wobbles.
    private var partialStage: some View {
        let moved = step >= 3
        let stays = step >= 3 && step <= 4
        return ZStack {
            blob(actors[1], x: RuleDemo.xs[0], y: RuleDemo.ys[0])
            blob(actors[0], x: RuleDemo.xs[0], y: RuleDemo.ys[1])
                .offset(x: stays ? 4 : 0)
                .animation(stays ? .easeInOut(duration: 0.1).repeatCount(5, autoreverses: true) : .default, value: step)
            blob(actors[1], x: RuleDemo.xs[1], y: RuleDemo.ys[0])
            blob(actors[0], x: RuleDemo.xs[1], y: RuleDemo.ys[1])
            blob(actors[0], x: moved ? RuleDemo.xs[1] : RuleDemo.xs[0],
                 y: step == 2 ? RuleDemo.ys[3] : RuleDemo.ys[2])
        }
    }

    /// The hand taps where the move starts, then where it ends.
    private var hand: some View {
        let spot: CGPoint
        switch (rule, step) {
        case (.wrapped, 1), (.wrapped, 2): spot = CGPoint(x: RuleDemo.xs[0], y: RuleDemo.ys[1])
        case (.wrapped, 3): spot = CGPoint(x: RuleDemo.xs[2], y: RuleDemo.ys[1])
        case (.duet, 1): spot = CGPoint(x: RuleDemo.xs[0], y: RuleDemo.ys[1])
        case (.duet, 2): spot = CGPoint(x: RuleDemo.xs[1], y: RuleDemo.ys[1])
        case (.duet, 3), (.duet, 4): spot = CGPoint(x: RuleDemo.xs[2], y: RuleDemo.ys[1])
        case (.frozen, 1): spot = CGPoint(x: RuleDemo.xs[2], y: RuleDemo.ys[1])
        case (.frozen, 2), (.frozen, 3): spot = CGPoint(x: RuleDemo.xs[1], y: RuleDemo.ys[1])
        case (.frozen, 4): spot = CGPoint(x: RuleDemo.xs[2], y: RuleDemo.ys[1])
        case (.partial, 1), (.partial, 2): spot = CGPoint(x: RuleDemo.xs[0], y: RuleDemo.ys[2])
        case (.partial, 3): spot = CGPoint(x: RuleDemo.xs[1], y: RuleDemo.ys[2])
        case (.curtain, 1), (.curtain, 2): spot = CGPoint(x: RuleDemo.xs[2], y: RuleDemo.ys[1])
        case (.curtain, 3): spot = CGPoint(x: RuleDemo.xs[0], y: RuleDemo.ys[2])
        default: spot = CGPoint(x: 130, y: 190)
        }
        let shown = step >= 1 && step <= 4
        return Text(verbatim: "👆").font(.system(size: 30))
            .position(x: spot.x + 6, y: spot.y + 30)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(false)
    }
}
