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
    @State private var squeeze: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if opened {
                SquishyView(id: collectible.id, rarity: collectible.rarity, squash: squeeze)
                    .frame(width: 220, height: 220)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in withAnimation(.easeOut(duration: 0.6)) { squeeze = 1 } }
                        .onEnded { _ in withAnimation(.spring(response: 1.2, dampingFraction: 0.6)) { squeeze = 0 } })
                Text(collectible.name).font(Theme.title(30)).foregroundStyle(Theme.plum)
                Text("Squeeze me!").font(Theme.body(18)).foregroundStyle(Theme.plum.opacity(0.7))
                // Double capsule: opt-in ad, same odds. Gentle mode gets it only in the book.
                if !model.isGentleMode && model.bonusCapsuleWorld != nil && model.canWatchRewarded {
                    Button {
                        done()
                        model.openBonusCapsule()
                    } label: { Label("Another capsule", systemImage: "play.rectangle.fill") }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                }
                Button("Next", action: done).buttonStyle(SquishButtonStyle())
            } else {
                capsule
                    .rotationEffect(.degrees(angle))
                    .gesture(DragGesture()
                        .onChanged { value in twist(value) }
                        .onEnded { _ in lastDrag = nil })
                // A tap works too, for VoiceOver and anyone who can't twist.
                Button { open() } label: {
                    Label("Twist to open!", systemImage: "arrow.clockwise")
                }
                .font(Theme.body(18)).foregroundStyle(Theme.plum)
                .accessibilityIdentifier("open-capsule")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.marshmallow.ignoresSafeArea())
    }

    private var capsule: some View {
        ZStack {
            Circle().fill(Theme.bubblegum).frame(width: 200, height: 200)
                .mask(Rectangle().frame(height: 100).offset(y: -50))
            Circle().fill(.white).frame(width: 200, height: 200)
                .mask(Rectangle().frame(height: 100).offset(y: 50))
            Circle().stroke(Theme.plum, lineWidth: 5).frame(width: 200, height: 200)
            Rectangle().fill(Theme.plum).frame(width: 200, height: 5)
        }
    }

    private func twist(_ value: DragGesture.Value) {
        let center = CGPoint(x: 100, y: 100)
        defer { lastDrag = value.location }
        guard let last = lastDrag else { return }
        let a1 = atan2(last.y - center.y, last.x - center.x)
        let a2 = atan2(value.location.y - center.y, value.location.x - center.x)
        var delta = (a2 - a1) * 180 / .pi
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        angle += abs(delta)
        if angle > 300 { open() }
    }

    private func open() {
        guard !opened else { return }
        model.haptics.complete()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.35)) { opened = true }
    }
}
