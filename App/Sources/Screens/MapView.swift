import SwiftUI
import SquishLevels

/// World map: the story worlds of the main path, Keep Squishing, plus Santa's Grotto once its door has been opened.
struct MapView: View {
    @EnvironmentObject var model: AppModel

    private var worlds: [(id: String, name: LocalizedStringKey)] { [
        ("toyshop", "Toy Shop"), ("sweetfactory", "Sweet Factory"),
        ("starlight", "Starlight Stage"), ("bubblebath", "Bubble Bath"), ("junglejam", "Jungle Jam"),
        (LevelCatalog.endless, "Keep Squishing"),
        ("christmas", AppModel.christmasWorldName),
    ] }

    /// Keep Squishing is always on the map, so the whole road shows from the first day (its levels
    /// stay locked until the story is done). Santa's Grotto shows once its door has been opened.
    private func shows(_ world: String) -> Bool {
        if world == "christmas" { return model.progress.christmasEntered }
        if world == LevelCatalog.endless { return model.endlessCount > 0 }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Levels")
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        if model.isExtraUnlocked(.squishRoom) {
                            Button { model.open(.squishRoom) } label: { Label("Squish Room", systemImage: "hand.tap.fill") }
                                .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                        }
                        // Under-13s reach the shop only from Settings.
                        if !model.isGentleMode {
                            Button { model.screen = .shop } label: { Label("Shop", systemImage: "bag.fill") }
                                .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                        }
                    }
                    ForEach(worlds.filter { shows($0.id) }, id: \.id) { world in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(world.name).font(Theme.title(22)).foregroundStyle(Theme.plum)
                                // A gold crown stamps a finished world.
                                if world.id != LevelCatalog.endless, model.isWorldComplete(world.id) {
                                    Image("boss-crown").resizable().scaledToFit().frame(height: 22)
                                        .accessibilityIdentifier("world-crown-\(world.id)")
                                }
                                if world.id != LevelCatalog.endless, let left = model.levelsToFinale(world: world.id) {
                                    Text("\(left) to the boss!").font(Theme.body(12)).foregroundStyle(Theme.plum)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(Theme.butter))
                                }
                                Spacer()
                                if world.id != LevelCatalog.endless { starJar(world.id) }
                            }
                            if world.id == LevelCatalog.endless {
                                if model.progress.highestUnlocked >= model.storyLevelCount {
                                    Text("It never runs out. A capsule every fifth level.")
                                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.65))
                                } else {
                                    Text("\(model.endlessCount) more levels. Opens after Jungle Jam.")
                                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.65))
                                        .accessibilityIdentifier("keep-squishing-locked")
                                }
                            }
                            ShowPoster(world: world.id)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                                ForEach(model.levels.indices.filter { model.levels[$0].file.world == world.id }, id: \.self) { i in
                                    levelBubble(i)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .onAppear {
                // Open on the level you are on, not on the top of the list.
                if let here = model.levels.indices.first(where: { isCurrent($0) && !model.isSideLevel($0) }) {
                    proxy.scrollTo(here, anchor: .center)
                }
            }
            }
        }
        .background(Theme.marshmallow.ignoresSafeArea())
    }

    /// The world's star jar: stars earned there, and how many more the next prize needs.
    private func starJar(_ world: String) -> some View {
        let stars = model.stars(inWorld: world)
        let given = model.starJarPrizes(world)
        let goals = model.starJarGoals(world)
        let more = given < 3 ? max(0, goals[given] - stars.earned) : 0
        return VStack(alignment: .trailing, spacing: 2) {
            Label { Text(verbatim: "\(stars.earned)/\(stars.possible)").monospacedDigit() } icon: {
                Image(systemName: "star.fill").foregroundStyle(Theme.butter).shadow(color: Theme.plum.opacity(0.5), radius: 0.5)
            }
            .font(Theme.body(15)).foregroundStyle(Theme.plum)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(Theme.plum.opacity(0.15), lineWidth: 2))
            if given < 3, more > 0 {
                Group {
                    switch given {
                    case 0: Text("\(more) more for coins")
                    case 1: Text("\(more) more for a capsule")
                    default: Text("\(more) more for a golden capsule")
                    }
                }
                .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.7))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The level the player is on: the next one to win on its path.
    private func isCurrent(_ i: Int) -> Bool {
        let sameNext = model.levels.indices.contains(i + 1) && model.isSideLevel(i + 1) == model.isSideLevel(i)
        return model.isUnlocked(i) && model.progress.stars[model.levels[i].id] == nil
            && !(sameNext && model.isUnlocked(i + 1))
    }

    private func levelBubble(_ i: Int) -> some View {
        let unlocked = model.isUnlocked(i)
        let stars = model.progress.stars[model.levels[i].id] ?? 0
        let current = isCurrent(i)
        let boss = model.levels[i].file.beat == .boss
        let finale = boss && model.isFinale(i) && model.levels[i].file.world != LevelCatalog.endless
        let world = model.levels[i].look
        // Three figures need smaller type to stay inside the bubble.
        let number = model.levelNumber(i)
        return Button {
            if unlocked { model.screen = .level(i) }
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: "\(number)").font(Theme.title(number > 999 ? 13 : number > 99 ? 15 : 18)).lineLimit(1)
                if current {
                    Text("Play").font(.system(size: 11, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                } else {
                    Text(String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars))
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(current ? .white : (unlocked ? Theme.plum : Theme.plum.opacity(0.3)))
            .frame(width: 58, height: 58)
            // Only the level you are on is filled with colour. A boss wears a crown instead.
            .background(Circle().fill(current ? Theme.bubblegum : (unlocked ? Color.white : Color.white.opacity(0.4))))
            .overlay(Circle().stroke(finale ? RarityLook.gold : (current ? Theme.plum : .clear), lineWidth: finale ? 4 : 3))
            .overlay(alignment: .top) {
                if finale {
                    // The world's finale: a crown and a BOSS ribbon.
                    VStack(spacing: 0) {
                        Image("boss-crown").resizable().scaledToFit().frame(height: 18)
                        Text("BOSS").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.grape))
                    }
                    .offset(y: -22)
                } else if boss {
                    Text(verbatim: "👑").font(.system(size: 14)).offset(y: -9)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // The giant waits beside its level until it is beaten.
                if finale && stars == 0 {
                    BossGiant(world: world).frame(width: 34, height: 34).offset(x: -12, y: 10).allowsHitTesting(false)
                }
            }
            // The Buddy (or the favourite squishy) sits on the level to play next.
            .overlay(alignment: .topTrailing) {
                if current {
                    SquishRefView(ref: model.progress.buddy.squishy ?? model.progress.favouriteSquishy ?? "peach-bun")
                        .frame(width: 34, height: 34).offset(x: 12, y: -16)
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(finale ? 1.18 : (current ? 1.08 : 1))
        }
        .zIndex(finale ? 1 : 0)
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .id(i)
        .accessibilityIdentifier(current ? "map-current" : "map-level-\(i)")
    }
}
