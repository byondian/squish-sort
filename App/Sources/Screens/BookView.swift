import SwiftUI
import SquishLevels
import SquishPolicy

/// The Collection: how many squishies are found, one tab per world, three set goals for the world
/// shown, and a grid of cubbies. A tap on a found squishy opens its card.
struct BookView: View {
    @EnvironmentObject var model: AppModel
    @State private var world = "toyshop"
    @State private var card: Collectible?
    @State private var riddle: Collectible?
    @State private var claimed: String?
    @State private var handBounce = false

    private var worlds: [String] {
        (LevelCatalog.worlds + [ChristmasWorld.id]).filter { showsShelf($0) }
    }

    private var items: [Collectible] { model.roster.collectibles.filter { $0.world == world } }
    private var ownedHere: [Collectible] { items.filter { model.progress.collection.owns($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Collection")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    tabs
                    goals
                    grid
                    spares
                    if !model.progress.made.isEmpty { madeShelf }
                    Text("Capsule odds: rare \(model.capsuleOddsPercent.rare)%, ultra-rare \(model.capsuleOddsPercent.ultra)%. Common squishies join when you sort a jar of them. Squishies are earned by playing and are never sold.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                    Text("The golden capsule for filling a world's star jar always holds an ultra-rare.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                    Text("Secret squishies never come from capsules: each one comes out when every other squishy of its world is found.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                }
                .padding(16)
            }
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .overlay { if claimed != nil { Confetti(count: 50, seconds: 2.5).ignoresSafeArea().id(claimed) } }
        .overlay {
            if let c = card {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { card = nil }
                    ScrollView {
                        SquishyCard(squishy: c, step: ownedHere.count > 1 ? { step($0) } : nil) { card = nil }
                            .padding(.vertical, 24)
                    }
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            // A secret's riddle, or for any other squishy not found yet, where it comes from.
            if let r = riddle, let line = r.rarity == .secret ? model.riddle(for: r.id) : model.howToFind(r) {
                HStack(spacing: 10) {
                    Text(verbatim: r.rarity == .secret ? "🤫" : "🔎").font(.system(size: 26))
                    Text(verbatim: line).font(Theme.body(15)).foregroundStyle(Theme.plum)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(r.rarity == .secret ? RarityLook.gold : RarityLook.color(r.rarity), lineWidth: 3))
                .padding(16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { riddle = nil }
                .accessibilityIdentifier("secret-riddle")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: card)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: riddle)
        .onAppear {
            // Open on the world being played.
            let playing = model.levels.indices.contains(model.progress.highestUnlocked)
                ? model.levels[model.progress.highestUnlocked].file.world : "toyshop"
            if worlds.contains(playing) { world = playing }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let all = model.roster.collectibles
        let found = all.filter { model.progress.collection.owns($0.id) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(found.count) of \(all.count) squishies found").font(Theme.title(22)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            ProgressBar(fraction: all.isEmpty ? 0 : Double(found.count) / Double(all.count), fill: .white, track: .white.opacity(0.3))
                .frame(height: 12)
            HStack(spacing: 6) {
                ForEach(Rarity.allCases, id: \.self) { rarity in
                    let of = all.filter { $0.rarity == rarity }.count
                    let have = found.filter { $0.rarity == rarity }.count
                    Text(verbatim: "\(RarityLook.name(rarity)) \(have)/\(of)")
                        .font(Theme.body(11)).foregroundStyle(Theme.plum).lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Capsule().fill(.white))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(
            LinearGradient(colors: [Color(hex: 0xFF8DBD), Color(hex: 0xFF5C9D)], startPoint: .top, endPoint: .bottom)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("collection-hero")
    }

    // MARK: - World tabs

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(worlds, id: \.self) { id in tab(id) }
            }
        }
    }

    private func tab(_ id: String) -> some View {
        let on = id == world
        // A gold frame once every squishy of the world is found.
        let gold = SetGoal.world.isDone(world: id, roster: model.roster, state: model.progress.collection)
        return Button {
            model.sounds.play("button")
            world = id
            riddle = nil
        } label: {
            HStack(spacing: 4) {
                if gold { Text(verbatim: "👑").font(.system(size: 13)) }
                Text(verbatim: model.worldTitle(id)).font(Theme.body(14)).lineLimit(1)
                if model.isWorldComplete(id) {
                    Image("boss-crown").resizable().scaledToFit().frame(height: 14)
                        .accessibilityIdentifier("world-badge-\(id)")
                }
            }
            .foregroundStyle(on ? .white : Theme.plum)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(on ? Theme.grape : .white))
            .overlay(Capsule().stroke(gold ? RarityLook.gold : .clear, lineWidth: 3))
        }
        .buttonStyle(PressSquish())
        .accessibilityIdentifier("collection-tab-\(id)")
    }

    // MARK: - Set goals

    private var goals: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(SetGoal.allCases, id: \.self) { goal in goalCard(goal) }
        }
    }

    private func goalCard(_ goal: SetGoal) -> some View {
        let p = goal.progress(world: world, roster: model.roster, state: model.progress.collection)
        let done = p.of > 0 && p.found == p.of
        let taken = model.setGoalClaimed(goal, world: world)
        let ready = done && !taken && goal.coins > 0
        let key = goal.key(world: world)
        return VStack(spacing: 5) {
            Text(verbatim: goalTitle(goal)).font(Theme.body(12)).foregroundStyle(Theme.plum).lineLimit(1).minimumScaleFactor(0.6)
            Group {
                if goal == .world {
                    Text(verbatim: done ? "⭐️" : "❓").font(.system(size: 22))
                } else {
                    Label { Text(verbatim: "\(goal.coins)") } icon: { CoinIcon() }
                        .font(Theme.title(16)).foregroundStyle(Theme.plum)
                }
            }
            .frame(height: 26)
            ProgressBar(fraction: p.of > 0 ? Double(p.found) / Double(p.of) : 0, fill: goalColor(goal)).frame(height: 8)
            if ready {
                Button {
                    if model.claimSetGoal(goal, world: world) { claimed = key }
                } label: { Text("Claim").font(Theme.body(13)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 5) }
                    .background(Capsule().fill(Theme.bubblegum))
                    .buttonStyle(PressSquish())
                    .accessibilityIdentifier("claim-\(key)")
            } else {
                Text(verbatim: done ? (goal == .world ? String(localized: "Secret found!") : String(localized: "Claimed")) : "\(p.found)/\(p.of)")
                    .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.vertical, 5)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ready ? Theme.butter : .clear, lineWidth: 3))
        .overlay(alignment: .bottom) {
            // Show, don't tell: a hand points at a prize that is waiting.
            if ready {
                Text(verbatim: "👆").font(.system(size: 30))
                    .offset(y: handBounce ? 24 : 32)
                    .allowsHitTesting(false)
                    .onAppear {
                        handBounce = false
                        withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { handBounce = true }
                    }
            }
        }
        .zIndex(ready ? 1 : 0)
    }

    private func goalTitle(_ goal: SetGoal) -> String {
        switch goal {
        case .commons: return String(localized: "All commons")
        case .rares: return String(localized: "All rares")
        case .world: return String(localized: "Whole world")
        }
    }

    private func goalColor(_ goal: SetGoal) -> Color {
        switch goal {
        case .commons: return RarityLook.color(.common)
        case .rares: return RarityLook.color(.rare)
        case .world: return RarityLook.gold
        }
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(items, id: \.id) { c in cubby(c) }
        }
    }

    private func cubby(_ c: Collectible) -> some View {
        let has = model.progress.collection.owns(c.id)
        let isNew = has && !model.progress.seenCards.contains(c.id)
        return Button {
            if has {
                model.haptics.land()
                card = c
            } else {
                // Not found yet: a secret tells its riddle, any other says where it comes from.
                model.haptics.land()
                riddle = riddle == c ? nil : c
            }
        } label: {
            VStack(spacing: 4) {
                SquishyView(id: c.id, rarity: c.rarity, silhouette: !has).frame(width: 74, height: 74)
                Text(verbatim: has ? c.name(in: model.language) : (c.rarity == .secret ? RarityLook.name(.secret) : "???"))
                    .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(has ? 1 : 0.5)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity).frame(height: 122)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(has ? 1 : 0.55)))
            .overlay {
                // A ring in the rarity colour for a rare and up.
                if has && c.rarity != .common {
                    RoundedRectangle(cornerRadius: 20).stroke(RarityLook.color(c.rarity), lineWidth: 3)
                }
            }
            .overlay(alignment: .topLeading) {
                if has {
                    RarityTag(rarity: c.rarity).padding(6)
                } else {
                    // Where to look: a jar for commons, a capsule for rares and ultras.
                    Image(systemName: where_(c)).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.plum.opacity(0.4)).padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isNew {
                    Text("NEW").font(Theme.body(10)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.bubblegum))
                        .rotationEffect(.degrees(8))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(PressSquish())
        .accessibilityLabel(Text(verbatim: has ? c.name(in: model.language) : "???"))
        .accessibilityIdentifier("cubby-\(c.id)")
    }

    private func where_(_ c: Collectible) -> String {
        switch c.rarity {
        case .common: return "cylinder.fill"
        case .secret: return "questionmark"
        default: return "capsule.fill"
        }
    }

    private func step(_ by: Int) {
        let list = ownedHere
        guard let now = card, let i = list.firstIndex(of: now), !list.isEmpty else { return }
        card = list[(i + by + list.count) % list.count]
    }

    // MARK: - Spares

    private var spares: some View {
        let count = model.progress.collection.spareCount
        let need = CapsuleDrops.sparesPerReroll
        let missing = items.contains { $0.rarity != .secret && !model.progress.collection.owns($0.id) }
        let ready = count >= need && missing
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Spares").font(Theme.title(17)).foregroundStyle(Theme.plum)
                Spacer()
                Text(verbatim: "\(min(count, need))/\(need)").font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
            }
            ProgressBar(fraction: Double(min(count, need)) / Double(need), fill: ready ? Theme.butter : Theme.grape).frame(height: 12)
            if ready {
                Button("Swap 3 spares for a new squishy") { _ = model.rerollSpares(world: world) }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .font(Theme.body(15))
                    .accessibilityIdentifier("swap-spares")
                    .overlay(alignment: .bottomTrailing) {
                        Text(verbatim: "👆").font(.system(size: 30)).offset(x: 6, y: handBounce ? 22 : 30).allowsHitTesting(false)
                            .onAppear {
                                handBounce = false
                                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { handBounce = true }
                            }
                    }
            } else if count < need {
                Text("\(need - count) more swaps for a new one").font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.65))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(ready ? Theme.butter : .clear, lineWidth: 3))
    }

    /// Squishies from the Maker have their own shelf at the end. A tap squeezes one.
    private var madeShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My squishies").font(Theme.title(20))
                Image(systemName: "paintbrush.fill").font(.system(size: 14, weight: .bold)).opacity(0.6)
                Spacer()
                Text(verbatim: "\(model.progress.made.count)").font(Theme.body(15)).opacity(0.7)
            }
            .foregroundStyle(Theme.plum)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.progress.made) { made in
                        Button { model.squeeze(made.ref) } label: {
                            VStack(spacing: 4) {
                                MadeSquishyView(made: made).frame(width: 72, height: 72)
                                Text(verbatim: made.name).font(Theme.body(11)).lineLimit(1).foregroundStyle(Theme.plum)
                            }
                            .frame(width: 80)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .accessibilityIdentifier("book-made")
    }

    /// The Christmas tab appears once the festive door has been opened (or something from it is owned).
    private func showsShelf(_ world: String) -> Bool {
        guard world == ChristmasWorld.id else { return true }
        return model.progress.christmasEntered
            || model.roster.collectibles.contains { $0.world == world && model.progress.collection.owns($0.id) }
    }
}

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @State private var picking = false
    let title: LocalizedStringKey

    var body: some View {
        HStack {
            IconButton(system: "chevron.left") { model.screen = model.homeScreen }
            Spacer()
            Text(title).font(Theme.title(22)).foregroundStyle(Theme.plum)
            Spacer()
            // The player's avatar is their Buddy.
            if model.buddyActive, let ref = model.progress.buddy.squishy {
                // A tap squashes it and opens the Buddy picker.
                Button {
                    model.haptics.land()
                    picking = true
                } label: {
                    SquishRefView(ref: ref).frame(width: 44, height: 44).background(Circle().fill(.white))
                }
                .buttonStyle(PressSquish())
                .accessibilityLabel(Text("Change Buddy"))
                .accessibilityIdentifier("top-buddy")
                .sheet(isPresented: $picking) {
                    BuddyPickerView { picking = false }.environmentObject(model)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
