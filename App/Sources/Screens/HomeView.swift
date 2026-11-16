import SwiftUI
import SquishPolicy

/// Home (Jelly pop, Ian 16 Nov): the wobbling logo, the Buddy, one big button straight into
/// the next level, then the Collection and the Mystery Bag. Nothing here pops up by itself.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var wobble = false
    @State private var showStamps = false
    @State private var coinsFlying = false
    @State private var coinsLanded = false

    var body: some View {
        GeometryReader { screen in
            // Small phones get a smaller logo and shorter buttons, so the Buddy keeps its room.
            let compact = screen.size.height < 720
            VStack(spacing: compact ? 6 : 10) {
                HStack {
                    // The coins pill opens the shop (under-13s reach it only from Settings).
                    Button { if !model.isGentleMode { model.screen = .shop } } label: {
                        Label { Text("\(model.progress.wallet.balance)") } icon: { CoinIcon() }
                            .font(Theme.body(17)).foregroundStyle(Theme.plum)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(model.progress.wallet.balance)))
                            .animation(.easeOut(duration: 0.9), value: model.progress.wallet.balance)
                            .scaleEffect(coinsLanded && coinsFlying ? 1.12 : 1)
                            .padding(.horizontal, 14).frame(height: 44)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home-coins")
                    Spacer()
                    IconButton(system: "gearshape.fill") { model.screen = .settings }
                }
                JellyLogo(scale: compact ? 0.42 : 0.56)
                if model.adventDoors > 0 { AdventShelf() }
                Spacer(minLength: 0)
                if model.isExtraUnlocked(.buddy) {
                    BuddyHomeView()
                } else {
                    SquishyView(id: model.progress.favouriteSquishy ?? "peach-bun", rarity: .rare)
                        .frame(width: 170, height: 170)
                }
                Spacer(minLength: 0)
                playButton(height: compact ? 72 : 90)
                HStack(spacing: 12) {
                    collectionButton(height: compact ? 78 : 100)
                    mysteryButton(height: compact ? 78 : 100)
                }
                places
                capsuleBar
            }
            .padding(16)
        }
        .background(
            LinearGradient(stops: [.init(color: Color(hex: 0xFFE1EE), location: 0), .init(color: Color(hex: 0xFFF0F4), location: 0.48),
                                   .init(color: Color(hex: 0xFFF6EA), location: 1)], startPoint: .top, endPoint: .bottom)
                .overlay { bubbles }
                .ignoresSafeArea()
        )
        .overlay {
            // Coins from the daily gift fly up to the coin counter.
            GeometryReader { geo in
                if coinsFlying {
                    ForEach(0..<10, id: \.self) { i in
                        CoinIcon()
                            .font(.system(size: 22)).foregroundStyle(Theme.butter)
                            .shadow(color: Theme.plum.opacity(0.6), radius: 1)
                            .position(coinsLanded
                                ? CGPoint(x: 50, y: 34)
                                : CGPoint(x: geo.size.width * 0.5 + CGFloat((i * 37) % 120 - 60),
                                          y: geo.size.height * 0.62 + CGFloat((i * 53) % 70 - 35)))
                            .opacity(coinsLanded ? 0 : 1)
                            .animation(.easeIn(duration: 0.5).delay(0.15 + Double(i) * 0.05), value: coinsLanded)
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .onChange(of: model.giftsOpened) { _, _ in
            coinsLanded = false
            coinsFlying = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { coinsLanded = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { coinsFlying = false; coinsLanded = false }
        }
        .onAppear {
            model.homeAppeared()
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { wobble = true }
        }
    }

    /// A few soft bubbles in the background.
    private var bubbles: some View {
        GeometryReader { geo in
            ForEach(0..<7, id: \.self) { i in
                let d = CGFloat(40 + (i * 37) % 70)
                Circle().fill(Color.white.opacity(0.35))
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1.5))
                    .frame(width: d, height: d)
                    .position(x: geo.size.width * CGFloat((i * 53) % 100) / 100, y: geo.size.height * CGFloat((i * 29 + 11) % 100) / 100)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The main button: straight into the level to play next.
    private func playButton(height: CGFloat) -> some View {
        let index = model.progress.highestUnlocked
        return Button { model.screen = .level(index) } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill").font(.system(size: height * 0.3, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xEE4689))
                    .frame(width: height * 0.62, height: height * 0.62)
                    .background(Circle().fill(.white))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Level \(model.levelNumber(index))").font(Theme.title(height * 0.34)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if model.levels.indices.contains(index) {
                        Text(AppModel.worldName(model.levels[index].file.world)).font(Theme.body(13))
                            .foregroundStyle(Color(hex: 0xEE4689))
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(Capsule().fill(.white))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity).frame(height: height)
        }
        .buttonStyle(JellyButtonStyle(colors: [Color(hex: 0xFF8DBD), Color(hex: 0xFF5C9D), Color(hex: 0xEE4689)], rim: Color(hex: 0xC7306F)))
        .accessibilityIdentifier("home-play")
    }

    /// The collection book: a little shelf of squishies and how many are found.
    private func collectionButton(height: CGFloat) -> some View {
        let owned = model.roster.collectibles.filter { model.progress.collection.owns($0.id) }
        let show = Array(owned.suffix(3))
        return Button { model.screen = .book } label: {
            VStack(spacing: 3) {
                HStack(spacing: -4) {
                    ForEach(show.isEmpty ? [] : show, id: \.id) { c in
                        SquishyView(id: c.id, rarity: c.rarity).frame(width: height * 0.36, height: height * 0.36)
                    }
                    if show.isEmpty {
                        Image(systemName: "square.grid.3x3.fill").font(.system(size: height * 0.28, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(height: height * 0.36)
                .background(alignment: .bottom) { Capsule().fill(Color.white.opacity(0.7)).frame(height: 5).offset(y: 3) }
                Text("Collection").font(Theme.title(17)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text("\(owned.count) of \(model.roster.collectibles.count)").font(Theme.body(12)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity).frame(height: height)
        }
        .buttonStyle(JellyButtonStyle(colors: [Color(hex: 0xA9DCFF), Color(hex: 0x63B6F5), Color(hex: 0x4C9FE6)], rim: Color(hex: 0x2F7FC4), radius: 26))
        .accessibilityIdentifier("home-collection")
    }

    /// The Mystery Bag: a bag with a big question mark. Before it opens, it says when it will.
    private func mysteryButton(height: CGFloat) -> some View {
        let open = model.isExtraUnlocked(.mysteryBag)
        let ready = open && model.progress.mystery.canPlay(today: model.today)
        return Button { if open { model.open(.mysteryBag) } } label: {
            VStack(spacing: 3) {
                Text(verbatim: "?").font(Theme.title(height * 0.24)).foregroundStyle(.white)
                    .frame(width: height * 0.34, height: height * 0.36)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x7646DE)))
                    .overlay(alignment: .top) { Capsule().fill(Theme.butter).frame(width: height * 0.2, height: 4).offset(y: 3) }
                    // The bag wiggles while today's bag is unopened.
                    .rotationEffect(.degrees(ready && wobble ? 7 : (ready ? -7 : 0)))
                    .overlay(alignment: .topTrailing) { if model.isNew(.mysteryBag) { NewBadge().offset(x: 16, y: -8) } }
                Text("Mystery Bag").font(Theme.title(17)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Group {
                    if !open {
                        Label("After level \(Extras.mysteryBagAfterLevel)", systemImage: "lock.fill")
                    } else if ready {
                        Text("Ready to open!")
                    } else {
                        Text("Back tomorrow")
                    }
                }
                .font(Theme.body(12)).foregroundStyle(.white.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity).frame(height: height)
        }
        .buttonStyle(JellyButtonStyle(colors: [Color(hex: 0xD7C4FF), Color(hex: 0xA985FA), Color(hex: 0x9570EE)], rim: Color(hex: 0x6E42D8), radius: 26))
        .opacity(open ? 1 : 0.75)
        .accessibilityIdentifier("home-mystery")
    }

    /// The smaller places: the level map, and the ones that open later.
    private var places: some View {
        HStack(spacing: 8) {
            place("Levels", "circle.grid.3x3.fill") { model.screen = .map }
            if model.isExtraUnlocked(.squishRoom) {
                place("Squish Room", "hand.tap.fill", extra: .squishRoom) { model.open(.squishRoom) }
            }
            if model.isExtraUnlocked(.maker) {
                place("Maker", "paintbrush.fill", extra: .maker) { model.open(.maker) }
            }
            // The festive door: a side world. No countdown anywhere.
            if model.showsFestiveDoor {
                place(AppModel.christmasWorldName, "door.left.hand.closed") { model.openFestiveDoor() }
                    .accessibilityIdentifier("festive-door")
            }
        }
    }

    private func place(_ title: LocalizedStringKey, _ icon: String, extra: Extra? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(Theme.body(13)).foregroundStyle(Theme.plum)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 40)
                .background(Capsule().fill(.white))
                .overlay(alignment: .topTrailing) { if let extra, model.isNew(extra) { NewBadge().offset(x: 4, y: -8) } }
        }
        .buttonStyle(PressSquish())
    }

    private var ownedCount: Int {
        model.roster.collectibles.filter { model.progress.collection.owns($0.id) }.count
    }

    /// How close the next capsule is, under Play.
    @ViewBuilder private var capsuleBar: some View {
        if let before = model.levelsToNextCapsule(after: model.progress.highestUnlocked - 1) {
            let toGo = before + 1
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i < 3 - toGo ? Theme.grape : Color.white)
                        .frame(width: 26, height: 9)
                        .overlay(Capsule().stroke(Theme.plum.opacity(0.25), lineWidth: 1.5))
                }
                if toGo == 1 {
                    Text("1 more level to a capsule")
                } else {
                    Text("\(toGo) more levels to a capsule")
                }
            }
            .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.75))
        }
        // The stamp card: one stamp for the first win of each day, once level 3 is won.
        // Nothing is lost on a missed day. Tap to see the seven rewards.
        Button { showStamps = true } label: {
            HStack(spacing: 5) {
                ForEach(0..<StampCard.size, id: \.self) { i in
                    Image(systemName: i < model.progress.stampCard.stamps ? "seal.fill" : "circle.dotted")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(i < model.progress.stampCard.stamps ? Theme.bubblegum : Theme.plum.opacity(0.3))
                }
                Text("Stamp card").font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stamp-card")
        .sheet(isPresented: $showStamps) {
            VStack(spacing: 14) {
                Text("Stamp card").font(Theme.title(26)).foregroundStyle(Theme.plum)
                Text("Your first win each day earns a stamp.").font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                    ForEach(1...StampCard.size, id: \.self) { n in
                        let done = n <= model.progress.stampCard.stamps
                        VStack(spacing: 4) {
                            Image(systemName: done ? "seal.fill" : "circle.dotted")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(done ? Theme.bubblegum : Theme.plum.opacity(0.3))
                            switch model.stampReward(n) {
                            case .coins(let amount):
                                Label { Text("\(amount)") } icon: { CoinIcon() }.font(Theme.body(13))
                            case .capsuleStep:
                                Image(systemName: "gift.fill").font(.system(size: 14, weight: .bold))
                            }
                        }
                        .foregroundStyle(Theme.plum)
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.marshmallow.ignoresSafeArea())
            .presentationDetents([.medium])
        }
    }

    /// One object in the scene: a picture with its name under it, and a "new!" tag until first opened.
}

/// 24 little doors, 1 to 24 December. Every door up to today can be opened once,
/// so missed days are caught up. Fixed rewards, no ad, no streak.
struct AdventShelf: View {
    @EnvironmentObject var model: AppModel
    @State private var said: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 6) {
            if let said {
                Text(said).font(Theme.body(14)).foregroundStyle(Theme.plum)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(1...Advent.doors, id: \.self) { day in door(day).id(day) }
                    }
                    .padding(.horizontal, 4).padding(.vertical, 4)
                }
                .onAppear {
                    // Start at the first door that can still be opened.
                    if let first = (1...Advent.doors).first(where: { canOpen($0) }) { proxy.scrollTo(first, anchor: .leading) }
                }
            }
        }
        .accessibilityIdentifier("advent-shelf")
    }

    private func canOpen(_ day: Int) -> Bool {
        day <= model.adventDoors && !model.adventOpened.contains(day)
    }

    private func door(_ day: Int) -> some View {
        let opened = model.adventOpened.contains(day)
        let ready = canOpen(day)
        return Button {
            guard let reward = model.openAdventDoor(day) else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { said = text(for: reward) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(opened ? Color.white.opacity(0.5) : (ready ? Theme.bubblegum : Theme.mint.opacity(0.6)))
                if opened {
                    Image(systemName: "checkmark").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.plum.opacity(0.4))
                } else {
                    Text(verbatim: "\(day)").font(Theme.title(18)).foregroundStyle(ready ? .white : Theme.plum.opacity(0.5))
                }
            }
            .frame(width: 44, height: 52)
            .scaleEffect(ready ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .accessibilityLabel(Text("Door \(day)"))
    }

    private func text(for reward: Advent.Reward) -> LocalizedStringKey {
        switch reward {
        case .coins(let amount): return "+\(amount) coins!"
        case .treats(let count): return "\(count) treats for your Buddy!"
        case .capsuleStep: return "One step closer to a capsule!"
        case .christmasCapsule: return "A Christmas capsule!"
        }
    }
}

struct NewBadge: View {
    var body: some View {
        Text("new!").font(Theme.body(11)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Theme.bubblegum))
    }
}

/// The Buddy on the home screen: says hello, reacts to pokes, eats treats.
/// It never gets hungry, sick or sad.
struct BuddyHomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var picking = false
    @State private var pokes = 0
    @State private var confirmTreat = false
    @State private var feeding = false
    @State private var flying = "🧁"
    @State private var burst = false
    @State private var burstShown = false
    @State private var heartUp = false
    @State private var spin = 0.0
    @State private var flip = 0.0
    @State private var sway: CGFloat = 0
    @State private var trickTurn = 0
    @State private var giftWobble = false
    @State private var talking = false
    /// The trick chip a bouncing hand points at (a trick just learned).
    @State private var pointAt: Int?
    @State private var handBounce = false

    /// One chip per trick. A learned one plays its trick; a locked one shows the hearts still needed.
    /// A bouncing hand points at a trick that has just been learned until it is tapped once.
    private var trickChips: some View {
        let buddy = model.progress.buddy
        let names: [LocalizedStringKey] = ["Spin", "Flip", "Dance"]
        let icons = ["arrow.triangle.2.circlepath", "arrow.up.and.down.circle.fill", "music.note"]
        return HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { n in
                let learned = n <= buddy.tricksUnlocked
                Button {
                    if pointAt == n { pointAt = nil }
                    playTrick(n)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: learned ? icons[n - 1] : "lock.fill")
                        Text(names[n - 1])
                        if !learned {
                            Label { Text(verbatim: "\(max(1, n * BuddyState.heartsPerTrick - buddy.hearts))") } icon: { Image(systemName: "heart.fill") }
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(Theme.body(13)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(Theme.plum.opacity(learned ? 1 : 0.5))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(learned ? Theme.mint : Color.white.opacity(0.5)))
                    .overlay(Capsule().stroke(pointAt == n ? Theme.bubblegum : Theme.plum.opacity(0.15), lineWidth: pointAt == n ? 3 : 2))
                }
                .buttonStyle(PressSquish())
                .disabled(!learned)
                .accessibilityIdentifier("trick-\(n)")
                .overlay(alignment: .bottom) {
                    if pointAt == n {
                        Text(verbatim: "👆").font(.system(size: 34))
                            .offset(y: handBounce ? 34 : 44)
                            .allowsHitTesting(false)
                            .onAppear {
                                handBounce = false
                                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { handBounce = true }
                            }
                    }
                }
                .zIndex(pointAt == n ? 1 : 0)
            }
        }
    }

    private func showOffTrick() {
        guard let number = model.trickToShow else { return }
        model.trickToShow = nil
        pointAt = number
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            spin = 0; flip = 0; sway = 0
            playTrick(number)
            burstShown = true
            burst = false
            withAnimation(.easeOut(duration: 0.7)) { burst = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { burstShown = false; burst = false }
        }
    }

    /// Three little squashes, like a mouth moving.
    private func talk() {
        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22 * Double(i)) {
                withAnimation(.easeOut(duration: 0.09)) { talking = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { talking = false } }
            }
        }
    }

    private let moods: [(id: String, face: String, label: LocalizedStringKey)] = [
        ("happy", "😊", "Happy"), ("okay", "🙂", "Okay"), ("sleepy", "😴", "Sleepy"), ("grumpy", "😠", "Grumpy"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            if let ref = model.progress.buddy.squishy {
                if let says = model.buddySays {
                    // A comic bubble; the mood question and its faces sit in the same bubble.
                    BuddyBubble(text: says, kind: model.buddySaysKind,
                                asker: model.buddyAsksMood ? model.progress.buddy.name : nil, sounds: model.sounds) {
                        if model.buddyAsksMood {
                            HStack(spacing: 10) {
                                ForEach(Array(moods.enumerated()), id: \.element.id) { i, mood in
                                    Button { withAnimation { model.answerMood(mood.id) } } label: {
                                        Text(verbatim: mood.face).font(.system(size: 26))
                                            .frame(width: 46, height: 42)
                                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .fill([Theme.butter, Theme.mint, Theme.sky, Theme.bubblegum][i % 4].opacity(0.7)))
                                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(Theme.plum.opacity(0.5), lineWidth: 2))
                                    }
                                    .buttonStyle(PressSquish())
                                    .accessibilityLabel(Text(mood.label))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .onTapGesture { withAnimation { model.buddySays = nil } }
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                    // It fades by itself after about four seconds, unless it is waiting for an answer.
                    .task(id: says) {
                        talk()
                        guard !model.buddyAsksMood, !AppModel.isUITesting else { return }
                        try? await Task.sleep(nanoseconds: UInt64((2.5 + Double(says.count) * 0.06) * 1_000_000_000))
                        if !Task.isCancelled, model.buddySays == says, !model.buddyAsksMood {
                            withAnimation { model.buddySays = nil }
                        }
                    }
                }
                // The Buddy is as soft as in the Squish Room: knead, pull, pinch, pick up and throw.
                SoftSquishy(toy: ref, look: ref, feel: model.feel(for: ref), mode: .room, pokes: pokes,
                            onTouch: { withAnimation { model.pokeBuddy() } }, onDoubleTap: { playTrick() }) {
                    SquishRefView(ref: ref)
                }
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 340)
                // Tricks: spin, flip and dance. Then the little growth from hearts, which never goes back.
                .rotationEffect(.degrees(spin))
                .modifier(FlipEffect(turn: flip))
                .offset(x: sway)
                // It squashes a little as it talks.
                .scaleEffect(x: talking ? 1.04 : 1, y: talking ? 0.94 : 1, anchor: .bottom)
                .scaleEffect(1 + buddySize, anchor: .bottom)
                .padding(.top, 60 * buddySize)
                .animation(.spring(response: 0.5, dampingFraction: 0.5), value: model.progress.buddy.lastTreatAt)
                .overlay {
                    // A treat flies up to the Buddy, and a heart floats off it.
                    if feeding {
                        Text(verbatim: flying).font(.system(size: flying == "🎁" ? 44 : 34))
                            .transition(.asymmetric(insertion: .offset(x: -70, y: 150).combined(with: .opacity),
                                                    removal: .scale(scale: 0.1).combined(with: .opacity)))
                    }
                    // A gift opens in a burst of hearts.
                    ForEach(0..<8, id: \.self) { i in
                        let angle = Double(i) / 8 * 2 * Double.pi
                        Image(systemName: "heart.fill").font(.system(size: 20)).foregroundStyle(Theme.bubblegum)
                            .offset(x: burst ? CGFloat(cos(angle)) * 110 : 0, y: burst ? CGFloat(sin(angle)) * 110 - 20 : 0)
                            .scaleEffect(burst ? 1.2 : 0.2)
                            .opacity(burstShown ? (burst ? 0 : 1) : 0)
                    }
                    if heartUp {
                        Image(systemName: "heart.fill").font(.system(size: 26)).foregroundStyle(Theme.bubblegum)
                            .transition(.asymmetric(insertion: .scale(scale: 0.3).combined(with: .opacity),
                                                    removal: .offset(x: 50, y: -120).combined(with: .opacity)))
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    // The daily gift sits by the Buddy and wobbles until it is opened, then bursts.
                    if model.dailyGiftWaiting {
                        Text(verbatim: "🎁").font(.system(size: 46))
                            .rotationEffect(.degrees(giftWobble ? 9 : -9), anchor: .bottom)
                            .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: giftWobble)
                            .offset(x: -18, y: -8)
                            .onAppear { giftWobble = true }
                            .onDisappear { giftWobble = false }
                            .onTapGesture { model.takeDailyGift() }
                            .transition(.asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity),
                                                    removal: .scale(scale: 2.2).combined(with: .opacity)))
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: model.progress.buddy.name))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { poke() }
                .accessibilityIdentifier("buddy")
                HStack(spacing: 8) {
                    Text(verbatim: model.progress.buddy.name).font(Theme.title(22))
                    // The heart ring fills towards the next trick.
                    ZStack {
                        Circle().stroke(Theme.bubblegum.opacity(0.2), lineWidth: 4)
                        Circle().trim(from: 0, to: model.progress.buddy.trickProgress)
                            .stroke(Theme.bubblegum, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(Theme.bubblegum)
                    }
                    .frame(width: 30, height: 30)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: model.progress.buddy.hearts)
                    Text(verbatim: "\(model.progress.buddy.hearts)").font(Theme.body(15)).foregroundStyle(Theme.bubblegum)
                }
                .foregroundStyle(Theme.plum)
                if let toGo = model.progress.buddy.heartsToNextTrick {
                    Text("\(toGo) more hearts to the next trick").font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.6))
                } else {
                    Text("Double tap for a trick!").font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.6))
                }
                if model.dailyGiftReady {
                    // The Buddy's daily gift: coins by opt-in ad, or free in gentle mode.
                    Button { model.takeDailyGift(); squish() } label: {
                        Label("Open gift: \(model.config.coins.dailyGift) coins",
                              systemImage: model.dailyGiftNeedsVideo ? "play.rectangle.fill" : "gift.fill")
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .accessibilityIdentifier("daily-gift")
                } else if model.dailyGiftWaiting {
                    // The box is here but no video has loaded: say so rather than do nothing.
                    Label("No video right now", systemImage: "gift.fill")
                        .font(Theme.body(14)).foregroundStyle(Theme.plum.opacity(0.6))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.7)))
                }
                trickChips
                HStack(spacing: 10) {
                    if model.progress.buddy.treats > 0 {
                        Button { feed { model.feedBuddy() } } label: {
                            Label("Treat ×\(model.progress.buddy.treats)", systemImage: "birthday.cake.fill")
                        }
                        .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                    } else if !model.isGentleMode && model.progress.wallet.canAfford(.treat) {
                        // Out of free treats: one more for coins, given straight away.
                        // Two taps, so a poke meant for the Buddy never spends coins.
                        Button {
                            if confirmTreat {
                                confirmTreat = false
                                feed { model.buyForBuddy(.treat) }
                            } else {
                                withAnimation { confirmTreat = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { confirmTreat = false } }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "birthday.cake.fill")
                                Text(confirmTreat ? LocalizedStringKey("Tap again") : LocalizedStringKey("Treat"))
                                Label { Text("\(Coins.Item.treat.price)") } icon: { CoinIcon() }.font(Theme.body(14))
                            }
                        }
                        .buttonStyle(SquishButtonStyle(fill: confirmTreat ? Theme.mint : Theme.butter, text: Theme.plum))
                        .accessibilityIdentifier("buy-treat")
                    } else {
                        // No treats and no coins: say where treats come from.
                        Button {
                            withAnimation { model.buddySays = String(localized: "Win a level and I get a treat!") }
                        } label: { Label("Get treats", systemImage: "birthday.cake.fill") }
                        .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                        .accessibilityIdentifier("get-treats")
                    }
                    Button { picking = true } label: {
                        Label("Change Buddy", systemImage: "arrow.left.arrow.right").font(Theme.body(14))
                    }
                    .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                }
            } else {
                Text(verbatim: "Squish Sort").font(Theme.title(40)).foregroundStyle(Theme.plum)
                Button { picking = true } label: { Label("Choose your Buddy", systemImage: "heart.fill") }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .overlay(alignment: .topTrailing) { if model.isNew(.buddy) { NewBadge().offset(x: 10, y: -10) } }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.buddySays)
        // A trick just learned is shown off at once, with a burst of hearts.
        .onChange(of: model.trickToShow) { _, _ in showOffTrick() }
        .onAppear { showOffTrick() }
        // Something bought in the shop arrives here, so the Buddy is seen enjoying it.
        .onAppear {
            guard let item = model.buddyDelivery else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                feed(gift: item == .gift) { model.deliverToBuddy() }
            }
        }
        .sheet(isPresented: $picking) {
            BuddyPickerView { picking = false }.environmentObject(model)
        }
    }

    private func poke() {
        withAnimation { model.pokeBuddy() }
        squish()
    }

    private func squish() {
        pokes += 1
    }

    /// Growth earned for good, plus the puff from a recent treat.
    private var buddySize: Double {
        model.progress.buddy.growth + model.progress.buddy.puff(at: Date().timeIntervalSince1970, lasting: model.puffSeconds)
    }

    /// The treat flies in, the Buddy chomps twice, then a heart floats up.
    private func feed(gift: Bool = false, _ give: @escaping () -> Void) {
        guard !feeding else { return }
        flying = gift ? "🎁" : "🧁"
        withAnimation(.easeOut(duration: 0.3)) { feeding = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeIn(duration: 0.15)) { feeding = false }
            squish()
            withAnimation { give() }
            if gift {
                burst = false
                burstShown = true
                withAnimation(.easeOut(duration: 0.8)) { burst = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { burstShown = false; burst = false }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            squish()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heartUp = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeIn(duration: 0.5)) { heartUp = false }
        }
    }

    /// A double tap plays a trick the Buddy knows: spin, flip or dance.
    /// Does trick `number` (1 spin, 2 flip, 3 dance), or the next one the Buddy knows.
    private func playTrick(_ number: Int? = nil) {
        let known = model.progress.buddy.tricksUnlocked
        guard known > 0, spin == 0, flip == 0, sway == 0 else { return }
        trickTurn += 1
        let which = number.map { min(max(1, $0), known) } ?? (trickTurn - 1) % known + 1
        model.sounds.play("trick", or: "buddy_giggle")
        model.haptics.complete()
        switch which {
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
}

/// Pick any owned or made squishy as the Buddy (and avatar), and name it.
/// The name stays on this device.
struct BuddyPickerView: View {
    @EnvironmentObject var model: AppModel
    let done: () -> Void
    @State private var ref: String?
    @State private var name = ""
    @State private var badName = false
    /// The name this sheet last put in the field itself. If the field still holds it, the player has not typed.
    @State private var filled = ""

    private var made: Set<String> { Set(model.progress.made.map(\.ref)) }
    private var choices: [String] {
        let all = model.squeezables
        return all.filter { made.contains($0) } + all.filter { !made.contains($0) }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Choose your Buddy").font(Theme.title(24)).foregroundStyle(Theme.plum).padding(.top, 20)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(choices, id: \.self) { item in
                        SquishRefView(ref: item)
                            .frame(width: 68, height: 68)
                            .background(RoundedRectangle(cornerRadius: 16).fill(item == ref ? Theme.butter : Color.white))
                            .overlay(alignment: .topTrailing) {
                                // The ones you made yourself come first, with a paintbrush.
                                if made.contains(item) {
                                    Image(systemName: "paintbrush.fill").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white).padding(4)
                                        .background(Circle().fill(Theme.mint)).offset(x: 4, y: -4)
                                }
                            }
                            .onTapGesture {
                                ref = item
                                // Each squishy brings its own name, unless the player has typed one here.
                                if name.isEmpty || name == filled {
                                    name = String(model.displayName(for: item).prefix(NameFilter.maxLength))
                                    filled = name
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            TextField("Name", text: $name)
                .font(Theme.body(18))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding(.horizontal, 24)
                .onChange(of: name) { _, new in
                    if new.count > NameFilter.maxLength { name = String(new.prefix(NameFilter.maxLength)) }
                    badName = false
                }
            if badName {
                Text("Try another name").font(Theme.body(14)).foregroundStyle(Theme.bubblegum)
            }
            Button("Save") {
                guard let ref else { return }
                if model.setBuddy(ref: ref, name: name) { done() } else { badName = true }
            }
            .buttonStyle(SquishButtonStyle())
            .disabled(ref == nil)
            .opacity(ref == nil ? 0.5 : 1)
            .padding(.bottom, 16)
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .onAppear {
            ref = model.progress.buddy.squishy
            name = model.progress.buddy.name
            filled = name
        }
    }
}

/// The flip trick: a jump with a full head-over-heels turn. Drawn as a flat turn, so it works on
/// the soft squishy, which a 3D turn does not move. `turn` runs from 0 to 1.
struct FlipEffect: GeometryEffect {
    var turn: Double
    var animatableData: Double {
        get { turn }
        set { turn = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let angle = CGFloat(turn) * 2 * .pi
        let jump = -sin(CGFloat(turn) * .pi) * size.height * 0.35
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let t = CGAffineTransform(translationX: center.x, y: center.y + jump)
            .rotated(by: -angle)
            .translatedBy(x: -center.x, y: -center.y)
        return ProjectionTransform(t)
    }
}
