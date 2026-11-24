import SwiftUI
import SquishPolicy

/// A world's big show (Content/finales/<world>.json): when its sneak peeks come, its music and
/// the timed steps of the finale. One player draws every world's show from this.
struct ShowPlan: Decodable {
    struct Step: Decodable {
        let at: Double
        let act: String
        let who: Int?
    }

    /// stage (Starlight), parade (Toy Shop), bake (Sweet Factory), sleigh (Santa's Grotto),
    /// swim (Bubble Bath), treetop (Jungle Jam), launch (Space Station) or lab (Morph Lab).
    let style: String
    let music: String
    /// The sneak peeks' music is this plus their number.
    let teaserMusic: String
    let teaserLevels: [Int]
    let keepsake: String
    let steps: [Step]

    private static var cache: [String: ShowPlan] = [:]
    private static var missing: Set<String> = []

    static let worlds = ["toyshop", "sweetfactory", "starlight", "bubblebath", "junglejam", "spacestation", "morphlab", "christmas"]

    static func load(_ world: String) -> ShowPlan? {
        if let plan = cache[world] { return plan }
        if missing.contains(world) { return nil }
        guard let url = Bundle.main.url(forResource: world, withExtension: "json", subdirectory: "Content/finales"),
              let data = try? Data(contentsOf: url),
              let plan = try? JSONDecoder().decode(ShowPlan.self, from: data) else {
            missing.insert(world)
            return nil
        }
        cache[world] = plan
        return plan
    }

    func time(_ act: String, who: Int? = nil) -> Double {
        steps.first { $0.act == act && (who == nil || $0.who == who) }?.at ?? 1_000
    }

    var length: Double { time("end") < 1_000 ? time("end") : 25 }

    var keepsakeGlyph: String {
        switch keepsake {
        case "drum": return "🥁"
        case "cake": return "🎂"
        case "globe": return "❄️"
        case "duck": return "⛲"
        case "bongo": return "🪘"
        case "rocket": return "🚀"
        case "flask": return "🧪"
        default: return "🎤"
        }
    }

    static func title(_ world: String) -> LocalizedStringKey {
        switch world {
        case "toyshop": return "Midnight Toy Parade"
        case "sweetfactory": return "Grand Bake-Off"
        case "christmas": return "Sleigh Night"
        case "bubblebath": return "Bubble Ballet"
        case "junglejam": return "Treetop Jam Session"
        case "spacestation": return "Launch Night"
        case "morphlab": return "The Big Experiment"
        default: return "Encore Concert"
        }
    }
}

/// Plays a world's finale (25 seconds, after its WORLD COMPLETE card) or one of its three-second
/// sneak peeks. Everything on screen is worked out from the time since it began, so a skip or a
/// replay needs no clean-up. No ads before, in or after it, no coins, nothing to lose by skipping.
struct WorldShowView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let world: String
    /// The sneak peek's number, or nil for the finale.
    let teaser: Int?
    @State private var start = Date()
    @State private var ended = false
    @State private var canSkip = false
    @State private var closed = false

    private enum Act { case hop, spin, glow, burst(String) }

    private var plan: ShowPlan? { ShowPlan.load(world) }
    private var cast: [String] { Array(model.roster.world(world, .common).map(\.id).prefix(6)) }
    private var backing: [Collectible] {
        let all = model.roster.world(world, .rare) + model.roster.world(world, .ultra)
        return Array(all.filter { model.progress.collection.owns($0.id) }.prefix(8))
    }
    private var music: String {
        guard let plan else { return "" }
        if let teaser { return plan.teaserMusic + String(teaser) }
        return plan.music
    }
    private static let lights: [Color] = [Theme.bubblegum, Theme.butter, Theme.mint, Theme.sky, Theme.grape, Theme.bubblegum]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: ended)) { timeline in
                let t: Double = ended ? (plan?.length ?? 25) : timeline.date.timeIntervalSince(start)
                if teaser != nil {
                    peek(t, geo.size)
                } else {
                    finale(t, geo.size)
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { if let teaser { peekLabel(teaser) } }
        .overlay(alignment: .topTrailing) {
            if teaser == nil, canSkip, !ended {
                Button("Skip") { end() }
                    .buttonStyle(SquishButtonStyle(fill: Color.white.opacity(0.25)))
                    .padding(16)
                    .accessibilityIdentifier("show-skip")
            }
        }
        .overlay { if ended { closing } }
        .overlay(alignment: .topLeading) {
            if !ended { ClipControl(clips: model.clips, markOnly: true).padding(16) }
        }
        .contentShape(Rectangle())
        .onTapGesture { if teaser != nil { close() } }
        .task { await run() }
        .accessibilityIdentifier("world-show")
    }

    // MARK: - Timing

    @MainActor
    private func run() async {
        guard let plan else { close(); return }
        model.sounds.stopMusic(fade: 0.3)
        model.sounds.play(music)
        func wait(_ seconds: Double) async -> Bool {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return !Task.isCancelled && !closed && !ended
        }
        if teaser != nil {
            model.haptics.lift()
            if await wait(3.2) { close() }
            return
        }
        // The count in: three, two, one.
        for _ in 0..<2 {
            model.haptics.lift()
            guard await wait(1) else { return }
        }
        model.haptics.lift()
        canSkip = true
        let finish = plan.time("finish")
        guard await wait(max(0, finish - 2)) else { return }
        model.haptics.win()
        guard await wait(max(0, plan.length - finish)) else { return }
        end()
    }

    /// The finale is over (or skipped): the closing card, with the keepsake the first time.
    private func end() {
        guard !ended else { return }
        model.sounds.stop(music)
        withAnimation(.easeOut(duration: 0.3)) { ended = true }
    }

    private func replay() {
        ended = false
        canSkip = false
        start = Date()
        Task { await run() }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        model.sounds.stop(music)
        model.newsRead()
    }

    // MARK: - Small sums

    private func ramp(_ t: Double, from: Double, over: Double) -> Double {
        max(0, min(1, (t - from) / max(0.001, over)))
    }

    private func act(for id: String) -> Act {
        guard let spec = SignatureMoves.shared.moves(for: id).first else { return .hop }
        switch spec.effect {
        case "TRICK": return spec.str("trick") == "spin" && !reduceMotion ? .spin : .hop
        case "GLOW": return .glow
        case "SOUND": return .burst("♪")
        case "BURST":
            switch spec.str("particle") ?? "" {
            case "hearts": return .burst("♥")
            case "notes": return .burst("♪")
            default: return .burst("✦")
            }
        default: return .hop
        }
    }

    private func backdrop(_ style: String) -> [Color] {
        switch style {
        case "parade": return [Color(red: 0.10, green: 0.10, blue: 0.28), Color(red: 0.30, green: 0.18, blue: 0.42)]
        case "bake": return [Color(red: 0.36, green: 0.16, blue: 0.30), Color(red: 0.62, green: 0.30, blue: 0.42)]
        case "sleigh": return [Color(red: 0.05, green: 0.10, blue: 0.26), Color(red: 0.16, green: 0.26, blue: 0.48)]
        case "swim": return [Color(red: 0.05, green: 0.28, blue: 0.44), Color(red: 0.24, green: 0.60, blue: 0.74)]
        case "treetop": return [Color(red: 0.04, green: 0.16, blue: 0.14), Color(red: 0.14, green: 0.38, blue: 0.24)]
        case "launch": return [Color(red: 0.07, green: 0.06, blue: 0.20), Color(red: 0.24, green: 0.21, blue: 0.44)]
        case "lab": return [Color(red: 0.06, green: 0.24, blue: 0.22), Color(red: 0.20, green: 0.50, blue: 0.44)]
        default: return [Color(red: 0.09, green: 0.06, blue: 0.20), Color(red: 0.26, green: 0.14, blue: 0.42)]
        }
    }

    // MARK: - One performer

    /// A squishy doing its move. `u` runs from 0 to 1 over its solo; outside a solo it is 0.
    private func performer(_ id: String, rarity: Rarity = .common, side: Double, u: Double, jump: Double) -> some View {
        let bump: Double = u > 0 ? sin(Double.pi * u) : 0
        let kind = act(for: id)
        var dy: Double = -jump
        var turn: Double = 0
        var glow: Double = 0
        var glyph: String?
        switch kind {
        case .hop: dy -= abs(sin(u * Double.pi * 4)) * side * 0.3 * (u > 0 ? 1 : 0)
        case .spin: turn = min(1, u * 2) * 360
        case .glow: glow = bump
        case .burst(let g):
            glyph = g
            dy -= abs(sin(u * Double.pi * 2)) * side * 0.15 * (u > 0 ? 1 : 0)
        }
        let scale: Double = 1 + 0.3 * bump
        return ZStack {
            if glow > 0.02 {
                Circle().fill(Theme.butter.opacity(0.55 * glow)).frame(width: side * 1.5, height: side * 1.5).blur(radius: 14)
            }
            SquishyView(id: id, rarity: rarity).frame(width: side, height: side)
                .rotationEffect(.degrees(turn))
                .scaleEffect(scale, anchor: .bottom)
            if let glyph, u > 0 {
                ForEach(0..<5, id: \.self) { k in
                    let rise: Double = side * (0.5 + u * (0.7 + 0.12 * Double(k)))
                    Text(verbatim: glyph).font(.system(size: side * 0.3, weight: .bold))
                        .foregroundStyle(WorldShowView.lights[k % WorldShowView.lights.count])
                        .offset(x: (Double(k) - 2) * side * 0.3, y: -rise)
                        .opacity(1 - u)
                }
            }
        }
        .offset(y: dy)
    }

    private func spotlight(x: Double, floor: Double, side: Double, strength: Double) -> some View {
        var beam = Path()
        beam.move(to: CGPoint(x: x - 14, y: 0))
        beam.addLine(to: CGPoint(x: x + 14, y: 0))
        beam.addLine(to: CGPoint(x: x + side * 0.9, y: floor + side * 0.1))
        beam.addLine(to: CGPoint(x: x - side * 0.9, y: floor + side * 0.1))
        beam.closeSubpath()
        return ZStack {
            beam.fill(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
            Ellipse().fill(Color.white.opacity(0.22))
                .frame(width: side * 1.9, height: side * 0.36)
                .position(x: x, y: floor + side * 0.1)
        }
        .opacity(strength)
        .allowsHitTesting(false)
    }

    /// The front row: little fans with lightsticks. They sway, and the sticks go up for a cheer.
    private func crowd(_ t: Double, _ size: CGSize, cheer: Double) -> some View {
        let n = 9
        let w = Double(size.width)
        return ZStack {
            ForEach(0..<n, id: \.self) { i in
                let x: Double = w * (Double(i) + 0.5) / Double(n)
                let sway: Double = reduceMotion ? 0 : sin(t * 2 + Double(i) * 0.9)
                let bob: Double = reduceMotion ? 0 : abs(sin(t * 6 + Double(i))) * 5 * cheer
                ZStack(alignment: .top) {
                    Capsule().fill(WorldShowView.lights[i % WorldShowView.lights.count])
                        .frame(width: 5, height: 20)
                        .rotationEffect(.degrees(sway * 14 * (1 - cheer)), anchor: .bottom)
                        .offset(x: 12, y: -14 - 8 * cheer)
                    RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.55))
                        .frame(width: 34, height: 44)
                }
                .position(x: x, y: Double(size.height) - 12 - bob)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - The sneak peek

    private func peek(_ t: Double, _ size: CGSize) -> some View {
        let w = Double(size.width), h = Double(size.height)
        let style = plan?.style ?? "stage"
        let who = cast.isEmpty ? "" : cast[((teaser ?? 1) - 1) % cast.count]
        let side: Double = min(w * 0.4, 170)
        let floor: Double = h * 0.6
        let u: Double = ramp(t, from: 0.3, over: 2.6)
        let arrive: Double = ramp(t, from: 0, over: 0.35)
        // Each world brings its performer on in its own way.
        let slide: Double = style == "parade" ? (1 - arrive) * -w * 0.6 : 0
        let rise: Double = style == "bake" ? (1 - arrive) * side : 0
        let float: Double = (style == "sleigh" || style == "swim") && !reduceMotion ? sin(t * 2.4) * 8 : 0
        // Bubble Bath floats up in a bubble; Jungle Jam drops in from the treetops.
        let bubbleUp: Double = style == "swim" ? (1 - arrive) * h * 0.4 : 0
        let dropIn: Double = style == "treetop" ? (1 - arrive) * -h * 0.5 : 0
        let y: Double = floor - side / 2 + rise + float + bubbleUp + dropIn
        return ZStack {
            LinearGradient(colors: backdrop(style), startPoint: .top, endPoint: .bottom)
            spotlight(x: w / 2, floor: floor, side: side, strength: arrive)
            if !who.isEmpty {
                performer(who, side: side, u: u > 0 && u < 1 ? u : 0, jump: 0)
                    .opacity(arrive)
                    .position(x: w / 2 + slide, y: y)
            }
            if style == "swim", !who.isEmpty {
                Circle().stroke(Color.white.opacity(0.7), lineWidth: 3)
                    .background(Circle().fill(Color.white.opacity(0.12)))
                    .frame(width: side * 1.4, height: side * 1.4)
                    .opacity(arrive)
                    .position(x: w / 2, y: y)
                    .allowsHitTesting(false)
            }
            crowd(t, size, cheer: ramp(t, from: 2.4, over: 0.3))
        }
    }

    private func peekLabel(_ number: Int) -> some View {
        let total = plan?.teaserLevels.count ?? number
        return Group {
            if world == "starlight" {
                Text("Rehearsal \(number) of \(total)")
            } else {
                Text("Sneak peek \(number) of \(total)")
            }
        }
        .font(Theme.title(18)).foregroundStyle(Theme.plum)
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Capsule().fill(Theme.butter))
        .padding(.top, 70)
        .accessibilityIdentifier("show-peek")
    }

    // MARK: - The finale

    private func finale(_ t: Double, _ size: CGSize) -> some View {
        let w = Double(size.width), h = Double(size.height)
        let plan = self.plan
        let style = plan?.style ?? "stage"
        let open: Double = plan?.time("open") ?? 3
        let backingAt: Double = plan?.time("backing") ?? 17
        let finishAt: Double = plan?.time("finish") ?? 21
        let cast = self.cast
        let n = max(1, cast.count)
        let side: Double = min(w * 0.86 / Double(n), 92)
        let floor: Double = h * (style == "sleigh" ? 0.52 : 0.64)
        let lit: Double = ramp(t, from: open, over: 1.2)
        let finishing: Double = t - finishAt
        let jump: Double = finishing > 0 && !reduceMotion ? abs(sin(finishing * Double.pi * 1.5)) * side * 0.45 * max(0, 1 - finishing / 4) : 0
        let float: Double = style == "sleigh" && !reduceMotion ? sin(t * 1.3) * 10 : 0
        // Who is in the spotlight now, and how far through their two seconds.
        var solo = -1
        var soloU: Double = 0
        for i in 0..<n {
            let at: Double = plan?.time("solo", who: i) ?? (5 + 2 * Double(i))
            if t >= at, t < at + 2 { solo = i; soloU = (t - at) / 2 }
        }
        let cheer: Double = max(ramp(t, from: finishAt, over: 0.3), soloU > 0.8 ? 1 : 0, t < open ? 0.6 : 0)
        let extras = backing
        return ZStack {
            LinearGradient(colors: backdrop(style), startPoint: .top, endPoint: .bottom)
            props(style, t, size, open: open, finishAt: finishAt, floor: floor, side: side)
            // The backing line: the rares and ultras already found, on risers behind.
            ForEach(Array(extras.enumerated()), id: \.element.id) { i, item in
                let m = max(1, extras.count)
                let x: Double = w / 2 + (Double(i) - Double(m - 1) / 2) * min(side * 0.95, w * 0.9 / Double(m))
                let up: Double = ramp(t, from: backingAt + 0.25 * Double(i), over: 0.35)
                let sway: Double = reduceMotion ? 0 : sin(t * 4 + Double(i)) * 5
                performer(item.id, rarity: item.rarity, side: side * 0.8, u: 0, jump: jump * 0.8)
                    .scaleEffect(up, anchor: .bottom)
                    .rotationEffect(.degrees(sway), anchor: .bottom)
                    .position(x: x, y: floor - side * 1.25 + float)
            }
            if solo >= 0 {
                let sx: Double = w / 2 + (Double(solo) - Double(n - 1) / 2) * side
                spotlight(x: sx, floor: floor + float, side: side, strength: sin(Double.pi * soloU))
            }
            ForEach(Array(cast.enumerated()), id: \.element) { i, id in
                let x: Double = w / 2 + (Double(i) - Double(n - 1) / 2) * side
                // The parade marches in, the bakers pop out on their turn, the rest step up as the lights come on.
                let turnAt: Double = plan?.time("solo", who: i) ?? open
                let arrive: Double = style == "bake" ? ramp(t, from: turnAt - 0.2, over: 0.3) : ramp(t, from: open + 0.15 * Double(i), over: 0.5)
                let march: Double = style == "parade" ? (1 - ramp(t, from: open, over: 2)) * -w : 0
                let bob: Double = reduceMotion ? 0 : sin(t * 3 + Double(i)) * 2
                performer(id, side: side * 0.92, u: i == solo ? soloU : 0, jump: jump)
                    .scaleEffect(style == "parade" ? 1 : arrive, anchor: .bottom)
                    .position(x: x + march, y: floor - side / 2 + bob + float)
            }
            crowd(t, size, cheer: cheer)
            if t < open {
                // Lights down, and the count in.
                Text(verbatim: "\(max(1, Int(open) - Int(t)))")
                    .font(Theme.title(110)).foregroundStyle(.white)
                    .scaleEffect(1.25 - 0.25 * (t - Double(Int(t))))
                    .position(x: w / 2, y: h * 0.4)
            } else if t < open + 2.2 {
                Text(ShowPlan.title(world))
                    .font(Theme.title(30)).foregroundStyle(Theme.butter)
                    .opacity(min(lit, ramp(open + 2.2 - t, from: 0, over: 0.4)))
                    .position(x: w / 2, y: h * 0.2)
            }
            if t >= finishAt, !ended {
                Confetti(count: 90, seconds: 4).allowsHitTesting(false)
            }
        }
    }

    /// What stands behind the cast: each world's own set, in plain shapes.
    @ViewBuilder
    private func props(_ style: String, _ t: Double, _ size: CGSize, open: Double, finishAt: Double, floor: Double, side: Double) -> some View {
        let w = Double(size.width), h = Double(size.height)
        let lit: Double = ramp(t, from: open, over: 1.5)
        switch style {
        case "parade":
            // The shop at midnight: the sign lights up and the floor is a long rug.
            RoundedRectangle(cornerRadius: 16).fill(Theme.butter.opacity(0.25 + 0.75 * lit))
                .overlay(Text(verbatim: "★  ★  ★").font(Theme.title(22)).foregroundStyle(Theme.plum.opacity(0.4 + 0.6 * lit)))
                .frame(width: w * 0.6, height: 50)
                .position(x: w / 2, y: h * 0.12)
            RoundedRectangle(cornerRadius: 18).fill(Theme.bubblegum.opacity(0.45))
                .frame(width: w * 1.1, height: side * 0.5)
                .position(x: w / 2, y: floor + side * 0.12)
        case "bake":
            // The cake builds itself layer by layer; the candles light for the finish.
            ForEach(0..<3, id: \.self) { k in
                let up: Double = ramp(t, from: open + 0.5 * Double(k), over: 0.4)
                let width: Double = w * (0.86 - 0.2 * Double(k))
                RoundedRectangle(cornerRadius: 18)
                    .fill(k == 1 ? Theme.butter : Color(red: 1, green: 0.84, blue: 0.9))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.8), lineWidth: 5))
                    .frame(width: width, height: side * 0.8)
                    .scaleEffect(x: 1, y: up, anchor: .bottom)
                    .position(x: w / 2, y: floor - side * 0.2 - side * 0.8 * Double(k))
            }
            ForEach(0..<5, id: \.self) { k in
                let glow: Double = ramp(t, from: finishAt + 0.1 * Double(k), over: 0.3)
                Circle().fill(Theme.butter.opacity(0.2 + 0.8 * glow))
                    .frame(width: 12, height: 12)
                    .shadow(color: Theme.butter.opacity(glow), radius: 8)
                    .position(x: w / 2 + (Double(k) - 2) * w * 0.08, y: floor - side * 2.25)
            }
        case "swim":
            // A giant tub: fountain jets in time, bubbles, a line of rubber ducks, and a rainbow for the finish.
            let bow: Double = ramp(t, from: finishAt, over: 0.8)
            ForEach(0..<4, id: \.self) { k in
                let hue: Color = [Theme.bubblegum, Theme.butter, Theme.mint, Theme.sky][k]
                let across: Double = w * (0.95 - 0.07 * Double(k))
                Circle().trim(from: 0.5, to: 0.5 + 0.5 * bow)
                    .stroke(hue.opacity(0.85), lineWidth: 9)
                    .frame(width: across, height: across)
                    .position(x: w / 2, y: floor - side * 0.4)
            }
            ForEach(0..<5, id: \.self) { k in
                let beat: Double = reduceMotion ? 0.6 : 0.5 + 0.5 * sin(t * 4 + Double(k) * 1.3)
                let tall: Double = max(1, side * (0.9 + 1.2 * beat) * lit)
                Capsule().fill(Color.white.opacity(0.5))
                    .frame(width: 10, height: tall)
                    .position(x: w * (0.14 + 0.18 * Double(k)), y: floor - tall / 2)
            }
            ForEach(0..<14, id: \.self) { k in
                let fx: Double = (Double(k) * 0.618).truncatingRemainder(dividingBy: 1)
                let speed: Double = 0.06 + 0.02 * Double(k % 3)
                let fy: Double = (Double(k) * 0.37 + (reduceMotion ? 0 : t * speed)).truncatingRemainder(dividingBy: 1)
                let across: Double = 10 + Double(k % 4) * 5
                Circle().stroke(Color.white.opacity(0.6), lineWidth: 2)
                    .frame(width: across, height: across)
                    .position(x: fx * w, y: (1 - fy) * h * 0.8)
            }
            RoundedRectangle(cornerRadius: 30).fill(Color.white.opacity(0.95))
                .frame(width: w * 0.98, height: side * 1.1)
                .position(x: w / 2, y: floor + side * 0.5)
            RoundedRectangle(cornerRadius: 22).fill(Color(hex: 0xBFEFFF))
                .frame(width: w * 0.9, height: side * 0.3)
                .position(x: w / 2, y: floor + side * 0.1)
            ForEach(0..<5, id: \.self) { k in
                let bob: Double = reduceMotion ? 0 : sin(t * 3 + Double(k)) * 4
                SquishyView(id: "quacky").frame(width: side * 0.42, height: side * 0.42)
                    .position(x: w * (0.14 + 0.18 * Double(k)), y: floor + side * 0.62 + bob)
            }
        case "treetop":
            // A plank stage in the treetops: swinging vines, fireflies, and leaves falling in time.
            ForEach(0..<4, id: \.self) { k in
                let swing: Double = reduceMotion ? 0 : sin(t * 1.6 + Double(k) * 1.1) * 9
                let long: Double = h * (0.28 + 0.05 * Double(k % 2))
                Capsule().fill(Color(hex: 0x4FA05A))
                    .frame(width: 7, height: long)
                    .rotationEffect(.degrees(swing), anchor: .top)
                    .position(x: w * (0.12 + 0.25 * Double(k)), y: long / 2 - 8)
            }
            ForEach(0..<12, id: \.self) { k in
                let fx: Double = (Double(k) * 0.618).truncatingRemainder(dividingBy: 1)
                let fy: Double = (Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
                let blink: Double = reduceMotion ? 0.7 : 0.5 + 0.5 * sin(t * 2.2 + Double(k) * 1.7)
                Circle().fill(Theme.butter.opacity(0.25 + 0.75 * blink * lit))
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.butter.opacity(blink * lit), radius: 6)
                    .position(x: fx * w, y: h * (0.12 + 0.45 * fy))
            }
            ForEach(0..<10, id: \.self) { k in
                let fx: Double = (Double(k) * 0.381 + 0.07).truncatingRemainder(dividingBy: 1)
                let fy: Double = (Double(k) * 0.29 + (reduceMotion ? 0 : t * 0.09)).truncatingRemainder(dividingBy: 1)
                let turn: Double = reduceMotion ? 20 : t * 60 + Double(k) * 40
                Ellipse().fill(Color(hex: 0x7CCB6B).opacity(0.85))
                    .frame(width: 14, height: 8)
                    .rotationEffect(.degrees(turn))
                    .position(x: fx * w, y: fy * h * 0.7)
            }
            RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0xB98654))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0x8A5F38), lineWidth: 3))
                .frame(width: w * 0.96, height: side * 0.32)
                .position(x: w / 2, y: floor + side * 0.12)
        case "launch":
            // Launch night: twinkling stars, a ringed planet, a shower of new stars on the finish chord, and the launch pad.
            ForEach(0..<30, id: \.self) { k in
                let fx: Double = (Double(k) * 0.618).truncatingRemainder(dividingBy: 1)
                let fy: Double = (Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
                let blink: Double = reduceMotion ? 0.7 : 0.5 + 0.5 * sin(t * 1.8 + Double(k) * 1.3)
                Circle().fill(Color.white.opacity(0.2 + 0.7 * blink * lit))
                    .frame(width: 4, height: 4)
                    .position(x: fx * w, y: fy * h * 0.6)
            }
            Ellipse().stroke(Color(hex: 0xFFB37A).opacity(0.7 * lit), lineWidth: 5)
                .frame(width: 150, height: 40)
                .rotationEffect(.degrees(-18))
                .position(x: w * 0.8, y: h * 0.16)
            Circle().fill(Color(hex: 0xC9A7F5).opacity(0.25 + 0.6 * lit))
                .frame(width: 84, height: 84)
                .position(x: w * 0.8, y: h * 0.16)
            ForEach(0..<14, id: \.self) { k in
                let fall: Double = ramp(t, from: finishAt + 0.08 * Double(k), over: 1.6)
                let fx: Double = (Double(k) * 0.381 + 0.05).truncatingRemainder(dividingBy: 1)
                Image(systemName: "star.fill").font(.system(size: 16))
                    .foregroundStyle(Theme.butter.opacity(fall > 0 && fall < 1 ? 1 : 0))
                    .position(x: fx * w, y: h * (0.05 + 0.5 * (reduceMotion ? 0.5 : fall)))
            }
            RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x9AA6C2))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0x6E7A98), lineWidth: 4))
                .frame(width: w * 0.96, height: side * 0.3)
                .position(x: w / 2, y: floor + side * 0.12)
        case "lab":
            // The big experiment: bubbles rising, a shelf of flasks that fizz, and a rainbow across the lab for the finish.
            ForEach(0..<10, id: \.self) { k in
                let fx: Double = (Double(k) * 0.618 + 0.1).truncatingRemainder(dividingBy: 1)
                let speed: Double = 0.06 + 0.02 * Double(k % 3)
                let fy: Double = (Double(k) * 0.29 + (reduceMotion ? 0 : t * speed)).truncatingRemainder(dividingBy: 1)
                let size: Double = 12 + Double(k % 4) * 8
                Circle().stroke(Color(hex: 0xA8F0D8).opacity(0.7), lineWidth: 3)
                    .frame(width: size, height: size)
                    .position(x: fx * w, y: h * 0.7 * (1 - fy))
            }
            ForEach(0..<5, id: \.self) { k in
                let fizz: Double = reduceMotion ? 0.6 : 0.5 + 0.5 * sin(t * 3.1 + Double(k) * 1.9)
                let tint: Color = [Color(hex: 0xFFC9DE), Color(hex: 0xC9A7F5), Color(hex: 0xB6F06A)][k % 3]
                RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.35 + 0.55 * fizz * lit))
                    .frame(width: 30, height: 44)
                    .position(x: w * (0.14 + 0.18 * Double(k)), y: h * 0.12)
            }
            let bow: Double = ramp(t, from: finishAt, over: 1.2)
            ForEach(0..<4, id: \.self) { k in
                let tint: Color = [Theme.bubblegum, Theme.butter, Theme.mint, Theme.sky][k]
                Circle().trim(from: 0.5, to: 0.5 + 0.5 * bow)
                    .stroke(tint.opacity(0.85), lineWidth: 9)
                    .frame(width: w * 0.9 - Double(k) * 22, height: w * 0.9 - Double(k) * 22)
                    .position(x: w / 2, y: floor - side * 0.2)
            }
            RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0xE3D3FF))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xB9A3E8), lineWidth: 4))
                .frame(width: w * 0.96, height: side * 0.3)
                .position(x: w / 2, y: floor + side * 0.12)
        case "sleigh":
            // A moon, falling snow, and the sleigh the cast ride in.
            let rise: Double = ramp(t, from: open, over: 2)
            let float: Double = reduceMotion ? 0 : sin(t * 1.3) * 10
            Circle().fill(Color(red: 1, green: 0.97, blue: 0.82))
                .frame(width: 90, height: 90)
                .position(x: w * 0.8, y: h * (0.3 - 0.14 * rise))
            ForEach(0..<28, id: \.self) { k in
                let fx: Double = (Double(k) * 0.618).truncatingRemainder(dividingBy: 1)
                let speed: Double = 0.05 + 0.02 * Double(k % 3)
                let fy: Double = (Double(k) * 0.37 + (reduceMotion ? 0 : t * speed)).truncatingRemainder(dividingBy: 1)
                Circle().fill(Color.white.opacity(0.8)).frame(width: 5, height: 5)
                    .position(x: fx * w, y: fy * h)
            }
            Capsule().fill(Color(red: 0.82, green: 0.16, blue: 0.22))
                .overlay(Capsule().stroke(Theme.butter, lineWidth: 4))
                .frame(width: w * 0.94, height: side * 0.55)
                .position(x: w / 2, y: floor + side * 0.1 + float)
        default:
            // The stage: lamps along the top come on left to right, and the velvet curtain parts.
            Ellipse().fill(Color.black.opacity(0.35))
                .frame(width: w * 1.2, height: side * 0.9)
                .position(x: w / 2, y: floor + side * 0.15)
            ForEach(0..<6, id: \.self) { k in
                let on: Double = ramp(t, from: open + 0.6 + 0.2 * Double(k), over: 0.25)
                Circle().fill(WorldShowView.lights[k].opacity(0.25 + 0.75 * on))
                    .frame(width: 18, height: 18)
                    .shadow(color: WorldShowView.lights[k].opacity(on), radius: 10)
                    .position(x: w * (Double(k) + 0.5) / 6, y: h * 0.1)
            }
            let part: Double = ramp(t, from: open, over: 1.5)
            ForEach(0..<2, id: \.self) { k in
                let dir: Double = k == 0 ? -1 : 1
                Rectangle().fill(Color(red: 0.69, green: 0.13, blue: 0.33))
                    .overlay(Rectangle().stroke(Theme.butter, lineWidth: 3))
                    .frame(width: w / 2 + 4, height: h)
                    .opacity(reduceMotion ? 1 - part : 1)
                    .position(x: w / 2 + dir * (w / 4 + (reduceMotion ? 0 : part * w / 2)), y: h / 2)
            }
        }
    }

    private var closing: some View {
        let first = !model.progress.finalesSeen.contains(world)
        return VStack(spacing: 14) {
            Text("Thanks for coming to the show!").font(Theme.title(24)).foregroundStyle(Theme.plum)
                .multilineTextAlignment(.center)
            if first, let plan {
                Text(verbatim: plan.keepsakeGlyph).font(.system(size: 64))
                Text("A keepsake for your Squish Room!").font(Theme.body(16)).foregroundStyle(Theme.plum)
                    .multilineTextAlignment(.center)
            }
            // The whole show again, recorded, for the share sheet.
            ClipControl(clips: model.clips, seconds: (plan?.length ?? 25) + 0.5) { replay() }
            Button { close() } label: { Text("Yay!").frame(maxWidth: 200) }
                .buttonStyle(SquishButtonStyle()).font(Theme.title(20))
                .accessibilityIdentifier("show-done")
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 30).fill(Theme.marshmallow))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.butter, lineWidth: 4))
        .padding(30)
        .frame(maxWidth: 560)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// The world's poster on the map heading: one spot for each sneak peek, filled in as they are
/// seen (tap one to watch it again), and the big show itself once it has played.
struct ShowPoster: View {
    @EnvironmentObject var model: AppModel
    let world: String

    var body: some View {
        if let plan = ShowPlan.load(world) {
            let cast = Array(model.roster.world(world, .common).map(\.id).prefix(6))
            let seen = model.progress.teasersSeen[world] ?? 0
            HStack(spacing: 6) {
                ForEach(plan.teaserLevels.indices, id: \.self) { i in
                    let id = cast.isEmpty ? "" : cast[i % cast.count]
                    Button {
                        if i < seen { model.showingNews = .teaser(world: world, number: i + 1) }
                    } label: {
                        SquishyView(id: id, silhouette: i >= seen).frame(width: 26, height: 26)
                            .padding(4)
                            .background(Circle().fill(i < seen ? Theme.butter : Color.white.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .disabled(i >= seen)
                }
                if model.progress.finalesSeen.contains(world) {
                    Button { model.showingNews = .finale(world: world) } label: {
                        Label { Text(ShowPlan.title(world)) } icon: { Image(systemName: "star.fill") }
                            .font(Theme.body(13))
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .accessibilityIdentifier("show-replay-\(world)")
                } else if model.isWorldComplete(world) {
                    // Finished, but the show was never watched: it is waiting right here.
                    Button { model.showingNews = .finale(world: world) } label: {
                        Label { Text("Watch the big show!") } icon: { Image(systemName: "star.fill") }
                            .font(Theme.body(13))
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.bubblegum))
                    .accessibilityIdentifier("show-watch-\(world)")
                } else {
                    Text("Big show after the last level!").font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.75))
                }
                Spacer(minLength: 0)
            }
        }
    }
}
