import SwiftUI
import SpriteKit
import SquishSoft
import SquishPolicy

/// A squishy that is soft all the way through: a finger makes a dent where it
/// touches and the rest gives way around it. Used in the Squish Room, for the
/// Buddy, the capsule reveal and the Maker preview.
@MainActor
struct SoftSquishy<Art: View>: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    /// Changes when it is a different toy: a new body is made.
    let toy: String
    /// Changes when the same toy only looks different: the body carries on.
    let look: String
    let feel: SquishFeel
    var mode = SoftSquishyScene.Mode.pressOnly
    /// Add one to press the toy from the app (a treat, a pat).
    var pokes = 0
    /// Add one for a quick shake.
    var wiggles = 0
    /// Slides back to the middle after being thrown (the Buddy on Home).
    var comesHome = false
    /// Other squishies out in the room with this one (Squish Room only). They can be squeezed and thrown
    /// too, and they bump into each other. The signature moves and the callbacks belong to `toy`.
    var mates: [String] = []
    /// The room's air and bounce (Squishy Workshop's rooms). See `SoftSquishyScene`.
    var gravityScale = 1.0
    var bounce: Double?
    /// Gifts this toy has on (the Buddy's hat, scarf and so on). They are part of its picture, so they squish with it.
    var wear: [BuddyGift] = []
    var onTouch: (() -> Void)?
    var onLetGo: ((Double) -> Void)?
    var onDoubleTap: (() -> Void)?
    var onGesture: ((TrickGesture) -> Bool)?
    @ViewBuilder var art: () -> Art
    @StateObject private var holder = Holder()

    final class Holder: ObservableObject {
        let scene = SoftSquishyScene()
        let pulse = MovePulse()
        var sim: MoveSim?
        /// The toys last handed to the scene, so only a new arrival drops in.
        var shown: Set<String> = []
        /// The other toys' own moves and where each one is.
        var mateSims: [String: MoveSim] = [:]
        var matePulses: [String: MovePulse] = [:]
    }

    /// The other toys out in the room that are drawn by this scene.
    private var roomMates: [String] {
        guard mode == .room else { return [] }
        var seen = Set([toy])
        return mates.filter { !SignatureMoves.shared.isRope($0) && seen.insert($0).inserted }
    }

    /// Each mate's own moves (sparkles, limbs, glow), drawn where that mate is.
    private func mateLayers() -> [String] {
        let ids = roomMates
        holder.mateSims = holder.mateSims.filter { ids.contains($0.key) }
        holder.matePulses = holder.matePulses.filter { ids.contains($0.key) }
        var with: [String] = []
        for id in ids {
            let specs = SignatureMoves.shared.moves(for: id)
            guard !specs.isEmpty else { continue }
            if holder.mateSims[id] == nil { holder.mateSims[id] = MoveSim(id: id, specs: specs) }
            if holder.matePulses[id] == nil { holder.matePulses[id] = MovePulse() }
            with.append(id)
        }
        return with
    }

    private func trick(of id: String) -> String? {
        SignatureMoves.shared.moves(for: id).first { $0.effect == "TRICK" }.map { $0.str("trick") ?? "hop" }
    }

    /// The squishy's own signature moves. A morphed look has none.
    private var specs: [MoveSpec] { look == toy ? SignatureMoves.shared.moves(for: toy) : [] }

    private func sim(_ specs: [MoveSpec]) -> MoveSim? {
        guard !specs.isEmpty else {
            holder.sim = nil
            return nil
        }
        if holder.sim?.id != toy { holder.sim = MoveSim(id: toy, specs: specs) }
        return holder.sim
    }

    var body: some View {
        if look == toy, SignatureMoves.shared.isRope(toy) {
            // A long squishy is a rope, not a blob: pull it out straight and it coils back.
            RopeSquishy(room: mode == .room, onTouch: onTouch, onLetGo: onLetGo, onDoubleTap: onDoubleTap, onGesture: onGesture)
        } else {
            soft
        }
    }

    private var soft: some View {
        let _ = connect()
        let specs = self.specs
        let sim = self.sim(specs)
        let layered = mateLayers()
        let together = !roomMates.isEmpty
        return ZStack {
            if let sim { MoveLayer(sim: sim, pulse: holder.pulse, behind: true) }
            ForEach(layered, id: \.self) { id in
                if let sim = holder.mateSims[id], let pulse = holder.matePulses[id] { MoveLayer(sim: sim, pulse: pulse, behind: true) }
            }
            SpriteView(scene: holder.scene, options: [.allowsTransparency])
            if let sim { MoveLayer(sim: sim, pulse: holder.pulse, behind: false) }
            ForEach(layered, id: \.self) { id in
                if let sim = holder.mateSims[id], let pulse = holder.matePulses[id] { MoveLayer(sim: sim, pulse: pulse, behind: false) }
            }
        }
        // The puff, spin and flip turn the whole view, so they are for a toy on its own.
        // With several out, each toy does its trick inside the scene instead.
        .modifier(MoveBodyEffect(specs: together ? [] : specs, pulse: holder.pulse, tricks: onGesture == nil))
            .onAppear { show(drop: true) }
            .onDisappear { holder.scene.goQuiet() }
            .onChange(of: toy) { _, _ in show(drop: true) }
            .onChange(of: mates) { _, _ in show(drop: true) }
            .onChange(of: look) { _, _ in
                if let image = picture() { holder.scene.redraw(image: image) }
            }
            .onChange(of: reduceMotion) { _, _ in show(drop: false) }
            .onChange(of: wear) { _, _ in show(drop: false) }
            .onChange(of: pokes) { _, _ in holder.scene.poke() }
            .onChange(of: wiggles) { _, _ in holder.scene.wiggle() }
    }

    /// Keeps the scene's switches and callbacks up to date with the view.
    private func connect() {
        let scene = holder.scene
        let model = self.model
        scene.mode = mode
        scene.comesHome = comesHome
        scene.gravityScale = gravityScale
        scene.bounce = bounce
        scene.reduceMotion = reduceMotion
        scene.sounds = model.sounds.squish
        scene.haptics = model.haptics.squish
        // UI tests run on machines with no speaker: leave the audio engine alone there.
        scene.soundOn = { model.sounds.enabled && model.sounds.squishOn && !AppModel.isUITesting }
        scene.hapticsOn = { model.haptics.enabled }
        scene.onTouch = onTouch
        scene.onLetGo = onLetGo
        scene.onDoubleTap = onDoubleTap
        scene.onGesture = onGesture
        let pulse = holder.pulse
        scene.onPulse = specs.isEmpty ? nil : { pulse.take($0) }
        let box = self.holder
        scene.onMatePulse = mode == .room ? { id, next in box.matePulses[id]?.take(next) } : nil
    }

    private func picture() -> UIImage? {
        // A move that brings its own part (a hat, a lid) uses the art with that part taken off.
        // Those pictures are drawn on a slightly wider frame than the squishy's own.
        if look == toy, let base = SignatureMoves.shared.baseArt(for: toy) {
            let bare = ImageRenderer(content: Image(base).resizable().frame(width: 320, height: 320)
                .frame(width: 300, height: 300).clipped().overlay(BuddyWearView(worn: wear)))
            bare.scale = min(max(displayScale, 1), 3)
            bare.isOpaque = false
            if let image = bare.uiImage { return image }
        }
        let renderer = ImageRenderer(content: art().environmentObject(model).frame(width: 300, height: 300)
            .overlay(BuddyWearView(worn: wear)))
        renderer.scale = min(max(displayScale, 1), 3)
        renderer.isOpaque = false
        return renderer.uiImage
    }

    private func matePicture(_ ref: String) -> UIImage? {
        let renderer = ImageRenderer(content: SquishRefView(ref: ref).environmentObject(model).frame(width: 300, height: 300))
        renderer.scale = min(max(displayScale, 1), 3)
        renderer.isOpaque = false
        return renderer.uiImage
    }

    private func show(drop: Bool) {
        connect()
        guard let image = picture() else { return }
        guard mode == .room else {
            holder.scene.show(image: image, feel: feel, drop: drop)
            return
        }
        var toys = [SoftSquishyScene.Toy(id: toy, image: image, feel: feel, trick: look == toy ? trick(of: toy) : nil)]
        // A long squishy is a rope with a view of its own, so it is never one of several.
        for mate in mates where mate != toy && !SignatureMoves.shared.isRope(mate) && !toys.contains(where: { $0.id == mate }) {
            if let art = matePicture(mate) { toys.append(SoftSquishyScene.Toy(id: mate, image: art, feel: model.feel(for: mate), trick: trick(of: mate))) }
        }
        let ids = Set(toys.map(\.id))
        holder.scene.show(toys: toys, fresh: ids.subtracting(holder.shown), drop: drop)
        holder.shown = ids
    }
}

/// What the Buddy has on, drawn over its picture: a hat on its head, something round its neck,
/// something held at its side. The pictures are the Workshop's own parts.
struct BuddyWearView: View {
    let worn: [BuddyGift]

    /// Where a gift from each tray sits on a squishy's picture and how big it is (shares of the picture's side).
    static func spot(_ category: String) -> (x: CGFloat, y: CGFloat, size: CGFloat) {
        switch category {
        case BuddyGifts.hats: return (0.5, 0.13, 0.46)
        case BuddyGifts.neck: return (0.5, 0.8, 0.42)
        default: return (0.13, 0.62, 0.36)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(worn) { gift in
                    if let image = WorkshopArt.part(gift.category, gift.part) {
                        let spot = BuddyWearView.spot(gift.category)
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: side * spot.size, height: side * spot.size)
                            .position(x: geo.size.width / 2 + side * (spot.x - 0.5), y: geo.size.height / 2 + side * (spot.y - 0.5))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
