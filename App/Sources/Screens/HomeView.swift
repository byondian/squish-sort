import SwiftUI
import SquishPolicy

/// Home: one big Play button, the Buddy, and a quiet button for each extra
/// once it unlocks. Nothing here pops up by itself.
struct HomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("\(model.progress.wallet.balance)", systemImage: "circle.hexagongrid.fill")
                    .font(Theme.body(17)).foregroundStyle(Theme.plum)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(.white))
                Spacer()
                IconButton(system: "gearshape.fill") { model.screen = .settings }
            }
            Spacer(minLength: 0)
            if model.isExtraUnlocked(.buddy) {
                BuddyHomeView()
            } else {
                Text(verbatim: "Squish Sort").font(Theme.title(40)).foregroundStyle(Theme.plum)
                SquishyView(id: model.progress.favouriteSquishy ?? "peach-bun", rarity: .rare)
                    .frame(width: 170, height: 170)
            }
            Spacer(minLength: 0)
            Button { model.screen = .level(model.progress.highestUnlocked) } label: {
                VStack(spacing: 2) {
                    Text("Play").font(Theme.title(30))
                    Text("Level \(model.progress.highestUnlocked + 1)").font(Theme.body(15)).opacity(0.85)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SquishButtonStyle())
            .accessibilityIdentifier("home-play")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                tile("Levels", "map.fill") { model.screen = .map }
                tile("Book", "book.fill") { model.screen = .book }
                if model.isExtraUnlocked(.squishRoom) {
                    tile("Squish Room", "hand.tap.fill", extra: .squishRoom) { model.open(.squishRoom) }
                }
                if model.isExtraUnlocked(.mysteryBag) {
                    tile("Mystery Bag", "bag.fill", extra: .mysteryBag) { model.open(.mysteryBag) }
                }
                if model.isExtraUnlocked(.maker) {
                    tile("Maker", "paintbrush.fill", extra: .maker) { model.open(.maker) }
                }
                // Under-13s reach the shop only from Settings.
                if !model.isGentleMode {
                    tile("Shop", "cart.fill") { model.screen = .shop }
                }
            }
        }
        .padding(16)
        .background(Theme.marshmallow.ignoresSafeArea())
        .onAppear { model.homeAppeared() }
    }

    private func tile(_ title: LocalizedStringKey, _ icon: String, extra: Extra? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22, weight: .bold))
                Text(title).font(Theme.body(13)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Theme.plum)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
            .overlay(alignment: .topTrailing) {
                if let extra, model.isNew(extra) { NewBadge().offset(x: 6, y: -6) }
            }
        }
        .buttonStyle(.plain)
    }
}

struct NewBadge: View {
    var body: some View {
        Text("new!").font(Theme.body(11)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Theme.bubblegum))
    }
}

/// The Buddy on the home screen: says hello, reacts to pokes, eats treats.
/// It never gets hungry, sick or sad.
struct BuddyHomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var picking = false
    @State private var bounce = false

    private let moods: [(id: String, face: String, label: LocalizedStringKey)] = [
        ("happy", "😊", "Happy"), ("okay", "🙂", "Okay"), ("sleepy", "😴", "Sleepy"), ("grumpy", "😠", "Grumpy"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            if let ref = model.progress.buddy.squishy {
                if let says = model.buddySays {
                    SpeechBubble(text: says).transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                if model.buddyAsksMood {
                    HStack(spacing: 12) {
                        ForEach(moods, id: \.id) { mood in
                            Button { withAnimation { model.answerMood(mood.id) } } label: {
                                Text(verbatim: mood.face).font(.system(size: 30))
                                    .frame(width: 52, height: 52)
                                    .background(Circle().fill(.white))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(mood.label))
                        }
                    }
                }
                SquishRefView(ref: ref, squash: bounce ? 0.7 : 0)
                    .frame(width: 180, height: 180)
                    .onTapGesture { poke() }
                    .accessibilityIdentifier("buddy")
                HStack(spacing: 8) {
                    Text(verbatim: model.progress.buddy.name).font(Theme.title(22))
                    Label("\(model.progress.buddy.hearts)", systemImage: "heart.fill")
                        .font(Theme.body(15)).foregroundStyle(Theme.bubblegum)
                }
                .foregroundStyle(Theme.plum)
                HStack(spacing: 10) {
                    Button { withAnimation { model.feedBuddy() }; squish() } label: {
                        Label("Treat ×\(model.progress.buddy.treats)", systemImage: "birthday.cake.fill")
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
                    .disabled(model.progress.buddy.treats == 0)
                    .opacity(model.progress.buddy.treats == 0 ? 0.5 : 1)
                    Button { picking = true } label: { Image(systemName: "pencil") }
                        .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                        .accessibilityLabel(Text("Change Buddy"))
                }
            } else {
                Text(verbatim: "Squish Sort").font(Theme.title(40)).foregroundStyle(Theme.plum)
                Button { picking = true } label: { Label("Choose your Buddy", systemImage: "heart.fill") }
                    .buttonStyle(SquishButtonStyle(fill: Theme.grape))
                    .overlay(alignment: .topTrailing) { if model.isNew(.buddy) { NewBadge().offset(x: 10, y: -10) } }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: model.buddySays)
        .sheet(isPresented: $picking) {
            BuddyPickerView { picking = false }.environmentObject(model)
        }
    }

    private func poke() {
        withAnimation { model.pokeBuddy() }
        squish()
    }

    private func squish() {
        withAnimation(.easeOut(duration: 0.12)) { bounce = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.45)) { bounce = false }
        }
    }
}

/// Pick any owned or made squishy as the Buddy (and avatar), and name it.
/// The name stays on this device.
struct BuddyPickerView: View {
    @EnvironmentObject var model: AppModel
    let done: () -> Void
    @State private var ref: String?
    @State private var name = ""
    @State private var badName = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Choose your Buddy").font(Theme.title(24)).foregroundStyle(Theme.plum).padding(.top, 20)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(model.squeezables, id: \.self) { item in
                        SquishRefView(ref: item)
                            .frame(width: 68, height: 68)
                            .background(RoundedRectangle(cornerRadius: 16).fill(item == ref ? Theme.butter : Color.white))
                            .onTapGesture {
                                ref = item
                                if name.isEmpty { name = model.displayName(for: item) }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
            TextField("Name", text: $name)
                .font(Theme.body(18))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .padding(.horizontal, 24)
                .onChange(of: name) { _, new in
                    if new.count > NameFilter.maxLength { name = String(new.prefix(NameFilter.maxLength)) }
                    badName = false
                }
            if badName {
                Text("Try another name").font(Theme.body(14)).foregroundStyle(Theme.bubblegum)
            }
            Button("Save") {
                guard let ref else { return }
                if model.setBuddy(ref: ref, name: name) { done() } else { badName = true }
            }
            .buttonStyle(SquishButtonStyle())
            .disabled(ref == nil)
            .opacity(ref == nil ? 0.5 : 1)
            .padding(.bottom, 16)
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .onAppear {
            ref = model.progress.buddy.squishy
            name = model.progress.buddy.name
        }
    }
}
