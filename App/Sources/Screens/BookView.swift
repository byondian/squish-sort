import SwiftUI
import SquishPolicy

/// The collection book: one shelf per world, silhouettes for missing squishies.
struct BookView: View {
    @EnvironmentObject var model: AppModel
    @State private var pressed: String?
    @State private var newOne: Collectible?

    private let worlds: [(id: String, name: LocalizedStringKey)] = [
        ("toyshop", "Toy Shop"), ("sweetfactory", "Sweet Factory"),
        ("starlight", "Starlight Stage"), ("christmas", "Christmas Workshop"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Collection book")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Gentle mode's only place for the bonus capsule (Ian, 16 Nov): calm, never a pop-up.
                    if model.isGentleMode && model.bonusCapsuleWorld != nil && model.canWatchRewarded {
                        Button { model.openBonusCapsule() } label: {
                            Label("Bonus capsule (watch an ad)", systemImage: "play.rectangle.fill")
                        }
                        .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                        .font(Theme.body(15))
                    }
                    ForEach(worlds, id: \.id) { world in
                        shelf(world.id, world.name)
                    }
                    Text("Odds: common 70%, rare 25%, ultra-rare 5%. Squishies are earned by playing and are never sold.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                }
                .padding(16)
            }
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .sheet(item: $newOne) { c in
            VStack(spacing: 12) {
                SquishyView(id: c.id, rarity: c.rarity).frame(width: 180, height: 180)
                Text(c.name).font(Theme.title(26))
                Text("New!").font(Theme.body(18))
            }
            .foregroundStyle(Theme.plum)
            .presentationDetents([.medium])
        }
    }

    private func shelf(_ world: String, _ name: LocalizedStringKey) -> some View {
        let items = model.roster.collectibles.filter { $0.world == world }
        let owned = items.filter { model.progress.collection.owns($0.id) }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name).font(Theme.title(20))
                Spacer()
                Text("\(owned)/\(items.count)").font(Theme.body(15)).opacity(0.7)
            }
            .foregroundStyle(Theme.plum)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items, id: \.id) { c in
                        let has = model.progress.collection.owns(c.id)
                        VStack(spacing: 4) {
                            SquishyView(id: c.id, rarity: c.rarity, silhouette: !has, squash: pressed == c.id ? 1 : 0)
                                .frame(width: 72, height: 72)
                                .overlay { if !has && c.rarity == .secret { Text("?").font(Theme.title(28)).foregroundStyle(Theme.plum.opacity(0.5)) } }
                            Text(has ? c.name : "???").font(Theme.body(11)).lineLimit(1).foregroundStyle(Theme.plum)
                        }
                        .frame(width: 80)
                        .onLongPressGesture(minimumDuration: 5, pressing: { down in
                            guard has else { return }
                            withAnimation(down ? .easeOut(duration: 0.8) : .spring(response: 1.2, dampingFraction: 0.6)) {
                                pressed = down ? c.id : nil
                            }
                        }, perform: {})
                    }
                }
                .padding(.vertical, 8)
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.6)).offset(y: 30).frame(height: 24), alignment: .bottom)
            if model.progress.collection.spareCount >= CapsuleDrops.sparesPerReroll && owned < items.filter({ $0.rarity != .secret }).count {
                Button("Swap 3 spares for a new squishy") { newOne = model.rerollSpares(world: world) }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .font(Theme.body(15))
            }
        }
    }
}

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    let title: LocalizedStringKey

    var body: some View {
        HStack {
            IconButton(system: "chevron.left") { model.screen = .level(model.progress.highestUnlocked) }
            Spacer()
            Text(title).font(Theme.title(22)).foregroundStyle(Theme.plum)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
