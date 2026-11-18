import SwiftUI

/// The five rooms. The Play Mat is free; the others come with "Unlock everything".
enum KidsScene: String, CaseIterable, Identifiable {
    case playMat, bathTime, bounceHouse, bedtime, snowDay

    var id: String { rawValue }
    var isFree: Bool { self == .playMat }

    /// Pictures only: a child who can't read picks a room by its picture.
    var icon: String {
        switch self {
        case .playMat: return "teddybear.fill"
        case .bathTime: return "bathtub.fill"
        case .bounceHouse: return "balloon.2.fill"
        case .bedtime: return "moon.stars.fill"
        case .snowDay: return "snowflake"
        }
    }

    /// Read out by VoiceOver only.
    var name: LocalizedStringKey {
        switch self {
        case .playMat: return "Play Mat"
        case .bathTime: return "Bath Time"
        case .bounceHouse: return "Bounce House"
        case .bedtime: return "Bedtime"
        case .snowDay: return "Snow Day"
        }
    }

    var tint: Color {
        switch self {
        case .playMat: return Theme.butter
        case .bathTime: return Theme.sky
        case .bounceHouse: return Theme.bubblegum
        case .bedtime: return Theme.grape
        case .snowDay: return Color(red: 0.80, green: 0.90, blue: 1)
        }
    }

    var isDark: Bool { self == .bedtime }

    /// How heavy a squishy is in this room: it bobs in the bath and drifts down on a snow day.
    var gravityScale: Double {
        switch self {
        case .bathTime: return 0.3
        case .snowDay: return 0.6
        default: return 1
        }
    }

    /// The Bounce House sends a thrown squishy off the walls again and again.
    var bounce: Double? { self == .bounceHouse ? 0.85 : nil }

    /// What floats in this room for a finger to pop: blocks, bubbles, balloons, stars, snowflakes.
    var popIcon: String {
        switch self {
        case .playMat: return "star.fill"
        case .bathTime: return "bubbles.and.sparkles.fill"
        case .bounceHouse: return "balloon.fill"
        case .bedtime: return "moon.stars.fill"
        case .snowDay: return "snowflake"
        }
    }

    var popColours: [Color] {
        switch self {
        case .playMat: return [Theme.bubblegum, Theme.sky, Theme.mint, Theme.grape]
        case .bathTime: return [.white]
        case .bounceHouse: return [Theme.sky, Theme.mint, Theme.grape, Theme.bubblegum]
        case .bedtime: return [Theme.butter]
        case .snowDay: return [.white]
        }
    }
}

/// A few things floating at the top of the room. A tap pops one with a sound, and another drifts
/// in a moment later. Nothing is counted and nothing runs out.
struct RoomPoppables: View {
    let scene: KidsScene
    var big: CGFloat = 1
    let popped: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How many times each place has been popped: the next one comes in a little to one side.
    @State private var rounds = [0, 0, 0, 0]
    @State private var gone: Set<Int> = []
    @State private var bob = false

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<4, id: \.self) { i in
                let size = 58 * big
                let shift = CGFloat((rounds[i] * 37 + i * 11) % 9 - 4) / 100
                let x = geo.size.width * (0.14 + 0.24 * CGFloat(i) + shift)
                let y = size * 0.8 + CGFloat((i * 53 + rounds[i] * 29) % 40) * big
                Button { pop(i) } label: {
                    Image(systemName: scene.popIcon)
                        .font(.system(size: size * 0.62, weight: .bold))
                        .foregroundStyle(scene.popColours[(i + rounds[i]) % scene.popColours.count])
                        .shadow(color: Theme.plum.opacity(0.18), radius: 3, y: 2)
                        .frame(width: size, height: size)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .scaleEffect(gone.contains(i) ? 1.7 : 1)
                .opacity(gone.contains(i) ? 0 : 1)
                .offset(y: bob && !reduceMotion ? -8 : 8)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.6 + 0.25 * Double(i)).repeatForever(autoreverses: true), value: bob)
                .animation(.easeOut(duration: 0.22), value: gone)
                .position(x: x, y: y)
                .disabled(gone.contains(i))
                .accessibilityLabel(Text(scene.name))
                .accessibilityIdentifier("kids-pop-\(i)")
            }
        }
        .onAppear { bob = true }
    }

    private func pop(_ i: Int) {
        guard !gone.contains(i) else { return }
        gone.insert(i)
        popped()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            rounds[i] += 1
            gone.remove(i)
        }
    }
}

/// What is behind the squishies in each room. Nothing here can be touched.
struct KidsBackdrop: View {
    let scene: KidsScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch scene {
            case .playMat:
                Theme.marshmallow
                mat
            case .bathTime:
                LinearGradient(colors: [Color(red: 0.78, green: 0.93, blue: 1), Color(red: 0.55, green: 0.80, blue: 0.98)],
                               startPoint: .top, endPoint: .bottom)
                Drifting(kind: .bubbles, still: reduceMotion)
            case .bounceHouse:
                stripes
            case .bedtime:
                RoomMood(mood: 1, colour: Color(red: 0.2, green: 0.17, blue: 0.32))
            case .snowDay:
                LinearGradient(colors: [Color(red: 0.74, green: 0.86, blue: 1), Color.white], startPoint: .top, endPoint: .bottom)
                Drifting(kind: .snow, still: reduceMotion)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A soft chequered play mat across the floor.
    private var mat: some View {
        GeometryReader { geo in
            let side = max(40, geo.size.width / 6)
            let rows = 3
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { col in
                            Rectangle()
                                .fill([Theme.mint, Theme.butter, Theme.sky, Theme.bubblegum][(row + col) % 4].opacity(0.28))
                                .frame(width: side, height: side * 0.7)
                        }
                    }
                }
            }
        }
    }

    private var stripes: some View {
        GeometryReader { geo in
            let count = 8
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    Rectangle().fill(i % 2 == 0 ? Theme.butter.opacity(0.55) : Theme.bubblegum.opacity(0.35))
                        .frame(width: geo.size.width / CGFloat(count))
                }
            }
        }
    }
}

/// Bubbles floating up or snow falling down, drawn from the clock so nothing is stored.
private struct Drifting: View {
    enum Kind { case bubbles, snow }
    let kind: Kind
    let still: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { timeline in
            Canvas { context, size in
                let t = still ? 0 : timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<26 {
                    let seed = Double(i)
                    let speed = 0.035 + 0.02 * (seed.truncatingRemainder(dividingBy: 5) / 5)
                    var along = (t * speed + seed * 0.137).truncatingRemainder(dividingBy: 1)
                    if kind == .bubbles { along = 1 - along }
                    let sway = sin(t * 0.6 + seed) * 0.03
                    let x = ((seed * 0.6180339).truncatingRemainder(dividingBy: 1) + sway) * size.width
                    let y = along * (size.height + 40) - 20
                    let r = kind == .bubbles ? 6 + seed.truncatingRemainder(dividingBy: 4) * 4 : 3 + seed.truncatingRemainder(dividingBy: 3) * 1.5
                    let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    if kind == .bubbles {
                        context.stroke(dot, with: .color(.white.opacity(0.85)), lineWidth: 2)
                        context.fill(dot, with: .color(.white.opacity(0.18)))
                    } else {
                        context.fill(dot, with: .color(.white.opacity(0.95)))
                    }
                }
            }
        }
    }
}
