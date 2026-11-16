import SwiftUI
import SquishPolicy
import SquishSoft

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
    /// Shape clue: the bag pulls tight round the toy for two seconds.
    @State private var tight = false
    /// Goes up by one for every squeak, so the sound rings play again.
    @State private var squeaks = 0
    @State private var lastTouch = Date.distantPast

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
            // The bag itself can be poked: each poke gives the next clue.
            softBag(bag)
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
                        // Heard, not read: tap it to hear the squeak again.
                        Button { poke(1) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "speaker.wave.2.fill").font(.system(size: 26))
                                Text("Squeak!").font(Theme.body(13))
                            }
                            .foregroundStyle(Theme.plum).frame(width: 84, height: 84)
                        }
                        .buttonStyle(PressSquish())
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
            Label { Text("+\(model.config.coins.mysteryGuess)") } icon: { CoinIcon() }
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

    private var bagLook: String { tight ? "tight" : (poked.contains(2) ? "peek" : "loose") }

    /// The bag is a soft body: poke it, squeeze it, and it gives like mochi.
    private func softBag(_ bag: MysteryBag) -> some View {
        SoftSquishy(toy: "mystery-bag-\(bag.answer.id)", look: bagLook, feel: SquishFeel(named: "mochi"),
                    onTouch: { touchedBag() }) {
            bagArt(bag)
        }
        .frame(width: 230, height: 230)
        .overlay {
            if squeaks > 0 { SqueakRings(squeak: bag.squeak).id(squeaks).allowsHitTesting(false) }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Mystery Bag"))
        .accessibilityAction { touchedBag() }
        .accessibilityIdentifier("mystery-bag")
    }

    /// What the bag looks like: loose, pulled tight round the toy, or with a slit that shows one colour.
    @ViewBuilder private func bagArt(_ bag: MysteryBag) -> some View {
        ZStack {
            if tight {
                Theme.grape.mask(SquishyView(id: bag.answer.id, silhouette: true).frame(width: 250, height: 250))
                    .frame(width: 250, height: 250)
            } else {
                RoundedRectangle(cornerRadius: 56).fill(Theme.grape).frame(width: 240, height: 250)
                RoundedRectangle(cornerRadius: 56).stroke(Theme.plum, lineWidth: 6).frame(width: 240, height: 250)
                Text(verbatim: "?").font(Theme.title(96)).foregroundStyle(.white.opacity(poked.contains(2) ? 0.35 : 1))
            }
            Capsule().fill(Theme.butter).frame(width: 130, height: 22).offset(y: -104)
            if poked.contains(2), !tight {
                // The slit: one colour of the toy shows through.
                SquishyView(id: bag.answer.id).frame(width: 330, height: 330)
                    .mask(Capsule().frame(width: 96, height: 26))
                    .frame(width: 100, height: 30)
                    .background(Capsule().fill(Theme.plum).frame(width: 104, height: 34))
                    .offset(y: 30)
            }
        }
        .frame(width: 300, height: 300)
    }

    /// A touch on the bag itself always squishes and sounds, and gives the next clue if one is left.
    private func touchedBag() {
        guard Date().timeIntervalSince(lastTouch) > 0.7 else { return }
        lastTouch = Date()
        poke((0..<3).first { !poked.contains($0) })
    }

    private func pokeButton(_ index: Int, _ title: LocalizedStringKey, _ icon: String) -> some View {
        Button { poke(index) } label: {
            Label(title, systemImage: icon).font(Theme.body(14))
        }
        .buttonStyle(SquishButtonStyle(fill: poked.contains(index) ? Theme.mint : .white, text: Theme.plum))
    }

    /// A poke jiggles the bag and shows a clue (nil: all three are already out).
    private func poke(_ index: Int?) {
        model.haptics.land()
        // The squeak clue is heard as well as read: rarer squishies squeak lower.
        if index == 1, let bag {
            let squeak: String
            switch bag.squeak {
            case .high: squeak = "squeak_high"
            case .middle: squeak = "squeak_mid"
            case .low: squeak = "squeak_low"
            }
            model.sounds.play(squeak, or: "mystery_poke")
        } else {
            model.sounds.play("mystery_poke")
        }
        if index == 1 { squeaks += 1 }
        if index == 0 {
            // The bag pulls tight round the toy, then lets go.
            tight = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { tight = false }
        }
        if let index {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { _ = poked.insert(index) }
        }
        withAnimation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true)) { jiggle.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { jiggle = false }
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

    private func guess(_ choice: Collectible) {
        guard guessedRight == nil else { return }
        let right = model.guessMystery(choice.id)
        if right { model.haptics.win() } else { model.haptics.reject(); ruledOut = choice.id }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { guessedRight = right }
    }
}

/// Sound you can see: rings come off the bag when it squeaks. Small and quick for a high squeak,
/// big and slow for a low one, so the clue works with the sound off.
private struct SqueakRings: View {
    let squeak: MysteryBag.Squeak
    @State private var out = false

    private var reach: CGFloat {
        switch squeak {
        case .high: return 1.15
        case .middle: return 1.45
        case .low: return 1.8
        }
    }

    private var seconds: Double {
        switch squeak {
        case .high: return 0.35
        case .middle: return 0.6
        case .low: return 0.95
        }
    }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(Theme.bubblegum, lineWidth: 4)
                    .frame(width: 150, height: 150)
                    .scaleEffect(out ? reach : 0.7)
                    .opacity(out ? 0 : 0.9)
                    .animation(.easeOut(duration: seconds).delay(Double(i) * seconds * 0.35), value: out)
            }
        }
        .onAppear { out = true }
    }
}
