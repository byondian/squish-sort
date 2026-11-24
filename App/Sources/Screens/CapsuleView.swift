import SwiftUI
import SquishPolicy

/// A capsule opens in two taps: the first twists it a notch and lets a crack of light out in the
/// rarity's colour, the second pops the top off. Then the reveal takes the whole screen.
struct CapsuleView: View {
    let collectible: Collectible
    let done: () -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false
    @State private var shake: CGFloat = 0
    /// Taps so far: the second opens it.
    @State private var taps = 0
    @State private var opening = false
    @State private var rolledIn = false
    @State private var hop = false
    @State private var rattle = false
    @State private var pulse = false
    @State private var handDown = false
    /// How far the top has turned: its stripes slide round.
    @State private var turned: Double = 0
    @State private var lidOff = false
    @State private var flash = false
    // The reveal, a beat at a time.
    @State private var landed = false
    @State private var squash: CGFloat = 0
    @State private var title = false
    @State private var card = false
    @State private var sparkle = false

    private var rarity: Rarity { collectible.rarity }
    private var tint: Color { RarityLook.color(rarity) }

    var body: some View {
        ZStack {
            if opened {
                reveal.transition(.opacity)
            } else {
                closed
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.marshmallow.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            // A rare find is worth showing off: six seconds of it, squishes and all.
            if opened, rarity != .common { ClipControl(clips: model.clips).padding(.trailing, 14).padding(.top, 6) }
        }
        .overlay {
            // One soft flash in the rarity's colour as the top comes off. No strobe.
            if flash { tint.opacity(0.55).ignoresSafeArea().transition(.opacity).allowsHitTesting(false) }
        }
        .onAppear {
            // A secret is not in a capsule: it steps straight out.
            if rarity == .secret { stepOut(); return }
            model.sounds.play("capsule_roll")
            // UI tests tap it straight away, so it is simply there.
            if AppModel.isUITesting || reduceMotion { rolledIn = true; return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) { rolledIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { hop = true }
                withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) { rattle = true }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) { handDown = true }
            }
        }
    }

    // MARK: - The closed capsule

    /// The very first capsule shows a hand tapping on it. Never again after that.
    private var showsHand: Bool {
        collectible.id == CapsuleDrops.firstCapsuleID && model.capsuleIsNew && !opening
    }

    private var closed: some View {
        VStack(spacing: 18) {
            Spacer()
            capsule
                // It rolls in, then hops and wobbles while it waits; harder after the first tap.
                .rotationEffect(.degrees(rolledIn ? (hop ? 4 : -4) * (taps > 0 ? 2 : 1) : -300))
                .offset(x: rolledIn ? shake : -420, y: hop ? -10 : 0)
                .overlay(alignment: .bottomTrailing) {
                    if showsHand {
                        Text(verbatim: "👆").font(.system(size: 46))
                            .offset(x: -40, y: handDown ? 6 : 26)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Circle())
                .onTapGesture { tapped() }
                // Anyone who tries to twist it: a drag round the capsule counts as a tap.
                .gesture(DragGesture(minimumDistance: 24).onEnded { _ in tapped() })
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(taps == 0 ? Text("Tap to open!") : Text("Tap again!"))
                .accessibilityAction { open() }
                .accessibilityIdentifier("open-capsule")
            // Two dots: one fills with each tap.
            HStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { i in
                    Circle().fill(i < taps ? tint : Theme.plum.opacity(0.18)).frame(width: 14, height: 14)
                }
            }
            .accessibilityHidden(true)
            Text(taps == 0 ? LocalizedStringKey("Tap to open!") : LocalizedStringKey("Tap again!"))
                .font(Theme.title(22)).foregroundStyle(Theme.plum.opacity(0.75))
                .accessibilityHidden(true)
            Spacer()
        }
    }

    /// Confetti in the colours of the squishy's world.
    private var worldColors: [Color] {
        switch collectible.world {
        case "toyshop": return [Theme.bubblegum, Theme.butter, Theme.sky]
        case "sweetfactory": return [Theme.bubblegum, Theme.mint, Theme.butter]
        case "starlight": return [Theme.grape, Theme.sky, Theme.butter]
        case "bubblebath": return [Theme.sky, Theme.bubblegum, Color.white]
        case "junglejam": return [Theme.mint, Theme.butter, Theme.bubblegum]
        case "spacestation": return [Theme.grape, Theme.butter, Theme.sky]
        case "morphlab": return [Theme.mint, Theme.bubblegum, Theme.grape]
        default: return [Theme.bubblegum, Theme.mint, Theme.butter, Theme.sky]
        }
    }

    private var topColor: Color { worldColors.first ?? Theme.bubblegum }

    /// A glossy toy capsule: coloured top, clear bottom with the squishy's shadow rattling inside.
    /// Only the top half turns: its stripes slide round as it twists.
    private var capsule: some View {
        let side: CGFloat = 210
        let cracked = taps > 0
        return ZStack {
            // After the first tap a glow in the rarity's colour gathers behind it.
            Circle().fill(tint).frame(width: side * 1.25, height: side * 1.25)
                .blur(radius: 30).opacity(cracked ? (pulse ? 0.55 : 0.3) : 0)
            // Clear bottom half, with a shadow of what is inside.
            ZStack {
                Circle().fill(Color.white.opacity(0.55))
                SquishyView(id: collectible.id, rarity: collectible.rarity, silhouette: true)
                    .frame(width: side * 0.5, height: side * 0.5)
                    .opacity(0.3)
                    .offset(x: rattle ? 5 : -5, y: side * 0.2 + (rattle ? -3 : 2))
            }
            .frame(width: side, height: side)
            .mask(Rectangle().frame(width: side, height: side / 2).offset(y: side / 4))
            // Coloured top half. It flies off when the capsule opens.
            ZStack {
                Circle().fill(LinearGradient(colors: [topColor, topColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                HStack(spacing: 30) {
                    ForEach(0..<12, id: \.self) { _ in Rectangle().fill(Color.white.opacity(0.28)).frame(width: 12) }
                }
                .offset(x: CGFloat(turned) * 0.42)
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .mask(Rectangle().frame(width: side, height: side / 2).offset(y: -side / 4))
            .offset(y: lidOff ? -520 : (cracked ? -5 : 0))
            .rotationEffect(.degrees(lidOff ? 40 : 0))
            .opacity(lidOff && reduceMotion ? 0 : 1)
            Circle().stroke(Theme.plum, lineWidth: 5).frame(width: side, height: side)
            // The seam. After the first tap a thin crack of light leaks out of it.
            Capsule().fill(Theme.plum).frame(width: side, height: 6)
            if cracked {
                Capsule().fill(tint).frame(width: side * 0.92, height: pulse ? 7 : 4)
                    .shadow(color: tint, radius: pulse ? 16 : 8)
                    .shadow(color: .white, radius: 3)
                    .transition(.scale(scale: 0.1).combined(with: .opacity))
            }
            // Shine.
            Ellipse().fill(Color.white.opacity(0.7)).frame(width: side * 0.2, height: side * 0.1)
                .rotationEffect(.degrees(-35)).offset(x: -side * 0.24, y: -side * 0.3)
        }
        .frame(width: side, height: side)
    }

    private func tapped() {
        guard !opening else { return }
        if AppModel.isUITesting { open(); return }
        if taps >= 1 { open(); return }
        // Tap 1: a notch of a twist, a click, and the tease.
        taps = 1
        model.sounds.play("capsule_click")
        model.haptics.land()
        withAnimation(.spring(response: 0.12, dampingFraction: 0.5)) { turned = 15 }
        guard !reduceMotion else { return }
        shake = 0
        withAnimation(.easeInOut(duration: 0.06).repeatCount(5, autoreverses: true)) { shake = 9 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { if !opening { shake = 0 } }
    }

    /// Tap 2: the full twist, the pop, one flash, and the top flies off.
    private func open() {
        guard !opening else { return }
        opening = true
        taps = 2
        shake = 0
        model.sounds.play("capsule_twist")
        model.haptics.win()
        if AppModel.isUITesting { showReveal(); return }
        withAnimation(.easeIn(duration: 0.22)) { turned = 200 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            model.sounds.play("capsule_pop")
            withAnimation(.easeOut(duration: 0.08)) { flash = true }
            withAnimation(.easeOut(duration: 0.25)) { lidOff = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation(.easeIn(duration: 0.35)) { flash = false } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showReveal() }
    }

    /// A secret's arrival: no capsule, a gold flash, then the reveal.
    private func stepOut() {
        opening = true
        if AppModel.isUITesting { showReveal(); return }
        withAnimation(.easeOut(duration: 0.12)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeIn(duration: 0.4)) { flash = false }
            showReveal()
        }
    }

    // MARK: - The reveal

    /// The squishy drops in and lands with a squash, then the title, then the card. Sound and
    /// haptics step up with the rarity.
    private func showReveal() {
        let still = AppModel.isUITesting || reduceMotion
        if still {
            landed = true; title = true; card = true; sparkle = true
            withAnimation(.easeOut(duration: 0.25)) { opened = true }
            cheer()
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { opened = true }
        sparkle = true
        withAnimation(.interpolatingSpring(stiffness: 150, damping: 13).delay(0.05)) { landed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            cheer()
            let wide: CGFloat = rarity == .secret ? 0.22 : (rarity == .ultra ? 0.2 : 0.18)
            withAnimation(.easeOut(duration: 0.1)) { squash = wide }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.38)) { squash = 0 }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { title = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { card = true }
        }
    }

    /// Rare: a chime and one heavy tap. Ultra: the longer chime and two. Secret: the fanfare,
    /// three, and the boss rumble softly underneath.
    private func cheer() {
        let heavy: Int
        switch rarity {
        case .secret:
            model.sounds.play("reveal_ultra")
            model.sounds.play("win_boss")
            model.sounds.play("boss_rumble", volume: 0.35)
            heavy = 3
        case .ultra:
            model.sounds.play("reveal_ultra")
            heavy = 2
        default:
            model.sounds.play("reveal_rare")
            heavy = 1
        }
        for i in 0..<heavy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16 * Double(i)) { model.haptics.win() }
        }
        if model.capsuleIsNew {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.sounds.play("new_stamp") }
        }
    }

    /// The first squishy out of a capsule (Peach Bun) offers to be the Buddy.
    private var asksToBeBuddy: Bool {
        collectible.id == CapsuleDrops.firstCapsuleID && model.offersFirstBuddy
    }

    /// Light in the middle behind the squishy, deeper at the edges.
    private var backdrop: [Color] {
        switch rarity {
        case .ultra: return [.white, Color(hex: 0xF0E2FF), Color(hex: 0x8C5CE6)]
        case .secret: return [Color(hex: 0xFFF4CC), RarityLook.gold, Color(hex: 0x22122E)]
        default: return [.white, Color(hex: 0xDDEEFF), Color(hex: 0x79B2EE)]
        }
    }

    private var reveal: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let twoLines = titleLines.count > 1 || rarity == .secret
            let titleHeight: CGFloat = twoLines ? 104 : 66
            let base: CGFloat = rarity == .secret ? 250 : (rarity == .ultra ? 240 : 230)
            // Small phones: the squishy gives way so the card always fits.
            let toy = min(base, max(130, h - titleHeight - 420))
            let centre = 6 + titleHeight + 10 + toy / 2
            ZStack(alignment: .top) {
                RadialGradient(colors: backdrop, center: UnitPoint(x: 0.5, y: centre / max(h, 1)),
                               startRadius: toy * 0.3, endRadius: max(w, h) * 0.85)
                    .ignoresSafeArea()
                // One big wheel of rays centred on the squishy: it reaches past every edge.
                RevealRays(rarity: rarity)
                    .frame(width: 1200, height: 1200)
                    .position(x: w / 2, y: centre)
                    .opacity(landed ? 1 : 0)
                // Sparkle stays in the top part and behind the card: it never crosses words or buttons.
                if sparkle {
                    Group {
                        Confetti(colors: rarity == .secret ? [RarityLook.gold, Theme.butter, .white] : worldColors,
                                 count: rarity == .rare ? 46 : 80, seconds: 3.2)
                        if rarity != .rare || reduceMotion { Twinkles(big: rarity == .secret) }
                    }
                    .frame(width: w, height: centre + toy * 0.55)
                    .clipped()
                    .allowsHitTesting(false)
                }
                VStack(spacing: 0) {
                    ZStack {
                        if title { titleView.transition(.scale(scale: 2.4).combined(with: .opacity)) }
                    }
                    .frame(height: titleHeight)
                    .padding(.top, 6)
                    squishy(toy).padding(.top, 10)
                    if !asksToBeBuddy {
                        Text("Press and squish me").font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.8))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(Color.white.opacity(0.85)))
                            .padding(.top, 4)
                            .opacity(card ? 1 : 0)
                    }
                    Spacer(minLength: 8)
                    if card {
                        bottomCard
                            .padding(.horizontal, 16).padding(.bottom, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
    }

    /// The soft squishy itself, on a white glow and a floor shadow. It can be squeezed straight away.
    private func squishy(_ side: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.85)).frame(width: side * 1.05, height: side * 1.05).blur(radius: 26)
            Ellipse().fill(Theme.plum.opacity(0.16)).frame(width: side * 0.62, height: side * 0.1)
                .offset(y: side * 0.46)
                .scaleEffect(landed ? 1 : 0.3)
            SoftSquishy(toy: collectible.id, look: collectible.id, feel: model.feel(for: collectible.id)) {
                SquishyView(id: collectible.id, rarity: collectible.rarity)
            }
            .frame(width: side, height: side)
            .shinyGlitter(model.capsuleIsShiny)
            .scaleEffect(x: 1 + squash, y: 1 - squash * 0.9, anchor: .bottom)
            .offset(y: landed ? 0 : -700)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: collectible.name(in: model.language)))
            .accessibilityIdentifier("capsule-squishy")
        }
        .frame(width: side, height: side)
    }

    /// "RARE!", or "ULTRA" over "RARE!", or "SECRET!". A spare says so instead.
    private var titleLines: [String] {
        if model.capsuleSpares != nil { return [String(localized: "+1 spare")] }
        let shout = RarityLook.shout(rarity)
        if rarity == .ultra, let gap = shout.firstIndex(of: " ") {
            return [String(shout[..<gap]), String(shout[shout.index(after: gap)...])]
        }
        return [shout]
    }

    private var titleView: some View {
        VStack(spacing: -6) {
            if rarity == .secret {
                Text("EVERY \(model.worldTitle(collectible.world).uppercased()) SQUISHY FOUND")
                    .font(Theme.body(13)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0x22122E).opacity(0.7)))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.bottom, 10)
            }
            ForEach(Array(titleLines.enumerated()), id: \.offset) { n, line in
                JellyTitle(text: line, rarity: rarity, size: titleLines.count > 1 ? (n == 0 ? 40 : 50) : 54)
            }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: titleLines.joined(separator: " ")))
    }

    /// One white card at the bottom: who it is, its set, and the two buttons side by side.
    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: collectible.name(in: model.language)).font(Theme.title(32)).foregroundStyle(Theme.plum)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer(minLength: 4)
                if model.capsuleIsShiny { ShinyBadge(size: 13) }
                RarityTag(rarity: rarity)
            }
            HStack(spacing: 6) {
                TagPill(text: model.worldTitle(collectible.world))
                TagPill(text: RarityLook.feel(model.feel(for: collectible.id)))
            }
            if let bio = model.bio(for: collectible.id) {
                Text(verbatim: bio).font(Theme.body(14)).foregroundStyle(Theme.plum.opacity(0.8))
                    .lineLimit(3).minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if let spares = model.capsuleSpares {
                    spareLine(spares)
                } else {
                    SetProgressLine(squishy: collectible)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.13)))
            if asksToBeBuddy {
                SpeechBubble(text: String(localized: "Can I be your Buddy?")).frame(maxWidth: .infinity)
                Button {
                    model.haptics.complete()
                    model.adoptFirstBuddy(collectible)
                    done()
                } label: { Text("Yes!").frame(maxWidth: .infinity) }
                .buttonStyle(SquishButtonStyle())
                .accessibilityIdentifier("capsule-next")
            } else {
                HStack(spacing: 10) {
                    if model.offersSqueezeFromCapsule {
                        // Opens the Squish Room with the new squishy in hand.
                        Button { model.squeezeFromCapsule(collectible.id) } label: {
                            Text("Squish it!").font(Theme.body(18)).foregroundStyle(tint)
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(Capsule().stroke(tint, lineWidth: 3))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressSquish())
                        .accessibilityIdentifier("capsule-squeeze")
                    }
                    Button(action: done) {
                        Text("Add to shelf").font(Theme.body(18)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(Capsule().fill(rarity == .secret ? RarityLook.gold : Theme.bubblegum))
                    }
                    .buttonStyle(PressSquish())
                    .accessibilityIdentifier("capsule-next")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.white))
        .overlay {
            // An ultra gets a holographic rim, a secret a gold one.
            let rim = RoundedRectangle(cornerRadius: 30, style: .continuous)
            switch rarity {
            case .ultra:
                rim.stroke(AngularGradient(colors: [Color(hex: 0xFF8DBD), Color(hex: 0x9B7BFF), Color(hex: 0x6FD6FF),
                                                    Color(hex: 0xA5F0C5), Color(hex: 0xFFE27A), Color(hex: 0xFF8DBD)],
                                           center: .center), lineWidth: 4)
            case .secret:
                rim.stroke(LinearGradient(colors: [Theme.butter, RarityLook.gold, Theme.butter],
                                          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 4)
            default:
                EmptyView()
            }
        }
        .shadow(color: Theme.plum.opacity(0.18), radius: 14, y: 6)
    }

    /// A duplicate fills the spares bar: three swap for a new squishy on the Collection page.
    private func spareLine(_ spares: Int) -> some View {
        let need = CapsuleDrops.sparesPerReroll
        return VStack(alignment: .leading, spacing: 5) {
            ProgressBar(fraction: Double(min(spares, need)) / Double(need), fill: spares >= need ? Theme.butter : Theme.grape)
                .frame(height: 10)
            if spares >= need {
                Text("3 spares! Swap them in your Collection.").font(Theme.body(12)).foregroundStyle(Theme.plum)
            } else {
                Text("Spares \(spares)/\(need)").font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.75))
            }
        }
    }
}

/// One wheel of light rays, big enough to pass every edge of the screen, fading out towards its rim.
/// Rare: 12 white rays. Ultra: 16, with thin pink ones turning the other way. Secret: 20 gold,
/// with thin white glints turning the other way, faster. Still with Reduce Motion.
struct RevealRays: View {
    let rarity: Rarity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn = false

    var body: some View {
        let main: (count: Int, color: Color, seconds: Double) = {
            switch rarity {
            case .ultra: return (16, .white, 24)
            case .secret: return (20, Theme.butter, 16)
            default: return (12, .white, 24)
            }
        }()
        ZStack {
            wheel(count: main.count, width: 0.24, color: main.color.opacity(0.5))
                .rotationEffect(.degrees(turn ? 360 : 0))
                .animation(reduceMotion ? nil : .linear(duration: main.seconds).repeatForever(autoreverses: false), value: turn)
            if rarity != .rare {
                wheel(count: main.count, width: 0.07,
                      color: (rarity == .ultra ? Color(hex: 0xFF8DBD) : Color.white).opacity(0.55))
                    .rotationEffect(.degrees(turn ? -360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: main.seconds * 0.75).repeatForever(autoreverses: false), value: turn)
            }
        }
        .mask(RadialGradient(colors: [.white, .white.opacity(0.7), .white.opacity(0)], center: .center,
                             startRadius: 40, endRadius: 600))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { if !reduceMotion { turn = true } }
    }

    private func wheel(count: Int, width: Double, color: Color) -> some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = max(size.width, size.height) / 2
            let step = 2 * Double.pi / Double(count)
            for i in 0..<count {
                let a = Double(i) * step
                var ray = Path()
                ray.move(to: c)
                ray.addLine(to: CGPoint(x: c.x + CGFloat(cos(a - step * width)) * r, y: c.y + CGFloat(sin(a - step * width)) * r))
                ray.addLine(to: CGPoint(x: c.x + CGFloat(cos(a + step * width)) * r, y: c.y + CGFloat(sin(a + step * width)) * r))
                ray.closeSubpath()
                ctx.fill(ray, with: .color(color))
            }
        }
    }
}

/// Stars that twinkle where they are. With Reduce Motion they are simply there.
struct Twinkles: View {
    var big = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    private static let spots: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.1, 0.16, 20), (0.86, 0.12, 24), (0.22, 0.5, 16), (0.8, 0.46, 18), (0.06, 0.74, 22),
        (0.93, 0.72, 20), (0.34, 0.08, 14), (0.68, 0.26, 14), (0.15, 0.9, 16), (0.88, 0.9, 16),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<Twinkles.spots.count, id: \.self) { i in
                let s = Twinkles.spots[i]
                Text(verbatim: "✦").font(.system(size: s.size * (big ? 1.5 : 1)))
                    .foregroundStyle(big ? Theme.butter : Color.white)
                    .shadow(color: Theme.plum.opacity(0.25), radius: 2)
                    .scaleEffect(on && i % 2 == 0 || !on && i % 2 == 1 ? 1.15 : 0.5)
                    .opacity(on && i % 2 == 0 || !on && i % 2 == 1 ? 1 : 0.35)
                    .position(x: s.x * geo.size.width, y: s.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

/// A word in big jelly letters, like the logo: each letter tilted and wobbling, with a coloured
/// outline and a glossy fill. Ultra's fill shifts like a hologram; a shine sweeps across SECRET.
struct JellyTitle: View {
    let text: String
    let rarity: Rarity
    var size: CGFloat = 54
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wobble = false
    @State private var sweep = false

    private var outline: Color {
        switch rarity {
        case .ultra: return Color(hex: 0x5B2FB8)
        case .secret: return Color(hex: 0x8A5A00)
        default: return Color(hex: 0x1F5FA8)
        }
    }

    private var fill: [Color] {
        switch rarity {
        case .ultra: return [Color(hex: 0xFFB3E1), Color(hex: 0xB79BFF), Color(hex: 0x8EE3FF)]
        case .secret: return [Color(hex: 0xFFF6C2), Color(hex: 0xFFD54A), Color(hex: 0xF0A51E)]
        default: return [.white, Color(hex: 0xBFE1FF), Color(hex: 0x6FB4F2)]
        }
    }

    var body: some View {
        let letters = Array(text)
        HStack(spacing: -size * 0.04) {
            ForEach(0..<letters.count, id: \.self) { i in
                letter(String(letters[i]))
                    .rotationEffect(.degrees((i % 2 == 0 ? -6 : 5) + (wobble ? (i % 2 == 0 ? 3 : -3) : 0)))
                    .scaleEffect(x: wobble ? 1.04 : 0.98, y: wobble ? 0.96 : 1.03, anchor: .bottom)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(Double(i) * 0.08),
                               value: wobble)
            }
        }
        .hueRotation(.degrees(rarity == .ultra && sweep ? 50 : 0))
        .overlay {
            if rarity == .secret {
                // A band of shine crossing the word.
                Rectangle().fill(LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * 0.9)
                    .rotationEffect(.degrees(18))
                    .offset(x: sweep ? size * 4 : -size * 4)
                    .blendMode(.plusLighter)
                    .mask(HStack(spacing: -size * 0.04) {
                        ForEach(0..<letters.count, id: \.self) { i in
                            Text(verbatim: String(letters[i])).font(Theme.title(size))
                                .rotationEffect(.degrees(i % 2 == 0 ? -6 : 5))
                        }
                    })
                    .allowsHitTesting(false)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .onAppear {
            guard !reduceMotion else { return }
            wobble = true
            withAnimation(.easeInOut(duration: rarity == .secret ? 1.6 : 1.2).repeatForever(autoreverses: rarity != .secret)) { sweep = true }
        }
    }

    private func letter(_ s: String) -> some View {
        let w = max(2, size * 0.07)
        return ZStack {
            // The outline: the letter set down eight times round itself, and a drop below.
            ForEach(0..<8, id: \.self) { k in
                let a = Double(k) / 8 * 2 * Double.pi
                Text(verbatim: s).font(Theme.title(size)).foregroundStyle(outline)
                    .offset(x: CGFloat(cos(a)) * w, y: CGFloat(sin(a)) * w)
            }
            Text(verbatim: s).font(Theme.title(size)).foregroundStyle(outline).offset(y: w * 2.2)
            Text(verbatim: s).font(Theme.title(size))
                .foregroundStyle(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
        }
        .fixedSize()
    }
}
