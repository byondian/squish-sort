import SwiftUI
import SquishPolicy

/// Home (Jelly pop, Ian 16 Nov): the wobbling logo, the Buddy, one big button straight into
/// the next level, then the Collection and the Mystery Bag. Nothing here pops up by itself.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var coinGate = false
    @State private var coinGatePassed = false
    @State private var wobble = false
    @State private var showStamps = false
    @State private var coinsFlying = false
    @State private var coinsLanded = false

    var body: some View {
        // While a new trick is being taught, everything but the Buddy steps back.
        let teaching = model.trickTeaching != nil
        GeometryReader { screen in
            // Small phones get a smaller logo and shorter buttons, so the Buddy keeps its room.
            let compact = screen.size.height < 720
            // An iPad: everything in the middle is bigger, and the buttons keep a comfortable width.
            let big = screen.size.width >= 700
            VStack(spacing: 0) {
                VStack(spacing: compact ? 6 : 10) {
                    topBar.dimmed(teaching)
                    JellyLogo(scale: big ? 0.64 : compact ? 0.32 : 0.42).dimmed(teaching)
                        .padding(.top, compact ? 9 : 14)
                        .accessibilityElement().accessibilityIdentifier("home-logo")
                    if model.adventDoors > 0 { AdventShelf().dimmed(teaching) }
                    Spacer(minLength: 0)
                    if model.isExtraUnlocked(.buddy) {
                        BuddyHomeView(side: big ? 340 : compact ? 160 : 200)
                    } else {
                        SquishyView(id: model.progress.favouriteSquishy ?? "peach-bun", rarity: .rare)
                            .frame(width: big ? 300 : 170, height: big ? 300 : 170)
                    }
                    Spacer(minLength: 0)
                    if let banner = model.eventBanner {
                        // A light event from the website's config. No countdown.
                        Text(verbatim: banner).font(Theme.body(13)).foregroundStyle(Theme.plum)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 12).padding(.vertical, 4)
                            .background(Capsule().fill(Theme.butter))
                            .dimmed(teaching)
                    }
                    if model.dailyJarOpen { dailyJarButton.frame(maxWidth: 620).dimmed(teaching) }
                    playButton(height: big ? 124 : compact ? 84 : 104).frame(maxWidth: 620).dimmed(teaching)
                    HStack(spacing: 12) {
                        collectionButton(height: big ? 104 : compact ? 76 : 88)
                        mysteryButton(height: big ? 104 : compact ? 76 : 88)
                    }
                    .frame(maxWidth: 620)
                    .dimmed(teaching)
                }
                // The bar sits just under the status bar, with the same 16 points either side.
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
                tabBar.dimmed(teaching)
            }
        }
        .background(
            LinearGradient(stops: [.init(color: Color(hex: 0xFFE1EE), location: 0), .init(color: Color(hex: 0xFFF0F4), location: 0.48),
                                   .init(color: Color(hex: 0xFFF6EA), location: 1)], startPoint: .top, endPoint: .bottom)
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
                                          y: geo.size.height * 0.5 + CGFloat((i * 53) % 70 - 35)))
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
        .onDisappear { model.trickTeaching = nil }
    }

    /// Every item in the top bar is this tall and sits on one centre line (a UI test holds it to that).
    static let barHeight: CGFloat = 44

    /// Coins (opens the coin shop), the stamp card, the festive door in season, and settings.
    private var topBar: some View {
        HStack(alignment: .center, spacing: 8) {
            // Under-13s (and players who gave no age) meet the grown-up check first, the same one Settings uses.
            Button { if model.isGentleMode { coinGate = true } else { model.screen = .shop } } label: {
                HStack(spacing: 6) {
                    CoinIcon().font(.system(size: 20))
                    Text("\(model.progress.wallet.balance)")
                        .font(Theme.body(17)).foregroundStyle(Theme.plum)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(model.progress.wallet.balance)))
                        .animation(.easeOut(duration: 0.9), value: model.progress.wallet.balance)
                    // No nudge to buy coins for younger players: the pill is only a counter there.
                    if !model.isGentleMode {
                        Image(systemName: "plus").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Circle().fill(Theme.mint))
                    }
                }
                .scaleEffect(coinsLanded && coinsFlying ? 1.12 : 1)
                // The same inset on both ends: the coin on the left, the plus (or the number) on the right.
                .padding(.leading, 11).padding(.trailing, model.isGentleMode ? 14 : 11).frame(height: HomeView.barHeight)
                .background(Capsule().fill(.white))
            }
            .buttonStyle(PressSquish())
            .accessibilityLabel(Text("Get coins"))
            .sheet(isPresented: $coinGate, onDismiss: { if coinGatePassed { coinGatePassed = false; model.screen = .shop } }) {
                ParentalGate(onPass: { coinGatePassed = true; coinGate = false }, onCancel: { coinGate = false })
            }
            .accessibilityIdentifier("home-coins")
            stampPill
            Spacer(minLength: 0)
            // The festive door: a side world. No countdown anywhere.
            if model.showsFestiveDoor {
                Button { model.openFestiveDoor() } label: {
                    Image(systemName: "door.left.hand.closed").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Circle().fill(Color(hex: 0xD8434F)))
                }
                .buttonStyle(PressSquish())
                .accessibilityLabel(Text(AppModel.christmasWorldName))
                .accessibilityIdentifier("festive-door")
            }
            IconButton(system: "gearshape.fill") { model.screen = .settings }
        }
        .frame(height: HomeView.barHeight)
    }

    /// Daily Jar: one board a day. Once it is won it just says so until tomorrow; nothing counts down.
    private var dailyJarButton: some View {
        let done = model.dailyJarDone
        return Button { model.playDailyJar() } label: {
            HStack(spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "sun.max.fill").font(.system(size: 17, weight: .bold))
                    .foregroundStyle(done ? Theme.mint : Theme.butter)
                Text("Daily Jar").font(Theme.title(17))
                Spacer(minLength: 0)
                if done {
                    Text("Done today").font(Theme.body(14)).opacity(0.7)
                } else {
                    Label { Text(verbatim: "+\(model.dailyJarCoins)") } icon: { CoinIcon() }.font(Theme.body(15))
                }
            }
            .foregroundStyle(Theme.plum)
            .padding(.horizontal, 16).frame(height: 44)
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(Theme.plum.opacity(0.12), lineWidth: 2))
        }
        .buttonStyle(PressSquish())
        .disabled(done)
        .accessibilityIdentifier("home-daily-jar")
    }

    /// The main button: straight into the level to play next, with how close the next capsule is.
    private func playButton(height: CGFloat) -> some View {
        let index = model.progress.highestUnlocked
        // The next world is waiting for stars: the button says how many and leads to the map.
        let gate = model.starGateWaiting
        return Button { model.screen = gate == nil ? .level(index) : .map } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill").font(.system(size: height * 0.28, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xEE4689))
                    .frame(width: height * 0.6, height: height * 0.6)
                    .background(Circle().fill(.white))
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if let gate { Text("\(gate.more) more stars") } else { Text("Level \(model.levelNumber(index))") }
                    }
                    .font(Theme.title(height * 0.32)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let gate {
                        Text("to open \(Text(AppModel.worldName(gate.next)))").font(Theme.body(13))
                            .foregroundStyle(Color(hex: 0xEE4689))
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(Capsule().fill(.white))
                    } else if model.levels.indices.contains(index) {
                        Text(AppModel.worldName(model.levels[index].file.world)).font(Theme.body(13))
                            .foregroundStyle(Color(hex: 0xEE4689))
                            .padding(.horizontal, 10).padding(.vertical, 2)
                            .background(Capsule().fill(.white))
                    }
                }
                Spacer(minLength: 0)
                if gate == nil, let before = model.levelsToNextCapsule(after: index - 1) {
                    // A capsule over three pips: one fills with each level won.
                    let toGo = before + 1
                    VStack(spacing: 6) {
                        Image(systemName: "capsule.portrait.fill").font(.system(size: height * 0.26, weight: .bold))
                            .foregroundStyle(.white)
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle().fill(Color.white.opacity(i < 3 - toGo ? 1 : 0.35)).frame(width: 8, height: 8)
                            }
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(toGo == 1 ? Text("1 more level to a capsule") : Text("\(toGo) more levels to a capsule"))
                }
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
        .overlay(alignment: .topTrailing) {
            // "NEW" only for a squishy not looked at yet; a set prize waiting to be collected is a gift.
            if model.newSquishies > 0 || model.setGoalWaiting {
                Group { if model.newSquishies > 0 { Text("NEW") } else { Text(verbatim: "🎁") } }
                    .font(Theme.body(11)).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.bubblegum))
                    .overlay(Capsule().stroke(.white, lineWidth: 2))
                    .rotationEffect(.degrees(8))
                    .offset(x: 4, y: -6)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityIdentifier("home-collection")
    }

    /// The Mystery Bag: a bag with a big question mark. Before it opens, it says when it will.
    private func mysteryButton(height: CGFloat) -> some View {
        let open = model.isExtraUnlocked(.mysteryBag)
        let ready = open && model.progress.mystery.canPlay(today: model.mysteryDay)
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

    /// The places, along the bottom. Home is where we are; the ones that open later show a lock until then.
    private var tabBar: some View {
        HStack(spacing: 4) {
            tab("Home", "house.fill", selected: true) {}
            tab("Levels", "circle.grid.3x3.fill") { model.screen = .map }
            tab("Squish Room", "hand.tap.fill", extra: .squishRoom) { model.open(.squishRoom) }
            tab("Workshop", "paintbrush.fill", extra: .maker) { model.open(.maker) }
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                .fill(Color.white.opacity(0.92))
                .shadow(color: Theme.plum.opacity(0.12), radius: 8, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tab(_ title: LocalizedStringKey, _ icon: String, selected: Bool = false, extra: Extra? = nil,
                     action: @escaping () -> Void) -> some View {
        let locked = extra.map { !model.isExtraUnlocked($0) } ?? false
        return Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: locked ? "lock.fill" : icon).font(.system(size: 19, weight: .bold))
                Text(title).font(Theme.body(11)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(selected ? Color.white : Theme.plum.opacity(locked ? 0.35 : 0.8))
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(selected ? Theme.bubblegum : Color.clear))
            .overlay(alignment: .topTrailing) { if let extra, model.isNew(extra) { NewBadge().offset(x: 2, y: -8) } }
        }
        .buttonStyle(PressSquish())
        .disabled(locked)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The stamp card: one stamp for the first win of each day, once level 3 is won.
    /// Nothing is lost on a missed day. Tap to see the seven rewards.
    private var stampPill: some View {
        Button { showStamps = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "seal.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.bubblegum)
                Text(verbatim: "\(model.progress.stampCard.stamps)/\(StampCard.size)")
                    .font(Theme.body(15)).foregroundStyle(Theme.plum).monospacedDigit()
            }
            .padding(.horizontal, 12).frame(height: HomeView.barHeight)
            .background(Capsule().fill(.white))
        }
        .buttonStyle(PressSquish())
        .accessibilityLabel(Text("Stamp card"))
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
}

private extension View {
    /// Steps back while the Buddy is teaching a trick.
    func dimmed(_ on: Bool) -> some View {
        opacity(on ? 0.25 : 1).allowsHitTesting(!on).animation(.easeInOut(duration: 0.25), value: on)
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

/// The Buddy on the home screen: says hello, reacts to pokes, eats treats and does tricks.
/// Tricks are finger movements on the Buddy itself: round it for a spin, a flick up for a flip,
/// a double tap for a dance. It never gets hungry, sick or sad.
struct BuddyHomeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var side: CGFloat = 200
    @State private var picking = false
    @State private var showSheet = false
    @State private var pokes = 0
    @State private var feeding = false
    @State private var gulp = false
    @State private var biggerPop = false
    @State private var flying = "🧁"
    @State private var burst = false
    @State private var burstShown = false
    @State private var heartUp = false
    @State private var spin = 0.0
    @State private var flip = 0.0
    @State private var sway: CGFloat = 0
    @State private var hop: CGFloat = 0
    @State private var giftWobble = false
    @State private var talking = false
    /// The pointing hand's loop while a trick is taught, and the cheer once it is done.
    @State private var handMoves = false
    @State private var cheer = false
    /// The trick just done, named over the Buddy for a moment so it is clear the movement was read.
    @State private var trickWord: Int?

    static let trickNames: [LocalizedStringKey] = ["Spin", "Flip", "Dance"]
    static let trickHows: [LocalizedStringKey] = ["Draw a circle round your Buddy", "Swipe up on your Buddy", "Double tap your Buddy"]
    static let trickIcons = ["arrow.triangle.2.circlepath", "arrow.up", "hand.tap.fill"]

    /// A trick just learned: Home steps back, the Buddy shows it once, and a hand shows how to ask for it.
    private func showOffTrick() {
        guard let number = model.trickToShow, (1...3).contains(number) else { return }
        model.trickToShow = nil
        cheer = false
        handMoves = false
        withAnimation { model.buddySays = nil; model.trickTeaching = number }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            spin = 0; flip = 0; sway = 0; hop = 0
            playTrick(number)
            hearts()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: number == 1 ? 2.2 : 1.1).repeatForever(autoreverses: false)) { handMoves = true }
            }
        }
        // It never holds Home for long: after a while it steps aside by itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            if model.trickTeaching == number, !cheer { withAnimation { model.trickTeaching = nil } }
        }
    }

    private func hearts() {
        burstShown = true
        burst = false
        withAnimation(.easeOut(duration: 0.7)) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { burstShown = false; burst = false }
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
        VStack(spacing: 8) {
            if let ref = model.progress.buddy.squishy {
                if let teaching = model.trickTeaching {
                    trickCard(teaching)
                        .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                }
                ZStack(alignment: .bottomTrailing) {
                    toy(ref)
                    // One round treat button by the Buddy, with how many are left. Gone when there are none.
                    if model.progress.buddy.treats > 0, model.trickTeaching == nil {
                        Button { feed { model.feedBuddy() } } label: {
                            Text(verbatim: "🧁").font(.system(size: 28))
                                .frame(width: 58, height: 58)
                                .background(Circle().fill(Theme.butter))
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .shadow(color: Theme.plum.opacity(0.18), radius: 4, y: 3)
                                .overlay(alignment: .topTrailing) {
                                    Text(verbatim: "\(model.progress.buddy.treats)")
                                        .font(Theme.body(13)).foregroundStyle(.white).monospacedDigit()
                                        .frame(minWidth: 22, minHeight: 22)
                                        .background(Capsule().fill(Theme.bubblegum))
                                        .overlay(Capsule().stroke(.white, lineWidth: 2))
                                        .offset(x: 4, y: -4)
                                }
                        }
                        .buttonStyle(PressSquish())
                        .accessibilityLabel(Text("Treat ×\(model.progress.buddy.treats)"))
                        .accessibilityIdentifier("treat")
                        .padding(.trailing, 30)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                // What the Buddy says floats above its head and takes no room of its own, so the
                // screen never has to make space for it and then close up again.
                .overlay(alignment: .top) {
                    if model.trickTeaching == nil, let says = model.buddySays {
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
                        .alignmentGuide(.top) { $0[.bottom] - 6 }
                    }
                }
                // The name row opens the Buddy's own page: friendship, tricks, change Buddy.
                Button { showSheet = true } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: model.progress.buddy.name).font(Theme.title(22)).foregroundStyle(Theme.plum)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        // The heart ring fills towards the next trick.
                        ZStack {
                            Circle().stroke(Theme.bubblegum.opacity(0.2), lineWidth: 4)
                            Circle().trim(from: 0, to: model.progress.buddy.trickProgress)
                                .stroke(Theme.bubblegum, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Theme.bubblegum)
                        }
                        .frame(width: 28, height: 28)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: model.progress.buddy.hearts)
                        Text(verbatim: "\(model.progress.buddy.hearts)").font(Theme.body(15)).foregroundStyle(Theme.bubblegum)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.plum.opacity(0.4))
                    }
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressSquish())
                .accessibilityIdentifier("buddy-name")
                .opacity(model.trickTeaching == nil ? 1 : 0.25)
                .allowsHitTesting(model.trickTeaching == nil)
                sizeMeter
                    .opacity(model.trickTeaching == nil ? 1 : 0.25)
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
            } else {
                Button { picking = true } label: { Label("Choose your Buddy", systemImage: "heart.fill") }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .overlay(alignment: .topTrailing) { if model.isNew(.buddy) { NewBadge().offset(x: 10, y: -10) } }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.buddySays)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.trickTeaching)
        // A trick just learned is taught at once.
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
        .sheet(isPresented: $showSheet) {
            BuddySheet { showSheet = false }.environmentObject(model)
        }
    }

    /// The Buddy itself: as soft as in the Squish Room. Knead, pull, pinch, pick up and throw.
    private func toy(_ ref: String) -> some View {
        SoftSquishy(toy: ref, look: ref, feel: model.feel(for: ref), mode: .room, pokes: pokes, comesHome: true,
                    wear: model.progress.buddy.worn,
                    onTouch: { withAnimation { model.pokeBuddy() } },
                    onDoubleTap: { _ = ask(for: 3) },
                    onGesture: { gesture in ask(for: gesture == .circle ? 1 : 2) }) {
            SquishRefView(ref: ref)
        }
        .frame(maxWidth: .infinity).frame(height: side)
        // Tricks: spin, flip and dance. Then the little growth from hearts, which never goes back.
        .rotationEffect(.degrees(spin))
        .modifier(FlipEffect(turn: flip))
        .offset(x: sway, y: hop)
        // It squashes a little as it talks.
        .scaleEffect(x: talking ? 1.04 : 1, y: talking ? 0.94 : 1, anchor: .bottom)
        // Every treat: a big gulp that springs back to a size a little bigger than before.
        .scaleEffect(gulp ? 1.22 : 1, anchor: .bottom)
        .scaleEffect(1 + buddySize, anchor: .bottom)
        .padding(.top, side * 0.6 * buddySize)
        .animation(.spring(response: 0.5, dampingFraction: 0.5), value: model.progress.buddy.lastTreatAt)
        .animation(.spring(response: 0.5, dampingFraction: 0.5), value: model.progress.buddy.hearts)
        .onChange(of: model.progress.buddy.hearts) { old, new in
            guard new > old else { return }
            withAnimation(.easeOut(duration: 0.18)) { gulp = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.35)) { gulp = false }
            }
            // "Bigger!" only when it is: a Giant Buddy just enjoys the treat.
            guard BuddyState.growth(hearts: new) > BuddyState.growth(hearts: old) else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { biggerPop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { withAnimation { biggerPop = false } }
        }
        .overlay(alignment: .top) {
            if let n = trickWord, (1...3).contains(n) {
                Text(BuddyHomeView.trickNames[n - 1]).font(Theme.title(24)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.grape))
                    .rotationEffect(.degrees(4))
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("trick-word")
            }
        }
        .overlay(alignment: .top) {
            if biggerPop {
                Text("Bigger!").font(Theme.title(22)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 4)
                    .background(Capsule().fill(Theme.bubblegum))
                    .rotationEffect(.degrees(-5))
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            // A treat flies up to the Buddy, and a heart floats off it.
            if feeding {
                Text(verbatim: flying).font(.system(size: flying == "🎁" ? 44 : 34))
                    .transition(.asymmetric(insertion: .offset(x: 70, y: 110).combined(with: .opacity),
                                            removal: .scale(scale: 0.1).combined(with: .opacity)))
            }
            // A gift, a new trick: a burst of hearts.
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) / 8 * 2 * Double.pi
                Image(systemName: "heart.fill").font(.system(size: 20)).foregroundStyle(Theme.bubblegum)
                    .offset(x: burst ? CGFloat(cos(angle)) * 110 : 0, y: burst ? CGFloat(sin(angle)) * 110 - 20 : 0)
                    .scaleEffect(burst ? 1.2 : 0.2)
                    .opacity(burstShown ? (burst ? 0 : 1) : 0)
                    .allowsHitTesting(false)
            }
            if heartUp {
                Image(systemName: "heart.fill").font(.system(size: 26)).foregroundStyle(Theme.bubblegum)
                    .transition(.asymmetric(insertion: .scale(scale: 0.3).combined(with: .opacity),
                                            removal: .offset(x: 50, y: -120).combined(with: .opacity)))
                    .allowsHitTesting(false)
            }
            // Show, don't tell: the hand draws the movement that asks for the new trick.
            if let teaching = model.trickTeaching, !cheer { trickHand(teaching) }
        }
        .overlay(alignment: .bottomLeading) {
            // The daily gift sits by the Buddy and wobbles until it is opened, then bursts.
            if model.dailyGiftWaiting {
                Text(verbatim: "🎁").font(.system(size: 46))
                    .rotationEffect(.degrees(giftWobble ? 9 : -9), anchor: .bottom)
                    .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: giftWobble)
                    .offset(x: 26, y: -8)
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
    }

    /// The card over the Buddy while a new trick is taught. A tap puts it away.
    private func trickCard(_ number: Int) -> some View {
        VStack(spacing: 4) {
            Text(cheer ? LocalizedStringKey("Yay!") : LocalizedStringKey("NEW TRICK"))
                .font(Theme.body(13)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 3)
                .background(Capsule().fill(Theme.bubblegum))
            HStack(spacing: 8) {
                Image(systemName: BuddyHomeView.trickIcons[number - 1]).font(.system(size: 22, weight: .heavy))
                Text(BuddyHomeView.trickNames[number - 1]).font(Theme.title(28))
            }
            .foregroundStyle(Theme.plum)
            if !cheer {
                Text(BuddyHomeView.trickHows[number - 1]).font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.8))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text("Try it now!").font(Theme.body(13)).foregroundStyle(Theme.bubblegum)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.butter, lineWidth: 4))
        .onTapGesture { withAnimation { model.trickTeaching = nil } }
        .accessibilityIdentifier("trick-card")
    }

    /// A pointing hand over the Buddy that plays the movement: round it, up it, or two taps on it.
    @ViewBuilder private func trickHand(_ number: Int) -> some View {
        let r = side * 0.5
        let dots = StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 10])
        Group {
            switch number {
            case 1:
                ZStack {
                    Circle().stroke(Theme.bubblegum.opacity(0.7), style: dots).frame(width: r * 2, height: r * 2)
                    Text(verbatim: "👆").font(.system(size: 38))
                        .rotationEffect(.degrees(handMoves ? -360 : 0))
                        .offset(y: -r)
                        .rotationEffect(.degrees(handMoves ? 360 : 0))
                }
            case 2:
                ZStack {
                    VStack(spacing: 0) {
                        Image(systemName: "arrowtriangle.up.fill").font(.system(size: 16)).foregroundStyle(Theme.bubblegum.opacity(0.8))
                        Rectangle().fill(.clear).frame(width: 4, height: r * 1.3)
                            .overlay(Path { p in p.move(to: CGPoint(x: 2, y: 0)); p.addLine(to: CGPoint(x: 2, y: r * 1.3)) }
                                .stroke(Theme.bubblegum.opacity(0.7), style: dots))
                    }
                    .offset(x: -30)
                    Text(verbatim: "👆").font(.system(size: 38))
                        .offset(y: handMoves ? -r * 0.75 : r * 0.6)
                        .opacity(handMoves ? 0.2 : 1)
                }
            default:
                Text(verbatim: "👆").font(.system(size: 38))
                    .scaleEffect(handMoves ? 1 : 0.78)
                    .offset(x: 10, y: 24)
                    .background(Circle().stroke(Theme.bubblegum.opacity(handMoves ? 0 : 0.8), lineWidth: 4)
                        .frame(width: handMoves ? 90 : 30, height: handMoves ? 90 : 30).offset(y: 4))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22).repeatForever(autoreverses: true), value: handMoves)
            }
        }
        .allowsHitTesting(false)
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
        min(BuddyHomeView.biggest, model.progress.buddy.growth
            + model.progress.buddy.puff(at: Date().timeIntervalSince1970, lasting: model.puffSeconds))
    }

    /// The most a Buddy is ever drawn bigger, growth and puff together, so it always fits on Home.
    private static let biggest = 0.72

    static func sizeName(_ size: BuddyState.Size) -> String {
        switch size {
        case .tiny: return String(localized: "Tiny")
        case .small: return String(localized: "Small")
        case .big: return String(localized: "Big")
        case .huge: return String(localized: "Huge")
        case .giant: return String(localized: "Giant")
        }
    }

    /// The size meter: which size the Buddy is, and how far it is to the next. Every treat moves it.
    private var sizeMeter: some View {
        let buddy = model.progress.buddy
        return HStack(spacing: 8) {
            Text(verbatim: BuddyHomeView.sizeName(buddy.size)).font(Theme.body(13)).foregroundStyle(Theme.plum)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.plum.opacity(0.12))
                    Capsule().fill(Theme.mint)
                        .frame(width: max(8, geo.size.width * buddy.sizeProgress))
                }
            }
            .frame(width: 90, height: 8)
            if let next = buddy.size.next {
                Text(verbatim: BuddyHomeView.sizeName(next)).font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.5))
            } else {
                Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Theme.butter)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: buddy.hearts)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("buddy-size")
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
            if gift { hearts() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            squish()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { heartUp = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeIn(duration: 0.5)) { heartUp = false }
        }
    }

    /// The player asked for trick `number` with its movement. Nothing happens until the Buddy knows it.
    /// True if the trick was done.
    private func ask(for number: Int) -> Bool {
        guard number <= model.progress.buddy.tricksUnlocked, playTrick(number) else { return false }
        if model.trickTeaching == number, !cheer {
            // Done once: a cheer, and Home comes back.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { cheer = true }
            hearts()
            model.haptics.win()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation { model.trickTeaching = nil }
                cheer = false
                handMoves = false
            }
        }
        return true
    }

    /// Does trick `number`: 1 spin, 2 flip, 3 dance. With Reduce Motion every trick is a gentle hop.
    @discardableResult
    private func playTrick(_ number: Int) -> Bool {
        guard spin == 0, flip == 0, sway == 0, hop == 0 else { return false }
        model.sounds.play("trick", or: "buddy_giggle")
        model.haptics.complete()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { trickWord = number }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { withAnimation { if trickWord == number { trickWord = nil } } }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { hop = -16 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { withAnimation(.easeIn(duration: 0.2)) { hop = 0 } }
            return true
        }
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
        return true
    }
}

/// The Buddy's own page, opened from its name on Home: friendship, the tricks it knows and the
/// finger movement for each, the next trick, and Change Buddy.
struct BuddySheet: View {
    @EnvironmentObject var model: AppModel
    let done: () -> Void
    @State private var picking = false

    var body: some View {
        let buddy = model.progress.buddy
        ScrollView {
            VStack(spacing: 14) {
                if let ref = buddy.squishy {
                    SquishRefView(ref: ref).frame(width: 120, height: 120)
                }
                Text(verbatim: buddy.name).font(Theme.title(28)).foregroundStyle(Theme.plum)
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").foregroundStyle(Theme.bubblegum)
                    Text(verbatim: "\(buddy.hearts)").font(Theme.title(20)).foregroundStyle(Theme.bubblegum)
                    ProgressView(value: buddy.trickProgress).tint(Theme.bubblegum).frame(width: 140)
                }
                Text("Tricks").font(Theme.title(20)).foregroundStyle(Theme.plum)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(1...BuddyState.tricks, id: \.self) { n in
                    if n <= buddy.tricksUnlocked {
                        row(icon: BuddyHomeView.trickIcons[n - 1], tint: Theme.mint,
                            title: Text(BuddyHomeView.trickNames[n - 1]), detail: Text(BuddyHomeView.trickHows[n - 1]))
                    }
                }
                if let toGo = buddy.heartsToNextTrick {
                    row(icon: "lock.fill", tint: Color.white, title: Text("Next trick"),
                        detail: Text("\(toGo) more hearts to the next trick"))
                        .opacity(0.7)
                }
                Button { picking = true } label: {
                    Label("Change Buddy", systemImage: "arrow.left.arrow.right")
                }
                .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                .padding(.top, 6)
                .accessibilityIdentifier("change-buddy")
            }
            .padding(20)
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $picking) {
            BuddyPickerView { picking = false; done() }.environmentObject(model)
        }
    }

    private func row(icon: String, tint: Color, title: Text, detail: Text) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.plum)
                .frame(width: 44, height: 44).background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                title.font(Theme.title(18)).foregroundStyle(Theme.plum)
                detail.font(Theme.body(14)).foregroundStyle(Theme.plum.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.8)))
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
