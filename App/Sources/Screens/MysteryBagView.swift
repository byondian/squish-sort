import SwiftUI
import SquishPolicy

/// Mystery Bag: once a day, poke the bag three ways, then guess who's inside.
/// Any guess pays coins, and a right guess moves the capsule bar on one step.
/// After a wrong guess, one more guess a day by opt-in ad (never in gentle mode).
struct MysteryBagView: View {
    @EnvironmentObject var model: AppModel
    @State private var poked: Set<Int> = []
    @State private var bag: MysteryBag?
    /// Nil until the player has guessed in this visit.
    @State private var guessedRight: Bool?
    @State private var jiggle = false
    /// A wrong guess from earlier in this visit, greyed out for the extra guess.
    @State private var ruledOut: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Mystery Bag")
            ScrollView {
                VStack(spacing: 18) {
                    stepsBar
                    if let bag {
                        if let right = guessedRight {
                            result(bag, right: right)
                        } else if model.progress.mystery.canPlay(today: model.today) {
                            play(bag)
                        } else {
                            comeBack
                        }
                    } else {
                        comeBack
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .onAppear { if bag == nil { bag = model.mysteryBag } }
    }

    private var stepsBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach(0..<MysteryBag.stepsPerCapsule, id: \.self) { i in
                    Capsule().fill(i < model.progress.mystery.steps ? Theme.bubblegum : Color.white)
                        .frame(width: 54, height: 14)
                        .overlay(Capsule().stroke(Theme.plum.opacity(0.2), lineWidth: 2))
                }
                Image(systemName: "gift.fill").foregroundStyle(Theme.grape)
            }
            Text("Three right guesses fill the bar for a free capsule.")
                .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
        }
    }

    private var comeBack: some View {
        VStack(spacing: 12) {
            bagShape.opacity(0.5)
            Text("Come back tomorrow for a new bag").font(Theme.body(18)).foregroundStyle(Theme.plum)
            if model.offersExtraMysteryGuess {
                Button { model.takeExtraMysteryGuess {} } label: {
                    Label("One more guess", systemImage: model.ownsRemoveAds ? "sparkles" : "play.rectangle.fill")
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.grape))
            }
        }
    }

    private var bagShape: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 40).fill(Theme.grape).frame(width: 190, height: 200)
            RoundedRectangle(cornerRadius: 40).stroke(Theme.plum, lineWidth: 5).frame(width: 190, height: 200)
            Capsule().fill(Theme.butter).frame(width: 120, height: 18).offset(y: -78)
            Text(verbatim: "?").font(Theme.title(80)).foregroundStyle(.white)
        }
        .rotationEffect(.degrees(jiggle ? 4 : 0))
    }

    private func play(_ bag: MysteryBag) -> some View {
        VStack(spacing: 16) {
            bagShape
            Text("Poke the bag, then guess who's inside!").font(Theme.body(17)).foregroundStyle(Theme.plum)
            HStack(spacing: 10) {
                pokeButton(0, "Shape", "hand.point.up.left.fill")
                pokeButton(1, "Squeak", "speaker.wave.2.fill")
                pokeButton(2, "Peek", "eye.fill")
            }
            HStack(alignment: .top, spacing: 12) {
                if poked.contains(0) {
                    clue("Shape") {
                        SquishyView(id: bag.answer.id, silhouette: true).frame(width: 84, height: 84).blur(radius: 5)
                    }
                }
                if poked.contains(1) {
                    clue("Squeak") {
                        VStack(spacing: 2) {
                            Image(systemName: "speaker.wave.2.fill").font(.system(size: 26))
                            Text(squeakText(bag.squeak)).font(Theme.body(14))
                        }
                        .foregroundStyle(Theme.plum).frame(width: 84, height: 84)
                    }
                }
                if poked.contains(2) {
                    clue("Peek") {
                        SquishyView(id: bag.answer.id).frame(width: 150, height: 150)
                            .mask(Circle().frame(width: 34, height: 34))
                            .frame(width: 84, height: 84)
                            .background(Circle().stroke(Theme.plum.opacity(0.3), lineWidth: 2).frame(width: 38, height: 38))
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(bag.choices) { choice in
                    Button { guess(choice) } label: {
                        VStack(spacing: 4) {
                            SquishyView(id: choice.id, rarity: choice.rarity).frame(width: 84, height: 84)
                            Text(verbatim: choice.name(in: model.language)).font(Theme.body(14)).foregroundStyle(Theme.plum).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 20).fill(.white))
                    }
                    .buttonStyle(.plain)
                    .disabled(choice.id == ruledOut)
                    .opacity(choice.id == ruledOut ? 0.35 : 1)
                    .accessibilityIdentifier("guess-\(choice.id)")
                }
            }
        }
    }

    private func result(_ bag: MysteryBag, right: Bool) -> some View {
        VStack(spacing: 14) {
            if right || !model.offersExtraMysteryGuess {
                SquishyView(id: bag.answer.id, rarity: bag.answer.rarity).frame(width: 190, height: 190)
            } else {
                bagShape
            }
            Text(right ? LocalizedStringKey("Yes! You got it!") : LocalizedStringKey("So close!")).font(Theme.title(28)).foregroundStyle(Theme.plum)
            Label("+\(model.config.coins.mysteryGuess)", systemImage: "circle.hexagongrid.fill")
                .font(Theme.body(17)).foregroundStyle(Theme.plum)
            if !right && model.offersExtraMysteryGuess {
                // The answer stays hidden while one more guess is on offer.
                Button {
                    model.takeExtraMysteryGuess { withAnimation { guessedRight = nil } }
                } label: {
                    Label("One more guess", systemImage: model.ownsRemoveAds ? "sparkles" : "play.rectangle.fill")
                }
                .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                // Nothing watched or bought ever leads to a capsule.
                Text("An extra guess wins coins. It doesn't fill the capsule bar.")
                    .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.6)).multilineTextAlignment(.center)
            } else {
                Text("It was \(bag.answer.name(in: model.language)).").font(Theme.body(18)).foregroundStyle(Theme.plum)
            }
            Text("Come back tomorrow for a new bag").font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.6))
        }
    }

    private func pokeButton(_ index: Int, _ title: LocalizedStringKey, _ icon: String) -> some View {
        Button {
            model.haptics.land()
            model.sounds.play("mystery_poke")
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { _ = poked.insert(index) }
            withAnimation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true)) { jiggle.toggle() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { jiggle = false }
        } label: {
            Label(title, systemImage: icon).font(Theme.body(14))
        }
        .buttonStyle(SquishButtonStyle(fill: poked.contains(index) ? Theme.mint : .white, text: Theme.plum))
    }

    private func clue<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 4) {
            content()
            Text(title).font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.6))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.7)))
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }

    private func squeakText(_ squeak: MysteryBag.Squeak) -> LocalizedStringKey {
        switch squeak {
        case .high: return "High squeak"
        case .middle: return "Middle squeak"
        case .low: return "Low squeak"
        }
    }

    private func guess(_ choice: Collectible) {
        guard guessedRight == nil else { return }
        let right = model.guessMystery(choice.id)
        if right { model.haptics.win() } else { model.haptics.reject(); ruledOut = choice.id }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { guessedRight = right }
    }
}
