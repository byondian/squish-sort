import SwiftUI
import SquishPolicy
import SquishSoft

/// How each rarity looks everywhere a squishy is shown: mint common, blue rare, purple ultra, gold secret.
enum RarityLook {
    static let gold = Color(red: 0.93, green: 0.69, blue: 0.13)

    static func color(_ rarity: Rarity) -> Color {
        switch rarity {
        case .common: return Color(hex: 0x4FBF9F)
        case .rare: return Color(hex: 0x4C9FE6)
        case .ultra: return Theme.grape
        case .secret: return gold
        }
    }

    static func name(_ rarity: Rarity) -> String {
        switch rarity {
        case .common: return String(localized: "Common")
        case .rare: return String(localized: "Rare")
        case .ultra: return String(localized: "Ultra rare")
        case .secret: return String(localized: "Secret")
        }
    }

    /// The big word of a find.
    static func shout(_ rarity: Rarity) -> String {
        switch rarity {
        case .common: return String(localized: "NEW SQUISHY!")
        case .rare: return String(localized: "RARE!")
        case .ultra: return String(localized: "ULTRA RARE!")
        case .secret: return String(localized: "SECRET!")
        }
    }

    static func feel(_ feel: SquishFeel) -> String {
        switch feel {
        case .foam: return String(localized: "Slow-rise foam")
        case .jelly: return String(localized: "Jelly")
        case .gel: return String(localized: "Gel")
        case .mochi: return String(localized: "Mochi")
        }
    }
}

/// A small coloured pill: "RARE", "Toy Shop", "Jelly".
struct TagPill: View {
    let text: String
    var fill: Color = Theme.plum.opacity(0.1)
    var ink: Color = Theme.plum

    var body: some View {
        Text(verbatim: text)
            .font(Theme.body(11)).foregroundStyle(ink).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(fill))
    }
}

struct RarityTag: View {
    let rarity: Rarity

    var body: some View {
        TagPill(text: RarityLook.name(rarity).uppercased(), fill: RarityLook.color(rarity), ink: .white)
    }
}

/// Rays of light turning slowly behind a find. Still when Reduce Motion is on.
struct Rays: View {
    var color: Color
    var count = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn = false

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = max(size.width, size.height) * 0.75
            let step = 2 * Double.pi / Double(count)
            for i in 0..<count {
                let a = Double(i) * step
                var ray = Path()
                ray.move(to: c)
                ray.addLine(to: CGPoint(x: c.x + CGFloat(cos(a - step * 0.22)) * r, y: c.y + CGFloat(sin(a - step * 0.22)) * r))
                ray.addLine(to: CGPoint(x: c.x + CGFloat(cos(a + step * 0.22)) * r, y: c.y + CGFloat(sin(a + step * 0.22)) * r))
                ray.closeSubpath()
                ctx.fill(ray, with: .color(color.opacity(0.32)))
            }
        }
        .rotationEffect(.degrees(turn ? 360 : 0))
        .mask(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 30, endRadius: 330))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { turn = true }
        }
    }
}

/// A set's progress: a bar and what finishing it wins.
struct SetProgressLine: View {
    @EnvironmentObject var model: AppModel
    let squishy: Collectible

    var body: some View {
        let p = model.setProgress(for: squishy)
        let left = max(0, p.of - p.found)
        VStack(alignment: .leading, spacing: 5) {
            ProgressBar(fraction: p.of > 0 ? Double(p.found) / Double(p.of) : 0, fill: RarityLook.color(squishy.rarity))
                .frame(height: 10)
            HStack(spacing: 4) {
                Text(verbatim: countLine(p.goal, p.found, p.of))
                Spacer(minLength: 6)
                if left == 0 {
                    Text("Set complete!")
                } else if p.goal == .world {
                    Text("\(left) more: a secret squishy")
                } else {
                    Text("\(left) more: \(p.goal.coins) coins")
                }
            }
            .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func countLine(_ goal: SetGoal, _ found: Int, _ of: Int) -> String {
        switch goal {
        case .commons: return String(localized: "\(found) of \(of) commons")
        case .rares: return String(localized: "\(found) of \(of) rares")
        case .world: return String(localized: "\(found) of \(of) found")
        }
    }
}

struct ProgressBar: View {
    let fraction: Double
    var fill: Color = Theme.bubblegum
    var track: Color = Theme.plum.opacity(0.12)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(geo.size.height, geo.size.width * CGFloat(min(1, max(0, fraction)))))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The white card of a find: name, tags, its one-line bio and how close its set is.
struct FindCard: View {
    @EnvironmentObject var model: AppModel
    let squishy: Collectible

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: squishy.name(in: model.language)).font(Theme.title(24)).foregroundStyle(Theme.plum)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                RarityTag(rarity: squishy.rarity)
                TagPill(text: model.worldTitle(squishy.world))
                TagPill(text: RarityLook.feel(model.feel(for: squishy.id)))
            }
            if let bio = model.bio(for: squishy.id) {
                Text(verbatim: bio).font(Theme.body(14)).foregroundStyle(Theme.plum.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            SetProgressLine(squishy: squishy)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(.white))
    }
}

/// A common joins the collection the first time a jar of it is sorted: it pops up big with its
/// name and its set's count, then flies off to the Collection button. A tap sends it on its way.
struct NewFindSticker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let squishy: Collectible
    let done: () -> Void
    @State private var phase = 0
    @State private var bounce = false

    var body: some View {
        let p = model.setProgress(for: squishy)
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(verbatim: RarityLook.shout(.common)).font(Theme.title(26)).foregroundStyle(Theme.bubblegum)
                    .lineLimit(1).minimumScaleFactor(0.6)
                ZStack {
                    Rays(color: Theme.butter).frame(width: 200, height: 150)
                    SquishyView(id: squishy.id, rarity: squishy.rarity).frame(width: 120, height: 120)
                        .scaleEffect(x: bounce ? 1.06 : 0.96, y: bounce ? 0.95 : 1.05, anchor: .bottom)
                }
                .frame(height: 130)
                Text(verbatim: squishy.name(in: model.language)).font(Theme.title(22)).foregroundStyle(Theme.plum)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 6) {
                    RarityTag(rarity: squishy.rarity)
                    Text("\(p.found) of \(p.of) \(model.worldTitle(squishy.world)) commons")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: 300)
            .background(RoundedRectangle(cornerRadius: 28).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Theme.butter, lineWidth: 4))
            .shadow(color: Theme.plum.opacity(0.18), radius: 14, y: 6)
            .scaleEffect(phase == 0 ? 0.3 : (phase == 1 ? 1 : 0.12), anchor: phase == 2 ? .topTrailing : .center)
            .opacity(phase == 1 ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: phase == 2 ? .trailing : .center)
            .padding(.top, phase == 2 ? 8 : 110)
            .padding(.horizontal, 12)
            .onTapGesture { leave() }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("new-find")
        .task {
            model.sounds.play("new_stamp")
            model.haptics.win()
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.5)) { phase = 1 }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) { bounce = true }
            }
            try? await Task.sleep(nanoseconds: AppModel.isUITesting ? 400_000_000 : 1_700_000_000)
            leave()
        }
    }

    private func leave() {
        guard phase == 1 else { return }
        withAnimation(.easeIn(duration: 0.35)) { phase = 2 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done() }
    }
}

/// The squishy's own card: a big soft squishy to press, what it is, and where it came from.
struct SquishyCard: View {
    @EnvironmentObject var model: AppModel
    let squishy: Collectible
    /// Step to the squishy before (-1) or after (+1) this one. Nil hides the arrows.
    var step: ((Int) -> Void)?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                RarityTag(rarity: squishy.rarity)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.plum)
                        .frame(width: 36, height: 36).background(Circle().fill(Theme.plum.opacity(0.08)))
                }
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("card-close")
            }
            HStack(spacing: 4) {
                arrow("chevron.left", -1)
                ZStack {
                    if squishy.rarity != .common { Rays(color: RarityLook.color(squishy.rarity)).frame(width: 220, height: 200) }
                    SoftSquishy(toy: squishy.id, look: squishy.id, feel: model.feel(for: squishy.id)) {
                        SquishyView(id: squishy.id, rarity: squishy.rarity)
                    }
                    .frame(width: 190, height: 190)
                    .shinyGlitter(model.progress.collection.ownsShiny(squishy.id))
                    .overlay(alignment: .bottom) {
                        if model.progress.collection.ownsShiny(squishy.id) { ShinyBadge(size: 13) }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 200)
                arrow("chevron.right", 1)
            }
            Text("Press and squish me").font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.55))
            Text(verbatim: squishy.name(in: model.language)).font(Theme.title(26)).foregroundStyle(Theme.plum)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let bio = model.bio(for: squishy.id) {
                Text(verbatim: bio).font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.8))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if let stats = model.stats(for: squishy.id) { StatPanel(values: stats).id(squishy.id) }
            VStack(spacing: 0) {
                row(String(localized: "World"), model.worldTitle(squishy.world))
                row(String(localized: "Feel"), RarityLook.feel(model.feel(for: squishy.id)))
                row(String(localized: "Found"), foundLine)
                row(String(localized: "You have"), "\(model.progress.collection.owned[squishy.id] ?? 0)")
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.plum.opacity(0.05)))
            buttons
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 30).fill(Theme.marshmallow))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(RarityLook.color(squishy.rarity), lineWidth: 4))
        .padding(.horizontal, 14)
        .onAppear { model.cardSeen(squishy.id) }
        .onChange(of: squishy.id) { _, id in model.cardSeen(id) }
        .accessibilityIdentifier("squishy-card")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if model.isExtraUnlocked(.buddy) && model.progress.buddy.squishy != squishy.id {
                Button {
                    if model.setBuddy(ref: squishy.id, name: squishy.name(in: model.language)) { model.haptics.complete() }
                } label: { Text("Make my Buddy").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.6) }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
            }
            if model.isExtraUnlocked(.squishRoom) {
                Button { close(); model.squeeze(squishy.id) } label: {
                    Text("Squish Room").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.6)
                }
                .buttonStyle(SquishButtonStyle())
            }
        }
        .font(Theme.body(15))
    }

    @ViewBuilder
    private func arrow(_ icon: String, _ by: Int) -> some View {
        if let step {
            Button { step(by) } label: {
                Image(systemName: icon).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.plum)
                    .frame(width: 40, height: 40).background(Circle().fill(.white))
            }
            .accessibilityLabel(Text(by < 0 ? "Previous" : "Next"))
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(verbatim: title).foregroundStyle(Theme.plum.opacity(0.6))
            Spacer()
            Text(verbatim: value).foregroundStyle(Theme.plum).lineLimit(1).minimumScaleFactor(0.6)
        }
        .font(Theme.body(14))
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private var foundLine: String {
        switch model.progress.collection.source(of: squishy.id) {
        case "capsule": return String(localized: "In a capsule")
        case "reroll": return String(localized: "Swapped for spares")
        case "set": return String(localized: "Came out of hiding")
        default: return squishy.rarity == .common ? String(localized: "Sorted in a jar") : String(localized: "In a capsule")
        }
    }
}

/// Four stats in a two-by-two grid. For show in 1.0: nothing in the game reads them and nothing raises them.
struct StatPanel: View {
    /// Squish, bounce, stretch, charm: 1 to 99.
    let values: [Int]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    private static let colors = [Color(hex: 0xFF5C9D), Color(hex: 0x63B6F5), Color(hex: 0x63D1B8), Color(hex: 0xFFC93C)]

    private var names: [String] {
        [String(localized: "Squish"), String(localized: "Bounce"), String(localized: "Stretch"), String(localized: "Charm")]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) { cell(0); cell(1) }
            HStack(spacing: 14) { cell(2); cell(3) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: 0xF7F1FF)))
        .onAppear {
            if reduceMotion { filled = true } else { withAnimation(.easeOut(duration: 0.4)) { filled = true } }
        }
    }

    private func cell(_ i: Int) -> some View {
        let value = i < values.count ? values[i] : 1
        return VStack(spacing: 4) {
            HStack {
                Text(verbatim: names[i])
                Spacer(minLength: 4)
                Text(verbatim: "\(value)").monospacedDigit()
            }
            .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.plum).lineLimit(1).minimumScaleFactor(0.7)
            ProgressBar(fraction: filled ? Double(value) / 100 : 0, fill: StatPanel.colors[i], track: Color(hex: 0xE8DDFF))
                .frame(height: 9)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(i) * 0.06), value: filled)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The sparkle of a shiny edition: gold and white stars twinkling over the squishy. Still with Reduce Motion.
struct ShinyGlitter: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    private static let spots: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.16, 0.2, 0.16), (0.84, 0.16, 0.2), (0.3, 0.52, 0.12), (0.78, 0.58, 0.15), (0.12, 0.8, 0.14), (0.9, 0.86, 0.12), (0.52, 0.1, 0.11),
    ]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ForEach(0..<ShinyGlitter.spots.count, id: \.self) { i in
                let s = ShinyGlitter.spots[i]
                let lit = (i % 2 == 0) == on
                Text(verbatim: "✦").font(.system(size: max(7, s.size * side)))
                    .foregroundStyle(i % 3 == 0 ? Color.white : Theme.butter)
                    .shadow(color: Color(hex: 0xFFB300).opacity(0.8), radius: 2)
                    .scaleEffect(lit ? 1.15 : 0.45)
                    .opacity(lit ? 1 : 0.3)
                    .position(x: s.x * geo.size.width, y: s.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

/// The small gold "Shiny" label on a shiny edition.
struct ShinyBadge: View {
    var size: CGFloat = 11

    var body: some View {
        Text("Shiny").font(Theme.body(size)).foregroundStyle(Theme.plum)
            .padding(.horizontal, size * 0.6).padding(.vertical, size * 0.25)
            .background(Capsule().fill(LinearGradient(colors: [Theme.butter, Color(hex: 0xFFC94D)], startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .accessibilityIdentifier("shiny-badge")
    }
}

extension View {
    /// Lays the shiny sparkle over a squishy the player owns a shiny edition of.
    func shinyGlitter(_ shiny: Bool) -> some View {
        overlay { if shiny { ShinyGlitter() } }
    }
}
