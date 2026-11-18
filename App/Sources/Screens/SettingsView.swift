import SwiftUI
import SquishLevels
import SquishPolicy

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var purchases: PurchaseService
    @State private var gateFor: GateAction?
    /// What the gate allowed; runs once the gate sheet has finished closing.
    @State private var passed: GateAction?
    @State private var thanks = false

    enum GateAction: Identifiable {
        case buy, leaveGentleMode, squishyShop
        var id: Int {
            switch self {
            case .buy: return 0
            case .leaveGentleMode: return 1
            case .squishyShop: return 2
            }
        }
    }

    @State private var versionTaps = 0
    @State private var testerTools = false

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "Squish Sort \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            Form {
                Section {
                    level("Sounds", "speaker.wave.2.fill",
                          Binding(get: { model.progress.soundOn ? model.progress.soundLevel : 0 }, set: { model.setSoundLevel($0) }))
                        .accessibilityIdentifier("settings-sounds")
                    level("Music", "music.note",
                          Binding(get: { model.progress.musicOn ? model.progress.musicLevel : 0 }, set: { model.setMusicLevel($0) }))
                    Toggle("Squish sounds", isOn: Binding(get: { model.progress.squishSoundsOn }, set: { model.setSquishSounds($0) }))
                    Toggle("Buddy voice", isOn: Binding(get: { model.progress.buddyVoiceOn }, set: { model.setBuddyVoice($0) }))
                    Toggle("Haptics", isOn: Binding(get: { model.progress.hapticsOn }, set: { model.setHaptics($0) }))
                }
                Section {
                    Button { model.screen = .shop } label: {
                        Label("Shop: coins and board themes", systemImage: "bag.fill")
                    }
                }
                if model.showsSquishyShop {
                    Section {
                        Button { gateFor = .squishyShop } label: {
                            Label("Real squishies (website)", systemImage: "safari.fill")
                        }
                    } footer: {
                        Text("Opens squishsort.app in Safari. These are affiliate links: we may earn a little if you buy. Ask a grown-up first.")
                    }
                }
                Section {
                    if purchases.ownsRemoveAds {
                        Label("Ads removed. Thank you!", systemImage: "heart.fill")
                    } else {
                        Button {
                            if model.isGentleMode { gateFor = .buy } else { buy() }
                        } label: {
                            HStack {
                                Text("Remove Ads")
                                Spacer()
                                Text(purchases.product?.displayPrice ?? "").foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Restore purchases") { Task { await purchases.restore() } }
                } footer: {
                    Text("Remove Ads stops forced ads. Squishies are never for sale.")
                }
                Section {
                    if model.isGentleMode {
                        Label("Gentle mode is on", systemImage: "leaf.fill")
                        Button("Turn off gentle mode") { gateFor = .leaveGentleMode }
                    } else {
                        Button("Set up for a child") { model.switchToGentleMode() }
                    }
                } footer: {
                    Text("Gentle mode: fewer, child-safe ads, purchases behind a grown-up check, no countdowns.")
                }
                Section {
                    if model.showsPrivacyChoices {
                        Button("Privacy choices") { model.showPrivacyChoices() }
                    }
                    if !model.isGentleMode {
                        // Apple's own review page. Never offered in gentle mode.
                        Link("Rate Squish Sort", destination: URL(string: "https://apps.apple.com/app/id6835495515?action=write-review")!)
                    }
                    Link("Privacy policy", destination: URL(string: "https://squishsort.app/privacy")!)
                    Link("Support", destination: URL(string: "https://squishsort.app/support")!)
                }
                Section {
                    if testerTools {
                        // Test builds only: jump to the start of any world, or start over.
                        ForEach(LevelCatalog.worlds, id: \.self) { world in
                            Button { model.testerStart(world: world) } label: {
                                HStack(spacing: 4) {
                                    Text(verbatim: "Tester: start at")
                                    Text(AppModel.worldName(world))
                                }
                            }
                        }
                        Toggle(isOn: Binding(get: { model.testerOwnsEverything }, set: { model.testerSetOwnsEverything($0) })) {
                            Text(verbatim: "Tester: paid version (no ads, Workshop Pro)")
                        }
                        Button(role: .destructive) { model.testerReset() } label: {
                            Text(verbatim: "Tester: reset all progress")
                        }
                    }
                } footer: {
                    Text(verbatim: versionLine)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            versionTaps += 1
                            if versionTaps >= 7 && AppModel.isTesterBuild { testerTools = true }
                        }
                        .accessibilityIdentifier("version-line")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .tint(Theme.bubblegum)
        .foregroundStyle(Theme.plum)
        .sheet(item: $gateFor, onDismiss: afterGate) { action in
            ParentalGate(onPass: {
                passed = action
                gateFor = nil
            }, onCancel: { gateFor = nil })
        }
    }

    /// Nothing can be presented while the gate sheet is still closing, so the
    /// follow-up waits for its onDismiss.
    private func afterGate() {
        guard let action = passed else { return }
        passed = nil
        switch action {
        case .buy: buy()
        case .leaveGentleMode: model.askAge = true
        case .squishyShop: model.openSquishyShop()
        }
    }

    private func buy() {
        Task { thanks = await purchases.buy() }
    }

    /// A slider row: name, then the slider with a quiet and a loud mark.
    private func level(_ title: LocalizedStringKey, _ icon: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
            Slider(value: value, in: 0...1) { Text(title) }
                .tint(Theme.bubblegum)
        }
        .padding(.vertical, 2)
    }

    private func binding(_ key: WritableKeyPath<PlayerProgress, Bool>) -> Binding<Bool> {
        Binding(get: { model.progress[keyPath: key] }, set: { v in model.update { $0[keyPath: key] = v } })
    }
}
