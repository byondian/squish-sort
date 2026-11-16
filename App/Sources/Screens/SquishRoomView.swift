import SwiftUI
import SquishPolicy

/// Squish Room: pick any squishy you own and play with it. No score, timer,
/// reward or ad, so it suits gentle mode.
struct SquishRoomView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: String?
    @State private var squash: CGFloat = 0
    @State private var stretch: CGFloat = 0
    @State private var wiggle = false
    @State private var mood = 0
    @State private var pressStart: Date?

    private let moods: [(LocalizedStringKey, Color)] = [
        ("Cream", Color("Marshmallow")), ("Night", Color(red: 0.2, green: 0.17, blue: 0.32)), ("Clouds", Color(red: 0.86, green: 0.93, blue: 1)),
    ]

    private var owned: [Collectible] {
        model.roster.collectibles.filter { model.progress.collection.owns($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Squish Room")
            Spacer()
            if let id = selected ?? owned.first?.id {
                let c = model.roster.collectible(id)
                SquishyView(id: id, rarity: c?.rarity ?? .common, squash: squash)
                    .frame(width: 280, height: 280)
                    .scaleEffect(x: 1 + stretch, y: 1 - stretch * 0.5)
                    .rotationEffect(.degrees(wiggle ? 6 : 0))
                    .gesture(squishGesture)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { tickle() })
            } else {
                Text("Win a capsule to fill the Squish Room").font(Theme.body()).foregroundStyle(Theme.plum)
            }
            Spacer()
            Picker("Mood", selection: $mood) {
                ForEach(moods.indices, id: \.self) { i in Text(moods[i].0).tag(i) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(owned, id: \.id) { c in
                        SquishyView(id: c.id, rarity: c.rarity).frame(width: 60, height: 60)
                            .onTapGesture { selected = c.id }
                    }
                }
                .padding(16)
            }
        }
        .background(moods[mood].1.ignoresSafeArea())
    }

    /// Hold to squeeze deeper the longer you press; drag to stretch; let go and it slowly rises.
    private var squishGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = Date()
                    model.haptics.lift()
                }
                let held = Date().timeIntervalSince(pressStart ?? Date())
                withAnimation(.easeOut(duration: 0.2)) {
                    squash = min(1, CGFloat(held) / 1.5)
                    stretch = max(-0.2, min(0.3, value.translation.width / 600))
                }
            }
            .onEnded { _ in
                pressStart = nil
                model.haptics.land()
                withAnimation(.spring(response: 1.6, dampingFraction: 0.55)) {
                    squash = 0
                    stretch = 0
                }
            }
    }

    private func tickle() {
        model.haptics.reject()
        withAnimation(.easeInOut(duration: 0.08).repeatCount(6, autoreverses: true)) { wiggle.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { wiggle = false }
    }
}
