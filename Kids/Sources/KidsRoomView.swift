import SwiftUI
import SquishLevels
import SquishPolicy
import SquishSoft

/// The room is the home screen. Everything is a picture, every button is big, and every squishy
/// reacts to a poke. There is no score, no timer, nothing to lose and nothing a child can delete.
struct KidsRoomView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("kids.scene") private var sceneName = KidsScene.playMat.rawValue
    /// The squishies out in the room, newest last.
    @State private var out: [String] = []
    /// Which group of the toy shelf is showing: a world, or "made" for the child's own squishies.
    @State private var tab = AppModel.kidsFreeWorld
    @State private var morphedInto: String?
    @State private var wiggles = 0
    @State private var gate = false
    @State private var grownUps = false

    private static let madeTab = "made"

    private var scene: KidsScene {
        let wanted = KidsScene(rawValue: sceneName) ?? .playMat
        return wanted.isFree || model.ownsRemoveAds ? wanted : .playMat
    }
    /// Two on an iPhone, four on an iPad: each stays big enough to squeeze properly.
    private var most: Int { UIDevice.current.userInterfaceIdiom == .pad ? 4 : 2 }
    /// Everything a child taps is bigger on an iPad, where there is room for it.
    private var big: CGFloat { UIDevice.current.userInterfaceIdiom == .pad ? 1.45 : 1 }
    private var shown: [String] { out.isEmpty ? Array(model.squeezables.prefix(1)) : out.filter { model.squeezables.contains($0) } }
    private var current: String? { shown.last }

    private var shelf: [String] {
        if tab == Self.madeTab { return model.progress.made.map(\.ref) }
        return model.kidsShelf.first { $0.world == tab }?.squishies ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            topRow
            room
            tabs
            toys
        }
        .background(KidsBackdrop(scene: scene).ignoresSafeArea())
        .fullScreenCover(isPresented: $gate) {
            KidsGate(onPass: {
                gate = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { grownUps = true }
            }, onCancel: { gate = false })
        }
        .sheet(isPresented: $grownUps) {
            GrownUpsView().environmentObject(model).environmentObject(model.purchases)
        }
        .onAppear {
            // Back from the Workshop with "Squeeze": that squishy is waiting in the room.
            if let start = model.roomStart {
                out = [start]
                if model.progress.made.contains(where: { $0.ref == start }) { tab = Self.madeTab }
                model.roomStart = nil
            }
        }
    }

    // MARK: - Rooms and the Grown-ups corner

    private var topRow: some View {
        HStack(spacing: 10) {
            ForEach(KidsScene.allCases) { s in
                let open = s.isFree || model.ownsRemoveAds
                Button {
                    // A closed room is a grown-up matter: the gate comes first, never a price.
                    if open { sceneName = s.rawValue } else { gate = true }
                } label: {
                    Image(systemName: s.icon)
                        .font(.system(size: 26 * big, weight: .bold))
                        .foregroundStyle(Theme.plum.opacity(open ? 1 : 0.35))
                        .frame(width: 60 * big, height: 60 * big)
                        .background(Circle().fill(scene == s ? s.tint : Color.white.opacity(0.9)))
                        .overlay(alignment: .bottomTrailing) { if !open { lockBadge } }
                }
                .buttonStyle(PressSquish())
                .accessibilityLabel(Text(s.name))
                .accessibilityIdentifier("kids-scene-\(s.rawValue)")
            }
            Spacer(minLength: 0)
            // Small and out of the way on purpose: it is not for the child.
            Button { gate = true } label: {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.plum.opacity(0.55))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("For grown-ups"))
            .accessibilityIdentifier("kids-grownups")
        }
        .padding(.horizontal, 14).padding(.top, 8)
    }

    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Theme.plum.opacity(0.6)))
    }

    // MARK: - The room

    @ViewBuilder private var room: some View {
        ZStack(alignment: .bottomTrailing) {
            if let id = current {
                SoftSquishy(toy: id, look: morphedInto ?? id, feel: model.feel(for: id), mode: .room, wiggles: wiggles,
                            mates: Array(shown.dropLast()),
                            onLetGo: { depth in morph(depth: depth) },
                            onDoubleTap: { model.haptics.reject(); wiggles += 1 }) {
                    SquishRefView(ref: morphedInto ?? id)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: model.displayName(for: id)))
                .accessibilityIdentifier("room-squishy")
            } else {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // The one big door: into the Workshop to make a new squishy.
            Button { model.screen = .maker } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 40 * big, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 96 * big, height: 96 * big)
                    .background(Circle().fill(Theme.bubblegum))
                    .overlay(Circle().stroke(Color.white, lineWidth: 5))
                    .shadow(color: Theme.plum.opacity(0.2), radius: 6, y: 4)
            }
            .buttonStyle(PressSquish())
            .padding(18)
            .accessibilityLabel(Text("Workshop"))
            .accessibilityIdentifier("kids-door")
        }
    }

    // MARK: - The toy shelf

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.kidsShelf, id: \.world) { group in
                    let face = model.roster.collectibles.first { $0.world == group.world }?.id
                    Button {
                        if group.open { tab = group.world } else { gate = true }
                    } label: {
                        ZStack {
                            if let face { SquishRefView(ref: face).padding(6).opacity(group.open ? 1 : 0.4) }
                        }
                        .frame(width: 56 * big, height: 56 * big)
                        .background(RoundedRectangle(cornerRadius: 18).fill(tab == group.world ? Theme.butter : Color.white.opacity(0.85)))
                        .overlay(alignment: .bottomTrailing) { if !group.open { lockBadge } }
                    }
                    .buttonStyle(PressSquish())
                    .accessibilityLabel(Text(AppModel.worldName(group.world)))
                    .accessibilityIdentifier("kids-tab-\(group.world)")
                }
                if !model.progress.made.isEmpty {
                    Button { tab = Self.madeTab } label: {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 24 * big, weight: .bold)).foregroundStyle(Theme.bubblegum)
                            .frame(width: 56 * big, height: 56 * big)
                            .background(RoundedRectangle(cornerRadius: 18).fill(tab == Self.madeTab ? Theme.butter : Color.white.opacity(0.85)))
                    }
                    .buttonStyle(PressSquish())
                    .accessibilityLabel(Text("Made squishies"))
                    .accessibilityIdentifier("kids-tab-made")
                }
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
    }

    private var toys: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(shelf, id: \.self) { item in
                    Button { pick(item) } label: {
                        SquishRefView(ref: item)
                            .frame(width: 88 * big, height: 88 * big)
                            .background(Circle().fill(Color.white.opacity(shown.contains(item) ? 0.9 : 0.45)))
                            .overlay(Circle().stroke(Theme.bubblegum, lineWidth: shown.contains(item) ? 4 : 0))
                    }
                    .buttonStyle(PressSquish())
                    .accessibilityLabel(Text(verbatim: model.displayName(for: item)))
                    .accessibilityIdentifier("kids-toy-\(item)")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(height: 88 * big + 24)
        .background(Color.white.opacity(0.35))
    }

    /// A tap on the shelf brings that squishy in beside the others; a tap on one that is out puts it away.
    private func pick(_ item: String) {
        var now = shown
        let moves = SignatureMoves.shared
        if let i = now.firstIndex(of: item) {
            guard now.count > 1 else { return }
            now.remove(at: i)
        } else if moves.isRope(item) || now.contains(where: { moves.isRope($0) }) {
            // A long, stretchy squishy needs the room to itself.
            now = [item]
        } else {
            if now.count >= most { now.removeFirst() }
            now.append(item)
        }
        out = now
        morphedInto = nil
        model.haptics.lift()
    }

    /// Morph Squad: letting go of a deep squeeze turns it into someone from its own world; the next one turns it back.
    private func morph(depth: Double) {
        guard depth > SquishTuning.standard.morphOverDepth,
              let id = current, model.roster.collectible(id)?.shapeshifter == true else { return }
        morphedInto = morphedInto == nil ? model.morphTarget(for: id)?.id : nil
    }
}
