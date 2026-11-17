import SwiftUI
import SquishPolicy

/// A world's shape-shifter at giant size with the gold crown on its head: the friendly guard of
/// the world's last level. Fun, never scary.
struct BossGiant: View {
    @EnvironmentObject var model: AppModel
    let world: String
    var squash: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack(alignment: .top) {
                SquishyView(id: model.bossID(world: world), rarity: .ultra, squash: squash)
                    .frame(width: side, height: side)
                // The crown rides on the top of the toy and sinks with a squash.
                Image("boss-crown").resizable().scaledToFit()
                    .frame(width: side * 0.46)
                    .rotationEffect(.degrees(-8))
                    .offset(x: -side * 0.04, y: -side * 0.12 + squash * side * 0.3)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// The splash before a boss level. A world's finale gets the long one: the screen dims, three
/// soft rumbles, the giant drops in, "BOSS LEVEL!" and the prizes. The every-tenth bosses get a
/// short "BOSS!". A tap skips it once it has been seen before.
struct BossSplash: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let world: String
    let finale: Bool
    let canSkip: Bool
    let done: () -> Void
    @State private var landed = false
    @State private var squash: CGFloat = 0
    @State private var title = false
    @State private var prizes = false
    @State private var shake: CGFloat = 0
    @State private var leaving = false

    private var tint: Color {
        switch world {
        case "toyshop": return Color(hex: 0xC2417F)
        case "sweetfactory": return Color(hex: 0x2F9E86)
        case "starlight": return Color(hex: 0x4B3A8C)
        case "bubblebath": return Color(hex: 0x2E86B0)
        case "junglejam": return Color(hex: 0x2F7D46)
        default: return Color(hex: 0xB03A48)
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint.opacity(0.94), Theme.plum.opacity(0.96)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if finale { Rays(color: Theme.butter).ignoresSafeArea().opacity(title ? 1 : 0) }
            VStack(spacing: 14) {
                Spacer()
                if finale {
                    BossGiant(world: world, squash: squash)
                        .frame(width: 210, height: 210)
                        .offset(y: landed ? 0 : -700)
                }
                if title {
                    Text(finale ? LocalizedStringKey("BOSS LEVEL!") : LocalizedStringKey("BOSS!"))
                        .font(Theme.title(finale ? 44 : 56)).foregroundStyle(.white)
                        .shadow(color: Theme.plum.opacity(0.7), radius: 0, x: 0, y: 4)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .transition(.scale(scale: 2.6).combined(with: .opacity))
                    if finale {
                        Text("World finale").font(Theme.body(18)).foregroundStyle(.white.opacity(0.9))
                            .transition(.opacity)
                    }
                }
                if prizes {
                    // What winning brings, shown up front.
                    HStack(spacing: 14) {
                        prize { Image(systemName: "capsule.fill").foregroundStyle(Theme.bubblegum) }
                        prize { Label { Text(verbatim: "+\(model.config.coins.worldComplete)") } icon: { CoinIcon() } }
                        prize { Image("boss-crown").resizable().scaledToFit().frame(height: 26) }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    Button(action: leave) { Text("Let's go!").frame(maxWidth: 220) }
                        .buttonStyle(SquishButtonStyle()).font(Theme.title(22))
                        .accessibilityIdentifier("boss-go")
                        .transition(.opacity)
                }
                Spacer()
            }
            .padding(24)
            .offset(x: shake)
        }
        .contentShape(Rectangle())
        .onTapGesture { if canSkip { leave() } }
        .opacity(leaving ? 0 : 1)
        .task { await run() }
    }

    private func prize<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(Theme.title(20)).foregroundStyle(Theme.plum)
            .frame(minWidth: 64, minHeight: 48)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
    }

    @MainActor
    private func run() async {
        model.sounds.play("drumroll")
        guard finale else {
            // The short one: a word, a beat, and on with the level.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { title = true }
            model.haptics.complete()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            leave()
            return
        }
        for _ in 0..<3 {
            model.sounds.play("boss_rumble")
            model.haptics.complete()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.05).repeatCount(5, autoreverses: true)) { shake = 3 }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            shake = 0
        }
        // The giant drops in and lands with a big squash.
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .interpolatingSpring(stiffness: 120, damping: 11)) { landed = true }
        try? await Task.sleep(nanoseconds: 380_000_000)
        model.sounds.play("land_soft")
        model.haptics.win()
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) { squash = 0.8 }
            try? await Task.sleep(nanoseconds: 140_000_000)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.4)) { squash = 0 }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { title = true }
        try? await Task.sleep(nanoseconds: 450_000_000)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { prizes = true }
    }

    private func leave() {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: 0.25)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { done() }
    }
}

/// The giant peeking over the corner of a finale's board. It gasps when a jar is finished,
/// wobbles on the last jar and cheers at the win. It never mocks.
struct BossPeek: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let world: String
    /// 0 watching, 1 gasp, 2 nervous, 3 cheer.
    let mood: Int
    @State private var squash: CGFloat = 0
    @State private var bob = false
    @State private var wobble = false

    var body: some View {
        BossGiant(world: world, squash: squash)
            .frame(width: 92, height: 92)
            .rotationEffect(.degrees(mood == 2 && wobble ? 5 : (mood == 2 ? -5 : -10)))
            .offset(x: 18, y: mood == 3 ? (bob ? -16 : 0) : (bob ? 2 : 6))
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true }
            }
            .onChange(of: mood) { _, now in react(now) }
    }

    private func react(_ now: Int) {
        guard !reduceMotion else { return }
        switch now {
        case 1:
            withAnimation(.easeOut(duration: 0.1)) { squash = -0.5 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) { squash = 0 }
            }
        case 2:
            withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) { wobble = true }
        case 3:
            wobble = false
            withAnimation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true)) { bob.toggle() }
            withAnimation(.easeInOut(duration: 0.28).repeatForever(autoreverses: true)) { squash = 0.45 }
        default:
            break
        }
    }
}
