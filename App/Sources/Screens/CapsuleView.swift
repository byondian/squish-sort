import SwiftUI
import SquishPolicy

/// Twist (drag round), click, a pause, then pop: the build-up matters more than the reveal.
struct CapsuleView: View {
    let collectible: Collectible
    let done: () -> Void
    @EnvironmentObject var model: AppModel
    @State private var angle: Double = 0
    @State private var lastDrag: CGPoint?
    @State private var opened = false
    @State private var shake: CGFloat = 0
    /// Taps so far: the third opens it, for anyone who can't twist.
    @State private var taps = 0
    @State private var opening = false
    @State private var rolledIn = false
    @State private var hop = false
    @State private var rattle = false
    @State private var lidOff = false
    @State private var flash = false
    @State private var banner = false
    @State private var confetti = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            if opened {
                if banner {
                    Text(verbatim: shout)
                        .font(Theme.title(34)).foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 6)
                        .background(Capsule().fill(RarityLook.color(collectible.rarity)))
                        .overlay(Capsule().stroke(.white, lineWidth: 3))
                        .rotationEffect(.degrees(-3))
                        .transition(.scale(scale: 2.8).combined(with: .opacity))
                }
                ZStack {
                    Rays(color: RarityLook.color(collectible.rarity)).frame(width: 340, height: 250)
                    SoftSquishy(toy: collectible.id, look: collectible.id, feel: model.feel(for: collectible.id)) {
                        SquishyView(id: collectible.id, rarity: collectible.rarity)
                    }
                    .frame(width: 200, height: 200)
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: collectible.name(in: model.language)))
                    .accessibilityIdentifier("capsule-squishy")
                }
                .frame(height: 210)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
                FindCard(squishy: collectible).padding(.horizontal, 20)
                if let spares = model.capsuleSpares {
                    spareLine(spares)
                }
                if asksToBeBuddy {
                    SpeechBubble(text: String(localized: "Can I be your Buddy?"))
                } else {
                    if !model.offersSqueezeFromCapsule {
                        Text("Squeeze me!").font(Theme.body(18)).foregroundStyle(Theme.plum.opacity(0.7))
                    }
                }
                if asksToBeBuddy {
                    Button("Yes!") {
                        model.haptics.complete()
                        model.adoptFirstBuddy(collectible)
                        done()
                    }
                    .buttonStyle(SquishButtonStyle())
                    .accessibilityIdentifier("capsule-next")
                } else {
                    if model.offersSqueezeFromCapsule {
                        // Opens the Squish Room with the new squishy in hand.
                        Button { model.squeezeFromCapsule(collectible.id) } label: {
                            Label("Squish it!", systemImage: "hand.point.up.left.fill")
                        }
                        .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                        .accessibilityIdentifier("capsule-squeeze")
                    }
                    Button("Add to shelf", action: done).buttonStyle(SquishButtonStyle())
                        .accessibilityIdentifier("capsule-next")
                }
            } else {
                capsule
                    // It rolls in, then hops and wobbles while it waits.
                    .rotationEffect(.degrees(rolledIn ? (hop ? 4 : -4) : -300))
                    .offset(x: rolledIn ? shake : -420, y: hop ? -10 : 0)
                    .contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 6)
                        .onChanged { value in twist(value) }
                        .onEnded { _ in lastDrag = nil })
                    .onTapGesture { tapped() }
                    .accessibilityElement()
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text("Twist to open!"))
                    .accessibilityAction { open() }
                    .accessibilityIdentifier("open-capsule")
                Text("Twist to open!").font(Theme.body(17)).foregroundStyle(Theme.plum.opacity(0.7))
                    .accessibilityHidden(true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.marshmallow.ignoresSafeArea())
        .overlay {
            // An ultra gets a gold flash before it shows itself.
            if flash { Theme.butter.opacity(0.85).ignoresSafeArea().transition(.opacity).allowsHitTesting(false) }
        }
        .overlay { if confetti { Confetti(colors: worldColors, count: 60, seconds: 3).ignoresSafeArea() } }
        .onAppear {
            // A secret is not in a capsule: it steps straight out.
            if collectible.rarity == .secret { reveal(); return }
            model.sounds.play("capsule_roll")
            // UI tests tap it straight away, so it is simply there.
            if AppModel.isUITesting { rolledIn = true; return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.62)) { rolledIn = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { hop = true }
                withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) { rattle = true }
            }
        }
    }

    /// The first squishy out of a capsule (Peach Bun) offers to be the Buddy.
    private var asksToBeBuddy: Bool {
        collectible.id == CapsuleDrops.firstCapsuleID && model.offersFirstBuddy
    }

    /// "5/17" for the squishy's world shelf.
    private var bookCount: String {
        let shelf = model.roster.collectibles.filter { $0.world == collectible.world }
        return "\(shelf.filter { model.progress.collection.owns($0.id) }.count)/\(shelf.count)"
    }

    /// Confetti in the colours of the squishy's world.
    private var worldColors: [Color] {
        switch collectible.world {
        case "toyshop": return [Theme.bubblegum, Theme.butter, Theme.sky]
        case "sweetfactory": return [Theme.bubblegum, Theme.mint, Theme.butter]
        case "starlight": return [Theme.grape, Theme.sky, Theme.butter]
        default: return [Theme.bubblegum, Theme.mint, Theme.butter, Theme.sky]
        }
    }

    private var topColor: Color { worldColors.first ?? Theme.bubblegum }
    /// White light for a rare, gold for an ultra.
    private var light: Color { collectible.rarity == .ultra ? Theme.butter : .white }
    /// 0 until the twist is half way, then up to 1 as it is about to open.
    private var leak: Double { min(1, max(0, (angle - 180) / 120)) }

    /// A glossy toy capsule: coloured top, clear bottom with the squishy's shadow rattling inside.
    /// Only the top half turns: its stripes slide round as it is twisted.
    private var capsule: some View {
        let side: CGFloat = 210
        return ZStack {
            // Light leaks out as it comes loose.
            Circle().fill(light).frame(width: side * 1.25, height: side * 1.25)
                .blur(radius: 28).opacity(leak * 0.9)
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
            // Coloured top half. It lifts off when the capsule opens.
            ZStack {
                Circle().fill(LinearGradient(colors: [topColor, topColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                HStack(spacing: 30) {
                    ForEach(0..<9, id: \.self) { _ in Rectangle().fill(Color.white.opacity(0.28)).frame(width: 12) }
                }
                .offset(x: CGFloat(angle.truncatingRemainder(dividingBy: 70)) * 0.6 - 21)
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .mask(Rectangle().frame(width: side, height: side / 2).offset(y: -side / 4))
            .offset(y: lidOff ? -260 : -CGFloat(leak) * 6)
            .rotationEffect(.degrees(lidOff ? 50 : 0))
            .opacity(lidOff ? 0 : 1)
            Circle().stroke(Theme.plum, lineWidth: 5).frame(width: side, height: side)
            Capsule().fill(Theme.plum).frame(width: side, height: 6)
            // Shine.
            Ellipse().fill(Color.white.opacity(0.7)).frame(width: side * 0.2, height: side * 0.1)
                .rotationEffect(.degrees(-35)).offset(x: -side * 0.24, y: -side * 0.3)
            // Sparkles leak from the seam and grow with the twist.
            ForEach(0..<5, id: \.self) { i in
                Text(verbatim: "✦").font(.system(size: 22)).foregroundStyle(i % 2 == 0 ? Theme.butter : .white)
                    .shadow(color: Theme.plum.opacity(0.4), radius: 1)
                    .scaleEffect(CGFloat(min(1.4, angle / 220)) * (rattle && i % 2 == 0 ? 1.15 : 0.9))
                    .offset(x: CGFloat(i - 2) * side * 0.21, y: i % 2 == 0 ? -9 : 9)
            }
        }
        .frame(width: side, height: side)
    }

    /// Three taps open it: each one is a bigger shake and a crack.
    private func tapped() {
        guard !opening else { return }
        if AppModel.isUITesting { open(); return }
        taps += 1
        if taps >= 3 { open(); return }
        model.sounds.play("capsule_shake")
        model.sounds.play("capsule_click")
        model.haptics.reject()
        angle = max(angle, Double(taps) * 100)
        shake = 0
        withAnimation(.easeInOut(duration: 0.06).repeatCount(3 + taps * 2, autoreverses: true)) { shake = CGFloat(6 + taps * 5) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { if !opening { shake = 0 } }
    }

    private func twist(_ value: DragGesture.Value) {
        let center = CGPoint(x: 105, y: 105)
        defer { lastDrag = value.location }
        guard let last = lastDrag else { return }
        let a1 = atan2(last.y - center.y, last.x - center.x)
        let a2 = atan2(value.location.y - center.y, value.location.x - center.x)
        var delta = (a2 - a1) * 180 / .pi
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        // A ratchet tick every 40 degrees of twist.
        if Int(angle / 40) != Int((angle + abs(delta)) / 40) {
            model.sounds.play("capsule_twist")
            model.haptics.land()
        }
        angle += abs(delta)
        if angle > 300, !opening { open() }
    }

    /// "NEW!" for a first find, the rarity's shout for a rare and up, "+1 spare" for one already owned.
    private var shout: String {
        if model.capsuleSpares != nil { return String(localized: "+1 spare") }
        return RarityLook.shout(collectible.rarity)
    }

    /// A duplicate fills the spares bar: three swap for a new squishy on the Collection page.
    private func spareLine(_ spares: Int) -> some View {
        let need = CapsuleDrops.sparesPerReroll
        return VStack(spacing: 5) {
            ProgressBar(fraction: Double(min(spares, need)) / Double(need), fill: spares >= need ? Theme.butter : Theme.grape)
                .frame(height: 12)
            if spares >= need {
                Text("3 spares! Swap them in your Collection.").font(Theme.body(14)).foregroundStyle(Theme.plum)
            } else {
                Text("Spares \(spares)/\(need)").font(Theme.body(14)).foregroundStyle(Theme.plum.opacity(0.75))
            }
        }
        .padding(.horizontal, 36)
    }

    /// A secret's arrival: no capsule, a gold flash, then the find.
    private func reveal() {
        opening = true
        model.sounds.play("reveal_ultra")
        model.haptics.win()
        confetti = true
        if AppModel.isUITesting { opened = true; banner = true; return }
        withAnimation(.easeOut(duration: 0.12)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeIn(duration: 0.4)) { flash = false }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) { opened = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { banner = true }
        }
    }

    private func open() {
        guard !opening else { return }
        opening = true
        model.haptics.complete()
        let ultra = collectible.rarity == .ultra
        angle = max(angle, 300)
        model.sounds.play("capsule_click")
        model.sounds.play(ultra ? "drumroll" : "capsule_shake")
        // A quick shake before the pop. An ultra holds its breath half a second longer, then flashes gold.
        let pop = ultra && !AppModel.isUITesting ? 0.85 : 0.35
        shake = 0
        withAnimation(.easeInOut(duration: 0.06).repeatCount(ultra ? 13 : 5, autoreverses: true)) { shake = 9 }
        if ultra {
            DispatchQueue.main.asyncAfter(deadline: .now() + pop - 0.12) {
                withAnimation(.easeOut(duration: 0.12)) { flash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation(.easeIn(duration: 0.4)) { flash = false } }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pop - 0.1) {
            withAnimation(.easeOut(duration: 0.18)) { lidOff = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pop) {
            model.sounds.play("capsule_pop")
            model.sounds.play(ultra ? "reveal_ultra" : "reveal_rare")
            confetti = true
            // The squishy springs out and bounces.
            withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) { opened = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { banner = true }
            }
            if model.capsuleIsNew {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    model.haptics.win()
                    model.sounds.play("new_stamp")
                }
            }
        }
    }
}
