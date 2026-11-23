import SwiftUI
import SquishPolicy
import SquishSoft

/// Squish Room: squeeze anything you own. No score, timer, reward or ad, so it
/// suits gentle mode. Morph Squad squishies change shape on a squeeze.
struct SquishRoomView: View {
    @EnvironmentObject var model: AppModel
    /// The squishies out in the room, newest last. Empty until one is picked: then it is the first on the shelf.
    @State private var out: [String] = []
    /// What a Morph Squad squishy currently looks like, if it has changed.
    @State private var morphedInto: String?
    @State private var wiggles = 0
    @State private var mood = 0

    private let moods: [(LocalizedStringKey, Color)] = [
        ("Cream", Color("Marshmallow")), ("Night", Color(red: 0.2, green: 0.17, blue: 0.32)), ("Clouds", Color(red: 0.86, green: 0.93, blue: 1)),
    ]

    /// How many can be out at once: two on an iPhone, four on an iPad.
    private var most: Int { UIDevice.current.userInterfaceIdiom == .pad ? 4 : 2 }
    private var shown: [String] { out.isEmpty ? Array(model.squeezables.prefix(1)) : out }
    /// The newest one out: it is named, and it is the one that morphs and does its moves.
    private var current: String? { shown.last }

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
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Squish Room")
            if let id = current {
                // Soft all the way through: knead it, pull it, pinch it, pick it up and throw it.
                SoftSquishy(toy: id, look: morphedInto ?? id, feel: model.feel(for: id), mode: .room, wiggles: wiggles, mates: Array(shown.dropLast()),
                            wear: morphedInto == nil && id == model.progress.buddy.squishy ? model.progress.buddy.worn : [],
                            onLetGo: { depth in morph(depth: depth) }, onDoubleTap: { tickle() }) {
                    SquishRefView(ref: morphedInto ?? id)
                        .colorMultiply(morphedInto == nil ? .white : Color(red: 0.86, green: 0.82, blue: 1))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    // A shiny edition sparkles in the Room too.
                    if morphedInto == nil, model.progress.collection.ownsShiny(id) {
                        ShinyGlitter().frame(width: 230, height: 230)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: model.displayName(for: id)))
                .accessibilityIdentifier("room-squishy")
                .overlay(alignment: .topTrailing) { ClipControl(clips: model.clips, seconds: 8).padding(12) }
                Text(verbatim: model.displayName(for: id)).font(Theme.title(22))
                    .foregroundStyle(mood == 1 ? Color.white : Theme.plum)
                    .padding(.bottom, shown.count == 1 && model.squeezables.count > 1 ? 2 : 10)
                if shown.count == 1, model.squeezables.count > 1 {
                    Text("Tap another squishy to bring it in too")
                        .font(Theme.body(13)).foregroundStyle((mood == 1 ? Color.white : Theme.plum).opacity(0.7))
                        .padding(.bottom, 8)
                }
            } else {
                Spacer()
            }
            // Keepsakes from the worlds' big shows: tap one to watch its show again.
            if !model.progress.keepsakes.isEmpty {
                HStack(spacing: 12) {
                    ForEach(ShowPlan.worlds.filter { model.progress.finalesSeen.contains($0) }, id: \.self) { world in
                        Button { model.showingNews = .finale(world: world) } label: {
                            Text(verbatim: ShowPlan.load(world)?.keepsakeGlyph ?? "🎤").font(.system(size: 30))
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(Color.white.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(ShowPlan.title(world)))
                    }
                }
                .padding(.bottom, 8)
            }
            Picker("Mood", selection: $mood) {
                ForEach(moods.indices, id: \.self) { i in Text(moods[i].0).tag(i) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.squeezables, id: \.self) { item in
                        SquishRefView(ref: item).frame(width: 60, height: 60)
                            // A ring shows which ones are out in the room.
                            .background(Circle().fill(Color.white.opacity(shown.contains(item) ? 0.85 : 0)))
                            .overlay(Circle().stroke(Theme.bubblegum, lineWidth: shown.contains(item) ? 3 : 0))
                            .onTapGesture { pick(item) }
                    }
                }
                .padding(16)
            }
        }
        .background(RoomMood(mood: mood, colour: moods[mood].1).ignoresSafeArea())
        .onAppear {
            // Came here from a "Squeeze me" button: start with that squishy.
            if let start = model.roomStart {
                out = [start]
                model.roomStart = nil
            }
        }
    }

    /// Morph Squad: letting go of a deep squeeze turns it into someone from its own world; the next one turns it back.
    private func morph(depth: Double) {
        guard depth > SquishTuning.standard.morphOverDepth,
              let id = current, model.roster.collectible(id)?.shapeshifter == true else { return }
        morphedInto = morphedInto == nil ? model.morphTarget(for: id)?.id : nil
    }

    private func tickle() {
        model.haptics.reject()
        wiggles += 1
    }
}

/// The room's mood behind the squishy: plain cream, a night sky with stars and a moon, or a
/// daytime sky with clouds drifting by. Nothing here can be touched.
struct RoomMood: View {
    let mood: Int
    let colour: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    /// Fixed spots, so the sky is the same every visit: (x, y, size) as fractions of the room.
    private static let clouds: [(CGFloat, CGFloat, CGFloat)] = [
        (0.18, 0.14, 1.0), (0.74, 0.22, 0.8), (0.40, 0.36, 0.6), (0.86, 0.50, 0.9), (0.12, 0.60, 0.75), (0.58, 0.74, 1.0),
    ]
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.10, 0.10, 5), (0.30, 0.18, 3), (0.52, 0.08, 4), (0.90, 0.30, 5), (0.16, 0.34, 3), (0.42, 0.28, 3),
        (0.64, 0.40, 4), (0.08, 0.52, 4), (0.84, 0.56, 3), (0.28, 0.66, 5), (0.72, 0.72, 3), (0.50, 0.58, 3),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                switch mood {
                case 2:
                    LinearGradient(colors: [Color(red: 0.62, green: 0.82, blue: 1), colour], startPoint: .top, endPoint: .bottom)
                    ForEach(Self.clouds.indices, id: \.self) { i in
                        let c = Self.clouds[i]
                        let reach: CGFloat = w * (i % 2 == 0 ? 0.10 : -0.07)
                        let shift: CGFloat = drift ? reach : -reach
                        cloud(width: w * 0.42 * c.2)
                            .position(x: w * c.0, y: h * c.1)
                            .offset(x: shift)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 9 + Double(i) * 1.7).repeatForever(autoreverses: true), value: drift)
                    }
                case 1:
                    colour
                    ForEach(Self.stars.indices, id: \.self) { i in
                        let s = Self.stars[i]
                        Circle().fill(Color.white)
                            .frame(width: s.2, height: s.2)
                            .opacity((drift && i % 2 == 0) ? 0.35 : 0.9)
                            .position(x: w * s.0, y: h * s.1)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.6 + Double(i % 4) * 0.5).repeatForever(autoreverses: true), value: drift)
                    }
                    Circle().fill(Color(red: 1, green: 0.95, blue: 0.75)).frame(width: 54, height: 54)
                        .overlay(Circle().fill(colour).frame(width: 46, height: 46).offset(x: 14, y: -8))
                        .position(x: w * 0.82, y: h * 0.13)
                default:
                    colour
                }
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { drift = true }
    }

    /// A soft cloud from three bumps on a flat base.
    private func cloud(width: CGFloat) -> some View {
        let h = width * 0.42
        return ZStack {
            Capsule().frame(width: width, height: h * 0.62).offset(y: h * 0.19)
            Circle().frame(width: h * 0.78, height: h * 0.78).offset(x: -width * 0.20, y: -h * 0.02)
            Circle().frame(width: h, height: h).offset(x: width * 0.04, y: -h * 0.16)
            Circle().frame(width: h * 0.66, height: h * 0.66).offset(x: width * 0.26, y: h * 0.04)
        }
        .foregroundStyle(Color.white.opacity(0.92))
        .frame(width: width, height: h * 1.3)
    }
}
