import SwiftUI

/// World map: the four worlds and their levels with stars.
struct MapView: View {
    @EnvironmentObject var model: AppModel

    private let worlds: [(id: String, name: LocalizedStringKey)] = [
        ("toyshop", "Toy Shop"), ("sweetfactory", "Sweet Factory"),
        ("starlight", "Starlight Stage"), ("christmas", "Christmas Workshop"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Levels")
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
                    ForEach(worlds, id: \.id) { world in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(world.name).font(Theme.title(22)).foregroundStyle(Theme.plum)
                            if !model.config.isWorldUnlocked(world.id, today: model.today) {
                                Text("Opens 18 December").font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.6))
                            }
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
        }
        .background(Theme.marshmallow.ignoresSafeArea())
    }

    private func levelBubble(_ i: Int) -> some View {
        let unlocked = model.isUnlocked(i)
        let stars = model.progress.stars[model.levels[i].id] ?? 0
        return Button {
            if unlocked { model.screen = .level(i) }
        } label: {
            VStack(spacing: 2) {
                Text("\(i + 1)").font(Theme.title(18))
                Text(String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars))
                    .font(.system(size: 10))
            }
            .foregroundStyle(unlocked ? Theme.plum : Theme.plum.opacity(0.3))
            .frame(width: 58, height: 58)
            .background(Circle().fill(unlocked ? (model.levels[i].file.beat == .boss ? Theme.butter : Color.white) : Color.white.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}
