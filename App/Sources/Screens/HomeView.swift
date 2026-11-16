import SwiftUI
import SquishPolicy

/// Home is one scene, not a grid: a shelf at the top, the Buddy on a rug in the
/// middle, Play at the bottom. Objects are the buttons, and each appears when
/// its extra unlocks. Nothing here pops up by itself.
struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var wobble = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                // The coins pill opens the shop (under-13s reach it only from Settings).
                Button { if !model.isGentleMode { model.screen = .shop } } label: {
                    Label("\(model.progress.wallet.balance)", systemImage: "circle.hexagongrid.fill")
                        .font(Theme.body(17)).foregroundStyle(Theme.plum)
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
            HStack(alignment: .center, spacing: 4) {
                VStack {
                    if model.isExtraUnlocked(.squishRoom) {
                        object("Squish Room", "hand.tap.fill", Theme.bubblegum.opacity(0.35), extra: .squishRoom) { model.open(.squishRoom) }
                    }
                }
                .frame(width: 76)
                if model.isExtraUnlocked(.buddy) {
                    BuddyHomeView()
                } else {
                    SquishyView(id: model.progress.favouriteSquishy ?? "peach-bun", rarity: .rare)
                        .frame(width: 170, height: 170)
                }
                VStack(spacing: 12) {
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
                .frame(width: 76)
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
        }
        .background(alignment: .bottom) {
            Capsule().fill(Color(red: 0.87, green: 0.72, blue: 0.53)).frame(height: 10).offset(y: -22)
        }
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
        // The stamp card: one stamp for the first win of each day. Nothing is lost on a missed day.
        HStack(spacing: 5) {
            ForEach(0..<StampCard.size, id: \.self) { i in
                Image(systemName: i < model.progress.stampCard.stamps ? "seal.fill" : "circle.dotted")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(i < model.progress.stampCard.stamps ? Theme.bubblegum : Theme.plum.opacity(0.3))
            }
            Text(model.progress.stampCard.canStamp(today: model.today) ? LocalizedStringKey("Win a level for today's stamp")
                 : LocalizedStringKey("Stamped today!"))
                .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.65))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stamp-card")
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
    @State private var bounce = false

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
                SquishRefView(ref: ref, squash: bounce ? 0.7 : 0)
                    .frame(width: 180, height: 180)
                    .onTapGesture { poke() }
                    .accessibilityIdentifier("buddy")
                HStack(spacing: 8) {
                    Text(verbatim: model.progress.buddy.name).font(Theme.title(22))
                    Label("\(model.progress.buddy.hearts)", systemImage: "heart.fill")
                        .font(Theme.body(15)).foregroundStyle(Theme.bubblegum)
                }
                .foregroundStyle(Theme.plum)
                if model.dailyGiftReady {
                    // The Buddy's daily gift: coins by opt-in ad, or free in gentle mode.
                    Button { withAnimation { model.takeDailyGift() }; squish() } label: {
                        Label("Daily gift", systemImage: model.isGentleMode || model.ownsRemoveAds ? "gift.fill" : "play.rectangle.fill")
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .accessibilityIdentifier("daily-gift")
                }
                HStack(spacing: 10) {
                    Button { withAnimation { model.feedBuddy() }; squish() } label: {
                        Label("Treat ×\(model.progress.buddy.treats)", systemImage: "birthday.cake.fill")
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                    .disabled(model.progress.buddy.treats == 0)
                    .opacity(model.progress.buddy.treats == 0 ? 0.5 : 1)
                    Button { picking = true } label: { Image(systemName: "pencil") }
                        .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                        .accessibilityLabel(Text("Change Buddy"))
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
        withAnimation(.easeOut(duration: 0.12)) { bounce = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.45)) { bounce = false }
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

    var body: some View {
        VStack(spacing: 14) {
            Text("Choose your Buddy").font(Theme.title(24)).foregroundStyle(Theme.plum).padding(.top, 20)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(model.squeezables, id: \.self) { item in
                        SquishRefView(ref: item)
                            .frame(width: 68, height: 68)
                            .background(RoundedRectangle(cornerRadius: 16).fill(item == ref ? Theme.butter : Color.white))
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
