import SwiftUI
import SquishPolicy

/// Good news after a win: a world finished, or a new place to play. One card at a time,
/// shown when the player moves on from the win card, so it never covers anything.
struct NewsCard: View {
    @EnvironmentObject var model: AppModel
    let news: AppModel.News
    @State private var burst = false

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
                } else if case .unlocked = news {
                    Button { model.newsRead(open: true) } label: {
                        Label("Try it now", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .accessibilityIdentifier("news-open")
                    Button("Keep playing") { model.newsRead() }
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
            .scaleEffect(burst ? 1 : 0.7)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { burst = true }
        }
    }

    @ViewBuilder private var picture: some View {
        switch news {
        case .worldComplete:
            Text(verbatim: "🏆").font(.system(size: 70))
        case .trick:
            if let ref = model.progress.buddy.squishy {
                SquishRefView(ref: ref).frame(width: 120, height: 120)
            } else {
                Text(verbatim: "🎪").font(.system(size: 70))
            }
        case .unlocked(let extra):
            Image(systemName: extra == .mysteryBag ? "bag.fill" : "paintbrush.fill")
                .font(.system(size: 44, weight: .bold)).foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: 28).fill(extra == .mysteryBag ? Theme.grape : Theme.mint))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.plum, lineWidth: 4))
        }
    }

    private var title: LocalizedStringKey {
        switch news {
        case .worldComplete(let world, _):
            switch world {
            case "toyshop": return "Toy Shop complete!"
            case "sweetfactory": return "Sweet Factory complete!"
            case "starlight": return "Starlight Stage complete!"
            default: return "World complete!"
            }
        case .unlocked(let extra):
            return extra == .mysteryBag ? "New: Mystery Bag!" : "New: Squishy Maker!"
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
            default: return "You sorted every jar. What a star!"
            }
        case .trick:
            return "Double tap your Buddy at home to see it."
        case .unlocked(let extra):
            return extra == .mysteryBag
                ? "Poke the bag and guess who's inside. A new bag every day, on your shelf at home."
                : "Finishing Toy Shop opened the Maker. Make your very own squishy and give it a name."
        }
    }
}
