import SwiftUI
import SquishPolicy

/// Good news after a win: a world finished, or a new place to play. One card at a time,
/// shown when the player moves on from the win card, so it never covers anything.
struct NewsCard: View {
    @EnvironmentObject var model: AppModel
    let news: AppModel.News
    @State private var burst = false
    @State private var spin = 0.0
    @State private var flip = 0.0
    @State private var sway: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            // A burst of stars and hearts behind the card.
            ForEach(0..<14, id: \.self) { i in
                let angle = Double(i) / 14 * 2 * Double.pi
                Text(verbatim: ["⭐️", "💖", "✨", "🎉"][i % 4])
                    .font(.system(size: 26))
                    .offset(x: burst ? CGFloat(cos(angle)) * 170 : 0, y: burst ? CGFloat(sin(angle)) * 230 : 0)
                    .opacity(burst ? 0 : 1)
                    .scaleEffect(burst ? 1.4 : 0.4)
            }
            VStack(spacing: 14) {
                picture
                Text(title).font(Theme.title(28)).foregroundStyle(Theme.plum).multilineTextAlignment(.center)
                Text(detail).font(Theme.body(16)).foregroundStyle(Theme.plum.opacity(0.75)).multilineTextAlignment(.center)
                if case .trick = news {
                    Button { model.newsRead() } label: { Text("Yay!").frame(maxWidth: .infinity) }
                        .buttonStyle(SquishButtonStyle())
                        .accessibilityIdentifier("news-next")
                } else if case .starterPack = news {
                    Button { model.newsRead(open: true) } label: {
                        Label("See it in the shop", systemImage: "bag.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    Button("Later") { model.newsRead() }
                        .font(Theme.body(16)).foregroundStyle(Theme.plum.opacity(0.7))
                        .accessibilityIdentifier("news-next")
                } else if case .unlocked = news {
                    Button { model.newsRead(open: true) } label: {
                        Label("Try it", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .accessibilityIdentifier("news-open")
                    Button("Later") { model.newsRead() }
                        .font(Theme.body(16)).foregroundStyle(Theme.plum.opacity(0.7))
                        .accessibilityIdentifier("news-next")
                } else {
                    Button { model.newsRead() } label: { Text("Yay!").frame(maxWidth: .infinity) }
                        .buttonStyle(SquishButtonStyle())
                        .accessibilityIdentifier("news-next")
                }
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 30).fill(Theme.marshmallow))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.plum.opacity(0.15), lineWidth: 2))
            .padding(30)
            .frame(maxWidth: 560)
            .scaleEffect(burst ? 1 : 0.7)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { burst = true }
        }
    }

    @ViewBuilder private var picture: some View {
        switch news {
        case .teaser, .finale:
            EmptyView()
        case .worldComplete:
            Text(verbatim: "🏆").font(.system(size: 70))
        case .starterPack:
            Text(verbatim: "🎁").font(.system(size: 70))
        case .bossBeaten:
            Text(verbatim: "👑").font(.system(size: 70))
        case .trick:
            if let ref = model.progress.buddy.squishy {
                // The Buddy does its new trick right here, again and again while the card is open.
                SquishRefView(ref: ref).frame(width: 120, height: 120)
                    .rotationEffect(.degrees(spin))
                    .modifier(FlipEffect(turn: flip))
                    .offset(x: sway)
                    .padding(.top, 30)
                    .onTapGesture { doTrick() }
                    .task {
                        while !Task.isCancelled {
                            doTrick()
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                        }
                    }
            } else {
                Text(verbatim: "🎪").font(.system(size: 70))
            }
        case .starJar(_, let prize):
            Image(systemName: "star.fill")
                .font(.system(size: 48, weight: .bold)).foregroundStyle(Theme.butter)
                .shadow(color: Theme.plum.opacity(0.5), radius: 1)
                .frame(width: 96, height: 96)
                .background(Circle().fill(prize >= 3 ? Theme.grape : Theme.sky))
                .overlay(Circle().stroke(Theme.plum, lineWidth: 4))
        case .unlocked(let extra):
            Image(systemName: extra == .mysteryBag ? "bag.fill" : extra == .maker ? "paintbrush.fill" : "hand.point.up.left.fill")
                .font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: 28).fill(extra == .mysteryBag ? Theme.grape : extra == .maker ? Theme.mint : Theme.bubblegum))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.plum, lineWidth: 4))
        }
    }

    private func doTrick() {
        guard case .trick(let number) = news, spin == 0, flip == 0, sway == 0 else { return }
        if !AppModel.isUITesting { model.sounds.play("trick", or: "buddy_giggle") }
        switch number {
        case 1:
            withAnimation(.easeInOut(duration: 0.6)) { spin = 360 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { spin = 0 }
        case 2:
            withAnimation(.easeInOut(duration: 0.7)) { flip = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { flip = 0 }
        default:
            withAnimation(.easeInOut(duration: 0.15).repeatCount(6, autoreverses: true)) { sway = 14 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { withAnimation(.easeOut(duration: 0.1)) { sway = 0 } }
        }
    }

    private var title: LocalizedStringKey {
        switch news {
        case .worldComplete(let world, _):
            switch world {
            case "toyshop": return "Toy Shop complete!"
            case "sweetfactory": return "Sweet Factory complete!"
            case "starlight": return "Starlight Stage complete!"
            case "bubblebath": return "Bubble Bath complete!"
            case "junglejam": return "Jungle Jam complete!"
            default: return "World complete!"
            }
        case .unlocked(let extra):
            switch extra {
            case .mysteryBag: return "You unlocked the Mystery Bag!"
            case .maker: return "You unlocked the Squishy Maker!"
            case .squishRoom: return "You unlocked the Squish Room!"
            case .buddy: return "You have a Buddy!"
            }
        case .teaser, .finale:
            return ""
        case .starterPack:
            return "Starter pack"
        case .bossBeaten:
            return "Boss beaten!"
        case .starJar:
            return "Star jar prize!"
        case .trick(let number):
            switch number {
            case 1: return "New trick: Spin!"
            case 2: return "New trick: Flip!"
            default: return "New trick: Dance!"
            }
        }
    }

    private var detail: LocalizedStringKey {
        switch news {
        case .worldComplete(_, let next):
            switch next {
            case "sweetfactory": return "You sorted every jar. Sweet Factory is open!"
            case "starlight": return "You sorted every jar. Starlight Stage is open!"
            case "bubblebath": return "You sorted every jar. Bubble Bath is open!"
            case "junglejam": return "You sorted every jar. Jungle Jam is open!"
            default: return "You sorted every jar. What a star!"
            }
        case .starJar(_, let prize):
            switch prize {
            case 1: return "You won \(AppModel.starJarCoins) coins for your stars."
            case 2: return "You won a capsule for your stars."
            default: return "Every star in this world! You won a golden capsule."
            }
        case .teaser, .finale:
            return ""
        case .bossBeaten:
            return "You out-sorted the boss. On to the next jars!"
        case .starterPack:
            return "\(StarterPack.coins) coins, \(StarterPack.hints) hints and the Golden Hour board. It is in the shop whenever you like."
        case .trick:
            return "Tap the trick under your Buddy at home to see it again."
        case .unlocked(let extra):
            switch extra {
            case .mysteryBag: return "Poke the bag and guess who's inside. A new bag every day, on your shelf at home."
            case .maker: return "Finishing Toy Shop opened the Maker. Make your very own squishy and give it a name."
            case .squishRoom: return "Squeeze, poke and stretch your squishies whenever you like."
            case .buddy: return "Your Buddy lives at home. Give it treats and pats."
            }
        }
    }
}
