import SwiftUI
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

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            Form {
                Section {
                    Toggle("Sound", isOn: Binding(get: { model.progress.soundOn }, set: { model.setSound($0) }))
                    Toggle("Music", isOn: binding(\.musicOn))
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
                    Link("Privacy policy", destination: URL(string: "https://squishsort.app/privacy")!)
                    Link("Support", destination: URL(string: "https://squishsort.app/support")!)
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

    private func binding(_ key: WritableKeyPath<PlayerProgress, Bool>) -> Binding<Bool> {
        Binding(get: { model.progress[keyPath: key] }, set: { v in model.update { $0[keyPath: key] = v } })
    }
}
