import StoreKit
import SwiftUI

/// The grown-up gate: hold the button for three seconds while it fills, then answer a sum.
/// A small child can't do either by chance. It stands in front of the purchase and every link.
struct KidsGate: View {
    var onPass: () -> Void
    var onCancel: () -> Void
    @State private var held = false
    @State private var filling = false

    var body: some View {
        if held {
            ParentalGate(onPass: onPass, onCancel: onCancel)
        } else {
            VStack(spacing: 22) {
                Text("For grown-ups").font(Theme.title(26)).foregroundStyle(Theme.plum)
                Text("Hold the button for 3 seconds").font(Theme.body(17)).foregroundStyle(Theme.plum.opacity(0.75))
                ZStack {
                    Circle().fill(Color.white).frame(width: 132, height: 132)
                    Circle().trim(from: 0, to: filling ? 1 : 0)
                        .stroke(Theme.sky, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 120, height: 120)
                        .animation(filling ? .linear(duration: 3) : .easeOut(duration: 0.2), value: filling)
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 40)).foregroundStyle(Theme.plum)
                }
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: 3, maximumDistance: 60) {
                    held = true
                } onPressingChanged: { pressing in
                    filling = pressing
                }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text("Hold the button for 3 seconds"))
                .accessibilityIdentifier("kids-gate-hold")
                Button("Close", action: onCancel).buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                    .accessibilityIdentifier("kids-gate-close")
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.marshmallow.ignoresSafeArea())
        }
    }
}

/// Everything that is not for the child: the one purchase, restore, the privacy policy,
/// and putting made squishies away for good. Only ever opened through the gate.
struct GrownUpsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var purchases: PurchaseService
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    static let privacyURL = URL(string: "https://squishsort.app/workshop/privacy")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("For grown-ups").font(Theme.title(26)).foregroundStyle(Theme.plum)
                    Spacer()
                    Button("Close") { dismiss() }.buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                        .accessibilityIdentifier("kids-grownups-close")
                }
                card {
                    if model.ownsRemoveAds {
                        Text("Everything is unlocked. Thank you!").font(Theme.body(17)).foregroundStyle(Theme.plum)
                            .accessibilityIdentifier("kids-unlocked")
                    } else {
                        Text("Unlock everything").font(Theme.title(20)).foregroundStyle(Theme.plum)
                        Text("Every squishy from every world, all five rooms and the whole Workshop. One payment, no ads ever.")
                            .font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.8))
                        HStack(spacing: 10) {
                            Button {
                                busy = true
                                Task {
                                    await purchases.buy()
                                    busy = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text("Unlock everything")
                                    if let price = purchases.product?.displayPrice { Text(verbatim: price) }
                                }
                            }
                            .buttonStyle(SquishButtonStyle(fill: Theme.bubblegum))
                            .disabled(busy || purchases.product == nil)
                            .opacity(purchases.product == nil ? 0.5 : 1)
                            .accessibilityIdentifier("kids-unlock")
                            Button("Restore purchases") {
                                busy = true
                                Task {
                                    await purchases.restore()
                                    busy = false
                                }
                            }
                            .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                            .disabled(busy)
                            .accessibilityIdentifier("kids-restore")
                        }
                    }
                }
                if !model.progress.made.isEmpty {
                    card {
                        Text("Made squishies").font(Theme.title(20)).foregroundStyle(Theme.plum)
                        ForEach(model.progress.made) { made in
                            HStack(spacing: 12) {
                                SquishRefView(ref: made.ref).frame(width: 52, height: 52)
                                Text(verbatim: made.name).font(Theme.body(17)).foregroundStyle(Theme.plum)
                                Spacer()
                                Button("Delete") { model.deleteMade(made.id) }
                                    .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                            }
                        }
                    }
                }
                card {
                    Text("No ads. Nothing is collected.").font(Theme.body(15)).foregroundStyle(Theme.plum)
                    Link(destination: Self.privacyURL) {
                        Text("Privacy policy").font(Theme.body(15)).underline()
                    }
                    .accessibilityIdentifier("kids-privacy")
                    Text("Squish Sort is the puzzle game these squishies come from (for ages 9 and over).")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.7))
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.marshmallow.ignoresSafeArea())
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22).fill(.white))
    }
}
