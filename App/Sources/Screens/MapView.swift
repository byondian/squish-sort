import SwiftUI

/// World map: the three worlds of the main path, plus Santa's Grotto once its door has been opened.
struct MapView: View {
    @EnvironmentObject var model: AppModel

    private var worlds: [(id: String, name: LocalizedStringKey)] { [
        ("toyshop", "Toy Shop"), ("sweetfactory", "Sweet Factory"),
        ("starlight", "Starlight Stage"), ("christmas", AppModel.christmasWorldName),
    ] }

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
                    ForEach(worlds.filter { $0.id != "christmas" || model.progress.christmasEntered }, id: \.id) { world in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(world.name).font(Theme.title(22)).foregroundStyle(Theme.plum)
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
        return Button {
            if unlocked { model.screen = .level(i) }
        } label: {
            VStack(spacing: 2) {
                Text("\(model.levelNumber(i))").font(Theme.title(18))
                if current {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                } else {
                    Text(String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars))
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(current ? .white : (unlocked ? Theme.plum : Theme.plum.opacity(0.3)))
            .frame(width: 58, height: 58)
            // Only the level you are on is filled with colour. A boss wears a crown instead.
            .background(Circle().fill(current ? Theme.bubblegum : (unlocked ? Color.white : Color.white.opacity(0.4))))
            .overlay(Circle().stroke(current ? Theme.plum : .clear, lineWidth: 3))
            .overlay(alignment: .top) {
                if boss { Text(verbatim: "👑").font(.system(size: 14)).offset(y: -9) }
            }
            .scaleEffect(current ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .id(i)
        .accessibilityIdentifier(current ? "map-current" : "map-level-\(i)")
    }
}
