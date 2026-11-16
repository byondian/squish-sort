import SwiftUI
import SquishLevels
import SquishPolicy

/// Paper confetti falling down the screen for a few seconds. Drawn in one canvas, so it is cheap.
struct Confetti: View {
    var colors: [Color] = [Theme.bubblegum, Theme.butter, Theme.mint, Theme.sky, Theme.grape]
    var count = 70
    var seconds: Double = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var over = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: over || reduceMotion)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                if reduceMotion || colors.isEmpty { return }
                for i in 0..<count {
                    let seed = Double(i)
                    let delay = Confetti.part(seed * 0.377) * 0.9
                    let life = t - delay
                    if life <= 0 { continue }
                    let speed = 240 + Confetti.part(seed * 0.911) * 280
                    let y = -20 + life * speed
                    if y > size.height + 20 { continue }
                    let x = Confetti.part(seed * 0.618) * size.width + sin(life * 3 + seed) * 18
                    var piece = ctx
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(life * 4 + seed))
                    piece.fill(Path(roundedRect: CGRect(x: -5, y: -3, width: 10, height: 6), cornerRadius: 1.5),
                               with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            start = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { over = true }
        }
    }

    private static func part(_ value: Double) -> Double { value - value.rounded(.down) }
}

/// A world is finished: its squishies rain in, the stars and the coin reward are counted,
/// then a curtain opens on the next world. Shown once per world, the same for all ages.
struct WorldCompleteView: View {
    @EnvironmentObject var model: AppModel
    let world: String
    let next: String?
    @State private var landed = false
    @State private var shownCoins = 0
    @State private var coinsReady = false
    @State private var coinsFly = false
    @State private var page = 0
    @State private var curtainOpen = false
    @State private var spin = 0.0
    @State private var flip = 0.0
    @State private var sway: CGFloat = 0

    private var colors: [Color] {
        switch world {
        case "toyshop": return [Theme.bubblegum, Theme.butter, Theme.sky]
        case "sweetfactory": return [Theme.bubblegum, Theme.mint, Theme.butter]
        case "starlight": return [Theme.grape, Theme.sky, Theme.butter]
        default: return [Theme.bubblegum, Theme.mint, Theme.butter, Theme.sky]
        }
    }

    private var owned: [Collectible] {
        Array(model.roster.collectibles.filter { $0.world == world && model.progress.collection.owns($0.id) }.prefix(8))
    }

    private var toFind: [Collectible] {
        guard let next else { return [] }
        return Array(model.roster.collectibles.filter { $0.world == next && !model.progress.collection.owns($0.id) }.prefix(3))
    }

    /// The last world of the main path has nothing after it.
    private var finishedEverything: Bool { next == nil && world == LevelCatalog.worlds.last }

    var body: some View {
        ZStack {
            Theme.marshmallow.ignoresSafeArea()
            if page == 0 { celebration.transition(.opacity) } else { arrival.transition(.opacity) }
            Confetti(colors: colors).id(page)
        }
        .onAppear {
            model.sounds.play("world_complete", or: "win_boss")
            model.haptics.win()
            shownCoins = max(0, model.progress.wallet.balance - model.config.coins.worldComplete)
            withAnimation { landed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { coinsReady = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                coinsFly = true
                model.sounds.play("coin_shower")
                withAnimation(.easeOut(duration: 1.0)) { shownCoins = model.progress.wallet.balance }
            }
            if finishedEverything { DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { everyTrick() } }
        }
    }

    private var celebration: some View {
        VStack(spacing: 16) {
            HStack {
                Label { Text("\(shownCoins)") } icon: { CoinIcon() }
                    .font(Theme.body(17)).foregroundStyle(Theme.plum).monospacedDigit()
                    .contentTransition(.numericText(value: Double(shownCoins)))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(.white))
                Spacer()
            }
            Spacer(minLength: 0)
            Text(verbatim: "🏆").font(.system(size: 64))
                .scaleEffect(landed ? 1 : 0.2)
                .animation(.spring(response: 0.5, dampingFraction: 0.45), value: landed)
            Text(title).font(Theme.title(32)).foregroundStyle(Theme.plum).multilineTextAlignment(.center)
            let stars = model.stars(inWorld: world)
            Label("\(stars.earned) of \(stars.possible) stars", systemImage: "star.fill")
                .font(Theme.body(18)).foregroundStyle(Theme.plum)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.butter))
            Label { Text("+\(model.config.coins.worldComplete)") } icon: { CoinIcon() }
                .font(Theme.title(24)).foregroundStyle(Theme.plum)
                .scaleEffect(coinsFly ? 1 : 0.3).opacity(coinsFly ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.5), value: coinsFly)
            if finishedEverything {
                Text("You finished every world! More are on the way.")
                    .font(Theme.body(17)).foregroundStyle(Theme.plum.opacity(0.8)).multilineTextAlignment(.center)
                if let ref = model.progress.buddy.squishy {
                    SquishRefView(ref: ref).frame(width: 110, height: 110)
                        .rotationEffect(.degrees(spin))
                        .modifier(FlipEffect(turn: flip))
                        .offset(x: sway)
                }
            }
            // The world's squishies drop in and bounce.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Array(owned.enumerated()), id: \.element.id) { i, c in
                    SquishyView(id: c.id, rarity: c.rarity).frame(width: 64, height: 64)
                        .offset(y: landed ? 0 : -700)
                        .animation(.interpolatingSpring(stiffness: 90, damping: 9).delay(0.15 + Double(i) * 0.12), value: landed)
                }
            }
            Spacer(minLength: 0)
            Button {
                if next != nil {
                    model.sounds.play("curtain", or: "unlock_new")
                    withAnimation(.easeInOut(duration: 0.3)) { page = 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.9)) { curtainOpen = true }
                    }
                } else {
                    model.newsRead()
                }
            } label: { Text("Yay!").frame(maxWidth: .infinity) }
                .buttonStyle(SquishButtonStyle())
                .accessibilityIdentifier("news-next")
        }
        .padding(20)
        .overlay {
            // The reward flies up to the coin counter.
            GeometryReader { geo in
                if coinsReady {
                ForEach(0..<10, id: \.self) { i in
                    CoinIcon()
                        .font(.system(size: 22)).foregroundStyle(Theme.butter)
                        .shadow(color: Theme.plum.opacity(0.6), radius: 1)
                        .position(coinsFly
                            ? CGPoint(x: 54, y: 38)
                            : CGPoint(x: geo.size.width * 0.5 + CGFloat((i * 37) % 120 - 60),
                                      y: geo.size.height * 0.5 + CGFloat((i * 53) % 70 - 35)))
                        .opacity(coinsFly ? 0 : 1)
                        .animation(.easeIn(duration: 0.55).delay(Double(i) * 0.05), value: coinsFly)
                }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// The next world arrives from behind a curtain.
    private var arrival: some View {
        ZStack {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                if let next {
                    Text(AppModel.worldName(next)).font(Theme.title(36)).foregroundStyle(Theme.plum)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 14) {
                    ForEach(toFind, id: \.id) { c in
                        SquishyView(id: c.id, rarity: c.rarity, silhouette: true).frame(width: 84, height: 84)
                            .overlay { Text(verbatim: "?").font(Theme.title(30)).foregroundStyle(Theme.plum.opacity(0.5)) }
                    }
                }
                Text("New squishies to find!").font(Theme.body(17)).foregroundStyle(Theme.plum.opacity(0.75))
                Spacer(minLength: 0)
                Button { model.newsRead() } label: { Text("Let's go!").frame(maxWidth: .infinity) }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .accessibilityIdentifier("news-next")
                    .opacity(curtainOpen ? 1 : 0)
            }
            .padding(20)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    curtainHalf.offset(x: curtainOpen ? -geo.size.width / 2 - 20 : 0)
                    curtainHalf.offset(x: curtainOpen ? geo.size.width / 2 + 20 : 0)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var curtainHalf: some View {
        Rectangle().fill(Theme.bubblegum)
            .overlay {
                HStack(spacing: 22) {
                    ForEach(0..<4, id: \.self) { _ in Rectangle().fill(Theme.plum.opacity(0.08)).frame(width: 10) }
                }
            }
    }

    private var title: LocalizedStringKey {
        switch world {
        case "toyshop": return "Toy Shop complete!"
        case "sweetfactory": return "Sweet Factory complete!"
        case "starlight": return "Starlight Stage complete!"
        default: return "World complete!"
        }
    }

    /// The Buddy shows off: spin, flip, then a dance.
    private func everyTrick() {
        withAnimation(.easeInOut(duration: 0.6)) { spin = 360 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            spin = 0
            withAnimation(.easeInOut(duration: 0.6)) { flip = 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            flip = 0
            withAnimation(.easeInOut(duration: 0.15).repeatCount(6, autoreverses: true)) { sway = 14 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { withAnimation(.easeOut(duration: 0.1)) { sway = 0 } }
    }
}
