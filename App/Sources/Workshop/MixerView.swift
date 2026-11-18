import SwiftUI
import SquishPolicy
import SquishWorkshop

/// The Squishy Mixer (Workshop Pro): drop in two squishies and a new made one comes out, with the
/// shape and face of the first and the colours of the second. The two that went in are never
/// changed or used up, and what comes out is a made squishy, never a collectible.
struct MixerView: View {
    @EnvironmentObject var model: AppModel
    let done: (WorkshopDesign) -> Void
    let cancel: () -> Void

    @State private var first: String?
    @State private var second: String?
    @State private var whizzing = false

    private static let recipes: MixerRecipes? = {
        guard let url = Bundle.main.url(forResource: "mixer-recipes", withExtension: "json", subdirectory: "Content"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? MixerRecipes(json: data)
    }()
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    private var made: [String] { model.progress.made.map(\.ref) }
    private var owned: [String] {
        let mine = Set(made)
        return model.squeezables.filter { !mine.contains($0) && MixerView.recipes?.design(for: $0) != nil }
    }

    private func design(_ ref: String) -> WorkshopDesign? {
        if let m = model.progress.made.first(where: { $0.ref == ref }) { return m.workshopDesign }
        return MixerView.recipes?.design(for: ref)
    }

    /// Two different squishies, and at least one of them made by the player.
    private var ready: Bool {
        guard let first, let second, first != second else { return false }
        return made.contains(first) || made.contains(second)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Mixer").font(Theme.title(22)).foregroundStyle(Theme.plum)
                Spacer()
                IconButton(system: "xmark", action: cancel)
            }
            HStack(spacing: 14) {
                slot(first)
                Image(systemName: "plus").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.plum.opacity(0.6))
                slot(second)
            }
            .rotationEffect(.degrees(whizzing ? 4 : 0))
            .animation(whizzing ? .easeInOut(duration: 0.08).repeatForever(autoreverses: true) : .easeOut(duration: 0.1), value: whizzing)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("My squishies").font(Theme.title(16)).foregroundStyle(Theme.plum)
                    if made.isEmpty {
                        Text("Make your own squishy. It can be your Buddy and lives in your Squish Room.")
                            .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.7))
                    }
                    grid(made, key: "made")
                    if !owned.isEmpty {
                        Text("Collection").font(Theme.title(16)).foregroundStyle(Theme.plum)
                        grid(owned, key: "owned")
                    }
                }
            }
            Button(action: whizz) {
                Label("Mix", systemImage: "tornado").frame(maxWidth: .infinity)
            }
            .buttonStyle(SquishButtonStyle())
            .disabled(!ready || whizzing)
            .opacity(ready ? 1 : 0.5)
            .accessibilityIdentifier("ws-mixer-go")
        }
        .padding(16)
        .background(Theme.marshmallow.ignoresSafeArea())
    }

    private func slot(_ ref: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(Color.white)
            if let ref {
                SquishRefView(ref: ref).padding(8)
            } else {
                Image(systemName: "questionmark").font(.system(size: 26, weight: .heavy)).foregroundStyle(Theme.plum.opacity(0.25))
            }
        }
        .frame(width: 110, height: 110)
    }

    private func grid(_ refs: [String], key: String) -> some View {
        LazyVGrid(columns: MixerView.columns, spacing: 8) {
            ForEach(Array(refs.enumerated()), id: \.element) { index, ref in
                Button { pick(ref) } label: {
                    SquishRefView(ref: ref)
                        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit).padding(4)
                        .background(RoundedRectangle(cornerRadius: 14).fill(ref == first || ref == second ? Theme.butter : Color.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: model.displayName(for: ref)))
                .accessibilityIdentifier("ws-mixer-\(key)-\(index + 1)")
            }
        }
    }

    private func pick(_ ref: String) {
        model.haptics.lift()
        if first == ref {
            first = nil
        } else if second == ref {
            second = nil
        } else if first == nil {
            first = ref
        } else {
            second = ref
        }
    }

    private func whizz() {
        guard ready, let first, let second, let a = design(first), let b = design(second) else { return }
        whizzing = true
        model.sounds.play("drumroll")
        let wait: UInt64 = AppModel.isUITesting ? 200_000_000 : 1_300_000_000
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: wait)
            whizzing = false
            model.sounds.play("double_pop")
            model.haptics.complete()
            done(SquishyMixer.mix(.made(a), .made(b), seed: Int.random(in: 0..<1000)))
        }
    }
}
