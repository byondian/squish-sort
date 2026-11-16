import SwiftUI
import SquishPolicy

/// The collection book: one shelf per world, silhouettes for missing squishies.
struct BookView: View {
    @EnvironmentObject var model: AppModel
    @State private var pressed: String?
    @State private var newOne: Collectible?

    private var worlds: [(id: String, name: LocalizedStringKey)] { [
        ("toyshop", "Toy Shop"), ("sweetfactory", "Sweet Factory"),
        ("starlight", "Starlight Stage"), ("christmas", AppModel.christmasWorldName),
    ] }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Collection book")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(worlds.filter { showsShelf($0.id) }, id: \.id) { world in
                        shelf(world.id, world.name)
                    }
                    if !model.progress.made.isEmpty { madeShelf }
                    Text("Capsule odds: rare \(model.capsuleOddsPercent.rare)%, ultra-rare \(model.capsuleOddsPercent.ultra)%. Common squishies join when you sort a jar of them. Squishies are earned by playing and are never sold.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                    Text("The golden capsule for filling a world's star jar always holds an ultra-rare.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                }
                .padding(16)
            }
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .sheet(item: $newOne) { c in
            VStack(spacing: 12) {
                SquishyView(id: c.id, rarity: c.rarity).frame(width: 180, height: 180)
                Text(verbatim: c.name(in: model.language)).font(Theme.title(26))
                Text("New!").font(Theme.body(18))
            }
            .foregroundStyle(Theme.plum)
            .presentationDetents([.medium])
        }
    }

    /// Squishies from the Maker have their own page at the end. A tap squeezes one.
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
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.6)).offset(y: 30).frame(height: 24), alignment: .bottom)
        }
        .accessibilityIdentifier("book-made")
    }

    /// The Christmas shelf appears once the festive door has been opened (or something from it is owned).
    private func showsShelf(_ world: String) -> Bool {
        guard world == ChristmasWorld.id else { return true }
        return model.progress.christmasEntered
            || model.roster.collectibles.contains { $0.world == world && model.progress.collection.owns($0.id) }
    }

    private func shelf(_ world: String, _ name: LocalizedStringKey) -> some View {
        let items = model.roster.collectibles.filter { $0.world == world }
        let owned = items.filter { model.progress.collection.owns($0.id) }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name).font(Theme.title(20))
                // A gold badge once every level of the world is finished.
                if model.isWorldComplete(world) {
                    Image(systemName: "rosette").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 0.93, green: 0.69, blue: 0.13))
                        .accessibilityIdentifier("world-badge-\(world)")
                }
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
                            Text(verbatim: has ? c.name(in: model.language) : "???").font(Theme.body(11)).lineLimit(1).foregroundStyle(Theme.plum)
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
