import SwiftUI
import SquishPolicy

/// Squishy Maker: build your own from parts. Made squishies live in the Squish
/// Room and as a Buddy, never on boards or in capsules.
struct MakerView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = MadeSquishy(id: UUID().uuidString)
    @State private var problem = false

    private var worlds: Int { model.worldsCompleted }
    private var isSaved: Bool { model.progress.made.contains { $0.id == draft.id } }
    private var shelfFull: Bool { !isSaved && model.progress.made.count >= MakerParts.maxMade }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Squishy Maker")
            SoftSquishy(toy: "\(draft.shape)-\(draft.ears)-\(draft.accessory)", look: String(describing: draft), feel: .jelly) {
                MadeSquishyView(made: draft)
            }
            .frame(width: 200, height: 200)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Name", text: $draft.name)
                        .font(Theme.body(18))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onChange(of: draft.name) { _, new in
                            if new.count > NameFilter.maxLength { draft.name = String(new.prefix(NameFilter.maxLength)) }
                            problem = false
                        }
                    if problem {
                        Text(shelfFull ? LocalizedStringKey("Your shelf is full") : LocalizedStringKey("Try another name"))
                            .font(Theme.body(14)).foregroundStyle(Theme.bubblegum)
                    }
                    row("Shape", MadeSquishy.Shape.allCases, unlocked: MakerParts.shapes(worldsCompleted: worlds),
                        isOn: { draft.shape == $0 }) { $0.shape = $1 }
                    row("Colour", Array(MakerParts.palette.indices), unlocked: MakerParts.colors(worldsCompleted: worlds),
                        isOn: { draft.color == $0 }) { $0.color = $1 }
                    row("Eyes", MadeSquishy.Eyes.allCases, unlocked: MakerParts.eyes(worldsCompleted: worlds),
                        isOn: { draft.eyes == $0 }) { $0.eyes = $1 }
                    row("Mouth", MadeSquishy.Mouth.allCases, unlocked: MakerParts.mouths(worldsCompleted: worlds),
                        isOn: { draft.mouth == $0 }) { $0.mouth = $1 }
                    row("Ears", MadeSquishy.Ears.allCases, unlocked: MakerParts.ears(worldsCompleted: worlds),
                        isOn: { draft.ears == $0 }) { $0.ears = $1 }
                    row("Extras", MadeSquishy.Accessory.allCases, unlocked: MakerParts.accessories(worldsCompleted: worlds),
                        isOn: { draft.accessory == $0 }) { $0.accessory = $1 }
                    Text("More parts open with each world you finish.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                    HStack(spacing: 10) {
                        Button("Save") { save() }.buttonStyle(SquishButtonStyle())
                            .accessibilityIdentifier("maker-save")
                        if isSaved {
                            Button("New") { draft = MadeSquishy(id: UUID().uuidString) }
                                .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                            Button { model.deleteMade(draft.id); draft = MadeSquishy(id: UUID().uuidString) } label: {
                                Image(systemName: "trash.fill")
                            }
                            .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                            .accessibilityLabel(Text("Delete"))
                        }
                    }
                    if !model.progress.made.isEmpty {
                        Text("My squishies").font(Theme.title(18)).foregroundStyle(Theme.plum)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(model.progress.made) { made in
                                    VStack(spacing: 2) {
                                        MadeSquishyView(made: made).frame(width: 64, height: 64)
                                        Text(verbatim: made.name).font(Theme.body(11)).foregroundStyle(Theme.plum).lineLimit(1)
                                    }
                                    .frame(width: 72)
                                    .padding(4)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(made.id == draft.id ? Theme.butter : Color.white))
                                    .onTapGesture { draft = made; problem = false }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.marshmallow.ignoresSafeArea())
    }

    /// One row of options, each drawn as the squishy would look with it. Locked ones show a padlock.
    private func row<T: Hashable>(_ title: LocalizedStringKey, _ options: [T], unlocked: Int,
                                  isOn: @escaping (T) -> Bool,
                                  apply: @escaping (inout MadeSquishy, T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.title(16)).foregroundStyle(Theme.plum)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        let locked = index >= unlocked
                        Button {
                            apply(&draft, option)
                            model.haptics.lift()
                        } label: {
                            MadeSquishyView(made: preview(option, apply))
                                .frame(width: 56, height: 56)
                                .opacity(locked ? 0.3 : 1)
                                .overlay { if locked { Image(systemName: "lock.fill").foregroundStyle(Theme.plum.opacity(0.6)) } }
                                .background(RoundedRectangle(cornerRadius: 14).fill(isOn(option) ? Theme.butter : Color.white))
                        }
                        .buttonStyle(.plain)
                        .disabled(locked)
                    }
                }
            }
        }
    }

    private func preview<T>(_ option: T, _ apply: (inout MadeSquishy, T) -> Void) -> MadeSquishy {
        var copy = draft
        apply(&copy, option)
        return copy
    }

    private func save() {
        if model.saveMade(draft) {
            problem = false
            model.haptics.complete()
            // Keep the cleaned-up name in the editor.
            if let saved = model.progress.made.first(where: { $0.id == draft.id }) { draft = saved }
        } else {
            problem = true
        }
    }
}
