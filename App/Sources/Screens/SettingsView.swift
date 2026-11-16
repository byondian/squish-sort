import SwiftUI
import SquishPolicy

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var purchases: PurchaseService
    @State private var gateFor: GateAction?
    @State private var thanks = false

    enum GateAction: Identifiable {
        case buy, leaveGentleMode
        var id: Int { self == .buy ? 0 : 1 }
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            Form {
                Section {
                    Toggle("Sound", isOn: binding(\.soundOn))
                    Toggle("Music", isOn: binding(\.musicOn))
                    Toggle("Haptics", isOn: Binding(get: { model.progress.hapticsOn }, set: { model.setHaptics($0) }))
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
                    Link("Privacy policy", destination: URL(string: "https://squishsort.app/privacy")!)
                    Link("Support", destination: URL(string: "https://squishsort.app/support")!)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .tint(Theme.bubblegum)
        .foregroundStyle(Theme.plum)
        .sheet(item: $gateFor) { action in
            ParentalGate(onPass: {
                gateFor = nil
                switch action {
                case .buy: buy()
                case .leaveGentleMode: model.askAge = true
                }
            }, onCancel: { gateFor = nil })
        }
    }

    private func buy() {
        Task { thanks = await purchases.buy() }
    }

    private func binding(_ key: WritableKeyPath<PlayerProgress, Bool>) -> Binding<Bool> {
        Binding(get: { model.progress[keyPath: key] }, set: { v in model.update { $0[keyPath: key] = v } })
    }
}
