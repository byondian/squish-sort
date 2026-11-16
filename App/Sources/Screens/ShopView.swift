import StoreKit
import SwiftUI
import SquishPolicy

/// Coins and board themes. Squishies and capsules are never sold.
struct ShopView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var purchases: PurchaseService
    @State private var gateProduct: Product?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Shop")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Image(systemName: "circle.hexagongrid.fill").foregroundStyle(Theme.butter)
                        Text("\(model.progress.wallet.balance) coins").font(Theme.title(24))
                    }
                    .foregroundStyle(Theme.plum)

                    Text("Coins").font(Theme.title(20)).foregroundStyle(Theme.plum)
                    ForEach(purchases.coinProducts, id: \.id) { product in
                        Button {
                            if model.isGentleMode { gateProduct = product } else { buy(product) }
                        } label: {
                            HStack {
                                Text("\(Coins.pack(for: product.id)?.coins ?? 0) coins")
                                Spacer()
                                Text(product.displayPrice)
                            }
                        }
                        .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
                    }
                    Text("Win levels to earn coins too: 5 a win, 10 with three stars.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))

                    Text("Board themes").font(Theme.title(20)).foregroundStyle(Theme.plum)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(BoardTheme.allCases) { theme in themeCard(theme) }
                    }
                    Text("Coins buy hints, extra jars and themes. Squishies are earned by playing and are never for sale.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                }
                .padding(16)
            }
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .sheet(item: $gateProduct) { product in
            ParentalGate(onPass: { gateProduct = nil; buy(product) }, onCancel: { gateProduct = nil })
        }
    }

    private func themeCard(_ theme: BoardTheme) -> some View {
        let owned = model.progress.ownedThemes.contains(theme.rawValue)
        let selected = model.boardTheme == theme
        return Button {
            if owned { model.selectTheme(theme) } else { model.buyTheme(theme) }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: theme.colors, startPoint: .top, endPoint: .bottom))
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Theme.bubblegum : Theme.plum.opacity(0.15), lineWidth: selected ? 4 : 2))
                Text(theme.name).font(Theme.body(15))
                if owned {
                    Text(selected ? "In use" : "Use").font(Theme.body(13)).opacity(0.7)
                } else {
                    Text("\(Coins.Item.theme.price) coins").font(Theme.body(13)).opacity(0.7)
                }
            }
            .foregroundStyle(Theme.plum)
        }
        .buttonStyle(.plain)
        .disabled(!owned && !model.progress.wallet.canAfford(.theme))
    }

    private func buy(_ product: Product) {
        Task { await purchases.buyCoins(product) }
    }
}

extension Product: @retroactive Identifiable {}
