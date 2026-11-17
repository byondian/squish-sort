import SwiftUI
import SquishPolicy
import SquishSoft

/// Squish Room: squeeze anything you own. No score, timer, reward or ad, so it
/// suits gentle mode. Morph Squad squishies change shape on a squeeze.
struct SquishRoomView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: String?
    /// What a Morph Squad squishy currently looks like, if it has changed.
    @State private var morphedInto: String?
    @State private var wiggles = 0
    @State private var mood = 0

    private let moods: [(LocalizedStringKey, Color)] = [
        ("Cream", Color("Marshmallow")), ("Night", Color(red: 0.2, green: 0.17, blue: 0.32)), ("Clouds", Color(red: 0.86, green: 0.93, blue: 1)),
    ]

    private var current: String? { selected ?? model.squeezables.first }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Squish Room")
            if let id = current {
                // Soft all the way through: knead it, pull it, pinch it, pick it up and throw it.
                SoftSquishy(toy: id, look: morphedInto ?? id, feel: model.feel(for: id), mode: .room, wiggles: wiggles,
                            onLetGo: { depth in morph(depth: depth) }, onDoubleTap: { tickle() }) {
                    SquishRefView(ref: morphedInto ?? id)
                        .colorMultiply(morphedInto == nil ? .white : Color(red: 0.86, green: 0.82, blue: 1))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: model.displayName(for: id)))
                .accessibilityIdentifier("room-squishy")
                .overlay(alignment: .topTrailing) { ClipControl(clips: model.clips, seconds: 8).padding(12) }
                Text(verbatim: model.displayName(for: id)).font(Theme.title(22))
                    .foregroundStyle(mood == 1 ? Color.white : Theme.plum)
                    .padding(.bottom, 10)
            } else {
                Spacer()
            }
            // Keepsakes from the worlds' big shows: tap one to watch its show again.
            if !model.progress.keepsakes.isEmpty {
                HStack(spacing: 12) {
                    ForEach(ShowPlan.worlds.filter { model.progress.finalesSeen.contains($0) }, id: \.self) { world in
                        Button { model.showingNews = .finale(world: world) } label: {
                            Text(verbatim: ShowPlan.load(world)?.keepsakeGlyph ?? "🎤").font(.system(size: 30))
                                .frame(width: 52, height: 52)
                                .background(Circle().fill(Color.white.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(ShowPlan.title(world)))
                    }
                }
                .padding(.bottom, 8)
            }
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
        .onAppear {
            // Came here from a "Squeeze me" button: start with that squishy.
            if let start = model.roomStart {
                selected = start
                model.roomStart = nil
            }
        }
    }

    /// Morph Squad: letting go of a deep squeeze turns it into someone from its own world; the next one turns it back.
    private func morph(depth: Double) {
        guard depth > SquishTuning.standard.morphOverDepth,
              let id = current, model.roster.collectible(id)?.shapeshifter == true else { return }
        morphedInto = morphedInto == nil ? model.morphTarget(for: id)?.id : nil
    }

    private func tickle() {
        model.haptics.reject()
        wiggles += 1
    }
}
