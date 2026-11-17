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
            RopeSquishy(room: mode == .room, onTouch: onTouch, onLetGo: onLetGo)
        } else {
            soft
        }
    }

    private var soft: some View {
        let _ = connect()
        let specs = self.specs
        let sim = self.sim(specs)
        return ZStack {
            if let sim { MoveLayer(sim: sim, pulse: holder.pulse, behind: true) }
            SpriteView(scene: holder.scene, options: [.allowsTransparency])
            if let sim { MoveLayer(sim: sim, pulse: holder.pulse, behind: false) }
        }
        .modifier(MoveBodyEffect(specs: specs, pulse: holder.pulse, tricks: onGesture == nil))
            .onAppear { show(drop: true) }
            .onDisappear { holder.scene.goQuiet() }
            .onChange(of: toy) { _, _ in show(drop: true) }
            .onChange(of: look) { _, _ in
                if let image = picture() { holder.scene.redraw(image: image) }
            }
            .onChange(of: reduceMotion) { _, _ in show(drop: false) }
            .onChange(of: pokes) { _, _ in holder.scene.poke() }
            .onChange(of: wiggles) { _, _ in holder.scene.wiggle() }
    }

    /// Keeps the scene's switches and callbacks up to date with the view.
    private func connect() {
        let scene = holder.scene
        let model = self.model
        scene.mode = mode
        scene.comesHome = comesHome
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
    }

    private func picture() -> UIImage? {
        // A move that brings its own part (a hat, a lid) uses the art with that part taken off.
        // Those pictures are drawn on a slightly wider frame than the squishy's own.
        if look == toy, let base = SignatureMoves.shared.baseArt(for: toy) {
            let bare = ImageRenderer(content: Image(base).resizable().frame(width: 320, height: 320)
                .frame(width: 300, height: 300).clipped())
            bare.scale = min(max(displayScale, 1), 3)
            bare.isOpaque = false
            if let image = bare.uiImage { return image }
        }
        let renderer = ImageRenderer(content: art().environmentObject(model).frame(width: 300, height: 300))
        renderer.scale = min(max(displayScale, 1), 3)
        renderer.isOpaque = false
        return renderer.uiImage
    }

    private func show(drop: Bool) {
        connect()
        guard let image = picture() else { return }
        holder.scene.show(image: image, feel: feel, drop: drop)
    }
}
