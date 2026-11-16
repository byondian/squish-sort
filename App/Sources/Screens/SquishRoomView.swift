import SwiftUI
import SquishPolicy

/// Squish Room: squeeze anything you own. No score, timer, reward or ad, so it
/// suits gentle mode. Morph Squad squishies change shape on a squeeze.
struct SquishRoomView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: String?
    /// What a Morph Squad squishy currently looks like, if it has changed.
    @State private var morphedInto: String?
    @State private var squash: CGFloat = 0
    @State private var stretch: CGFloat = 0
    @State private var wiggle = false
    @State private var mood = 0
    @State private var pressStart: Date?

    private let moods: [(LocalizedStringKey, Color)] = [
        ("Cream", Color("Marshmallow")), ("Night", Color(red: 0.2, green: 0.17, blue: 0.32)), ("Clouds", Color(red: 0.86, green: 0.93, blue: 1)),
    ]

    private var current: String? { selected ?? model.squeezables.first }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Squish Room")
            Spacer()
            if let id = current {
                SquishRefView(ref: morphedInto ?? id, squash: squash)
                    .colorMultiply(morphedInto == nil ? .white : Color(red: 0.86, green: 0.82, blue: 1))
                    .frame(width: 280, height: 280)
                    .scaleEffect(x: 1 + stretch, y: 1 - stretch * 0.5)
                    .rotationEffect(.degrees(wiggle ? 6 : 0))
                    .gesture(squishGesture)
                    .simultaneousGesture(TapGesture(count: 2).onEnded { tickle() })
                    .accessibilityIdentifier("room-squishy")
                Text(verbatim: model.displayName(for: id)).font(Theme.title(22))
                    .foregroundStyle(mood == 1 ? Color.white : Theme.plum)
            }
            Spacer()
            Picker("Mood", selection: $mood) {
                ForEach(moods.indices, id: \.self) { i in Text(moods[i].0).tag(i) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.squeezables, id: \.self) { item in
                        SquishRefView(ref: item).frame(width: 60, height: 60)
                            .onTapGesture {
                                selected = item
                                morphedInto = nil
                            }
                    }
                }
                .padding(16)
            }
        }
        .background(moods[mood].1.ignoresSafeArea())
    }

    /// Hold to squeeze deeper the longer you press; drag to stretch; let go and it springs back.
    private var squishGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if pressStart == nil {
                    pressStart = Date()
                    model.haptics.lift()
                }
                let held = Date().timeIntervalSince(pressStart ?? Date())
                withAnimation(.easeOut(duration: 0.2)) {
                    squash = max(0.35, min(1, CGFloat(held) / 1.5))
                    stretch = max(-0.2, min(0.3, value.translation.width / 600))
                }
            }
            .onEnded { _ in
                pressStart = nil
                model.haptics.land()
                morph()
                withAnimation(.spring(response: 0.9, dampingFraction: 0.5)) {
                    squash = 0
                    stretch = 0
                }
            }
    }

    /// Morph Squad: a squeeze turns it into someone from its own world; the next squeeze turns it back.
    private func morph() {
        guard let id = current, model.roster.collectible(id)?.shapeshifter == true else { return }
        morphedInto = morphedInto == nil ? model.morphTarget(for: id)?.id : nil
    }

    private func tickle() {
        model.haptics.reject()
        withAnimation(.easeInOut(duration: 0.08).repeatCount(6, autoreverses: true)) { wiggle.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { wiggle = false }
    }
}
