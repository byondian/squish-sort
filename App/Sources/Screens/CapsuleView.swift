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
    @State private var shake: CGFloat = 0

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
                Text(verbatim: collectible.name(in: model.language)).font(Theme.title(30)).foregroundStyle(Theme.plum)
                if model.capsuleIsNew {
                    Text("NEW!").font(Theme.title(20)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(Capsule().fill(Theme.bubblegum))
                        .rotationEffect(.degrees(-6))
                        .transition(.scale(scale: 2.5).combined(with: .opacity))
                }
                Text(verbatim: bookCount).font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
                if asksToBeBuddy {
                    SpeechBubble(text: String(localized: "Can I be your Buddy?"))
                } else {
                    Text("Squeeze me!").font(Theme.body(18)).foregroundStyle(Theme.plum.opacity(0.7))
                }
                // Double capsule: opt-in ad, same odds. Gentle mode gets it only in the book.
                if !model.isGentleMode && model.bonusCapsuleWorld != nil && model.canWatchRewarded {
                    Button {
                        // The ad is presented once this screen has finished closing.
                        model.capsuleClosed(then: .bonusCapsule)
                    } label: { Label("Another capsule", systemImage: "play.rectangle.fill") }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
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
                    Button("Next", action: done).buttonStyle(SquishButtonStyle())
                        .accessibilityIdentifier("capsule-next")
                }
            } else {
                capsule
                    .rotationEffect(.degrees(angle))
                    .offset(x: shake)
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

    /// The first squishy out of a capsule (Peach Bun) offers to be the Buddy.
    private var asksToBeBuddy: Bool {
        collectible.id == CapsuleDrops.firstCapsuleID && model.offersFirstBuddy
    }

    /// "5/17" for the squishy's world shelf.
    private var bookCount: String {
        let shelf = model.roster.collectibles.filter { $0.world == collectible.world }
        return "\(shelf.filter { model.progress.collection.owns($0.id) }.count)/\(shelf.count)"
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
        // A quick shake before the pop.
        withAnimation(.easeInOut(duration: 0.06).repeatCount(5, autoreverses: true)) { shake = 9 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.35)) { opened = true }
        if model.capsuleIsNew {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { model.haptics.win() }
        }
    }
}
