import SwiftUI
import SquishPolicy

/// Home is one scene, not a grid: a shelf at the top, the Buddy on a rug in the
/// middle, Play at the bottom. Objects are the buttons, and each appears when
/// its extra unlocks. Nothing here pops up by itself.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var wobble = false
    @State private var showStamps = false
    @State private var coinsFlying = false
    @State private var coinsLanded = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                // The coins pill opens the shop (under-13s reach it only from Settings).
                Button { if !model.isGentleMode { model.screen = .shop } } label: {
                    Label("\(model.progress.wallet.balance)", systemImage: "circle.hexagongrid.fill")
                        .font(Theme.body(17)).foregroundStyle(Theme.plum)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(model.progress.wallet.balance)))
                        .animation(.easeOut(duration: 0.9), value: model.progress.wallet.balance)
                        .scaleEffect(coinsLanded && coinsFlying ? 1.12 : 1)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-coins")
                Spacer()
                IconButton(system: "gearshape.fill") { model.screen = .settings }
            }
            Text(verbatim: "Squish Sort").font(Theme.title(30)).foregroundStyle(.white)
                .padding(.horizontal, 22).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.bubblegum))
                .rotationEffect(.degrees(-2))
            if model.adventDoors > 0 { AdventShelf() }
            shelf
            Spacer(minLength: 0)
            if model.isExtraUnlocked(.buddy) {
                BuddyHomeView()
            } else {
                SquishyView(id: model.progress.favouriteSquishy ?? "peach-bun", rarity: .rare)
                    .frame(width: 170, height: 170)
            }
            Spacer(minLength: 0)
            Button { model.screen = .level(model.progress.highestUnlocked) } label: {
                VStack(spacing: 2) {
                    Text("Play").font(Theme.title(30))
                    Text("Level \(model.levelNumber(model.progress.highestUnlocked))").font(Theme.body(15)).opacity(0.85)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityIdentifier("home-play")
            capsuleBar
        }
        .padding(16)
        .background(Theme.marshmallow.ignoresSafeArea())
        .overlay {
            // Coins from the daily gift fly up to the coin counter.
            GeometryReader { geo in
                if coinsFlying {
                    ForEach(0..<10, id: \.self) { i in
                        Image(systemName: "circle.hexagongrid.fill")
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

    /// The shelf, left to right: the book, the capsule machine (the level map) and the Mystery Bag.
    private var shelf: some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom) {
                object("Book \(ownedCount)/\(model.roster.collectibles.count)", "book.closed.fill", Color(red: 0.49, green: 0.78, blue: 1)) {
                    model.screen = .book
                }
                Spacer()
                object("Levels", "circle.hexagongrid.circle.fill", Theme.bubblegum, tint: .white) { model.screen = .map }
                Spacer()
                if model.isExtraUnlocked(.mysteryBag) {
                    object("Mystery Bag", "bag.fill", Theme.grape, tint: .white, extra: .mysteryBag) { model.open(.mysteryBag) }
                        // The bag wiggles while today's bag is unopened.
                        .rotationEffect(.degrees(model.progress.mystery.canPlay(today: model.today) && wobble ? 5 : 0))
                } else {
                    Color.clear.frame(width: 76, height: 1)
                }
            }
            .padding(.horizontal, 8)
            .background(alignment: .bottom) { plank }
            // A second shelf for the places that open later, so nothing floats beside the Buddy.
            if model.isExtraUnlocked(.squishRoom) || model.isExtraUnlocked(.maker) || model.showsFestiveDoor {
                HStack(alignment: .bottom, spacing: 18) {
                    if model.isExtraUnlocked(.squishRoom) {
                        object("Squish Room", "hand.tap.fill", Theme.bubblegum.opacity(0.35), extra: .squishRoom) { model.open(.squishRoom) }
                    }
                    if model.isExtraUnlocked(.maker) {
                        object("Maker", "paintbrush.fill", Theme.mint, extra: .maker) { model.open(.maker) }
                    }
                    // The festive door: a side world. No countdown anywhere.
                    if model.showsFestiveDoor {
                        object(AppModel.christmasWorldName, "door.left.hand.closed", Color(red: 0.9, green: 0.25, blue: 0.3),
                               tint: .white) { model.openFestiveDoor() }
                            .accessibilityIdentifier("festive-door")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .background(alignment: .bottom) { plank }
            }
        }
    }

    private var plank: some View {
        Capsule().fill(Color(red: 0.87, green: 0.72, blue: 0.53)).frame(height: 10).offset(y: -22)
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
                                Label("\(amount)", systemImage: "circle.hexagongrid.fill").font(Theme.body(13))
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
    private func object(_ title: LocalizedStringKey, _ icon: String, _ fill: Color, tint: Color = Theme.plum,
                        extra: Extra? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 26, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: 18).fill(fill))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.plum, lineWidth: 3))
                    .overlay(alignment: .topTrailing) {
                        if let extra, model.isNew(extra) { NewBadge().offset(x: 12, y: -10) }
                    }
                Text(title).font(Theme.body(12)).foregroundStyle(Theme.plum)
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }
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
    @State private var heartUp = false
    @State private var spin = 0.0
    @State private var flip = 0.0
    @State private var sway: CGFloat = 0
    @State private var trickTurn = 0
    @State private var giftWobble = false

    private let moods: [(id: String, face: String, label: LocalizedStringKey)] = [
        ("happy", "😊", "Happy"), ("okay", "🙂", "Okay"), ("sleepy", "😴", "Sleepy"), ("grumpy", "😠", "Grumpy"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            if let ref = model.progress.buddy.squishy {
                if let says = model.buddySays {
                    SpeechBubble(text: says).transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                if model.buddyAsksMood {
                    HStack(spacing: 12) {
                        ForEach(moods, id: \.id) { mood in
                            Button { withAnimation { model.answerMood(mood.id) } } label: {
                                Text(verbatim: mood.face).font(.system(size: 30))
                                    .frame(width: 52, height: 52)
                                    .background(Circle().fill(.white))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(mood.label))
                        }
                    }
                }
                // Poke and squeeze only, no throwing.
                SoftSquishy(toy: ref, look: ref, feel: model.feel(for: ref), pokes: pokes,
                            onTouch: { withAnimation { model.pokeBuddy() } }, onDoubleTap: { playTrick() }) {
                    SquishRefView(ref: ref)
                }
                .frame(width: 170, height: 170)
                // Tricks: spin, flip and dance. Then the little growth from hearts, which never goes back.
                .rotationEffect(.degrees(spin))
                .rotation3DEffect(.degrees(flip), axis: (x: 1, y: 0, z: 0))
                .offset(x: sway)
                .scaleEffect(1 + model.progress.buddy.growth, anchor: .bottom)
                .padding(.top, 170 * model.progress.buddy.growth)
                .overlay {
                    // A treat flies up to the Buddy, and a heart floats off it.
                    if feeding {
                        Text(verbatim: "🧁").font(.system(size: 34))
                            .transition(.asymmetric(insertion: .offset(x: -70, y: 150).combined(with: .opacity),
                                                    removal: .scale(scale: 0.1).combined(with: .opacity)))
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
                            .offset(x: 34, y: 6)
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
                                Label("\(Coins.Item.treat.price)", systemImage: "circle.hexagongrid.fill").font(Theme.body(14))
                            }
                        }
                        .buttonStyle(SquishButtonStyle(fill: confirmTreat ? Theme.mint : Theme.butter, text: Theme.plum))
                        .accessibilityIdentifier("buy-treat")
                    } else {
                        // No treats and no coins: say where treats come from.
                        Label("Win a level for a treat", systemImage: "birthday.cake.fill")
                            .font(Theme.body(14)).foregroundStyle(Theme.plum.opacity(0.6))
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

    /// The treat flies in, the Buddy chomps twice, then a heart floats up.
    private func feed(_ give: @escaping () -> Void) {
        guard !feeding else { return }
        withAnimation(.easeOut(duration: 0.3)) { feeding = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeIn(duration: 0.15)) { feeding = false }
            squish()
            withAnimation { give() }
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
    private func playTrick() {
        let known = model.progress.buddy.tricksUnlocked
        guard known > 0, spin == 0, flip == 0, sway == 0 else { return }
        trickTurn += 1
        model.sounds.play("trick", or: "buddy_giggle")
        model.haptics.complete()
        switch trickTurn % known {
        case 0:
            withAnimation(.easeInOut(duration: 0.6)) { spin = 360 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { spin = 0 }
        case 1:
            withAnimation(.easeInOut(duration: 0.6)) { flip = 360 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { flip = 0 }
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
                                if name.isEmpty { name = model.displayName(for: item) }
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
        }
    }
}
