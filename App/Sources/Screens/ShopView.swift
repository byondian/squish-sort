import StoreKit
import SwiftUI
import SquishPolicy

/// Coins and board themes. Squishies and capsules are never sold.
struct ShopView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var purchases: PurchaseService
    @State private var gateProduct: Product?
    @State private var passedProduct: Product?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Shop")
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        CoinIcon().foregroundStyle(Theme.butter)
                        Text("\(model.progress.wallet.balance) coins").font(Theme.title(24))
                    }
                    .foregroundStyle(Theme.plum)

                    Text("Coins").font(Theme.title(20)).foregroundStyle(Theme.plum)
                    Text("Coins are saved on this device only.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
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
                    Text("Win levels to earn coins too: 50 a win, 100 with three stars.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                    if model.offersAllowed { extras }

                    Text("Board themes").font(Theme.title(20)).foregroundStyle(Theme.plum)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(BoardTheme.allCases.filter { $0 != .gold || model.progress.ownedThemes.contains($0.rawValue) }) { theme in
                            themeCard(theme)
                        }
                    }
                    if model.buddyActive {
                        Text("For your Buddy").font(Theme.title(20)).foregroundStyle(Theme.plum)
                        HStack(spacing: 12) {
                            buddyItem(.treat, "Treat", "birthday.cake.fill")
                            buddyItem(.gift, "Gift", "gift.fill")
                        }
                        Text("Hearts teach your Buddy tricks and help it grow. Every level you win gives a free treat. Just for fun.")
                            .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                    }
                    Text("Coins buy hints, shuffles and themes. Squishies are earned by playing and are never for sale.")
                        .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.6))
                    if model.storefront.uppercased() == "KOR" || model.language == "ko" {
                        // Korea: a minor can cancel a purchase made without a guardian's consent, and the shop says so.
                        Text(verbatim: "미성년자가 법정대리인의 동의 없이 결제한 경우 본인 또는 법정대리인이 취소할 수 있습니다.")
                            .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.6))
                            .accessibilityIdentifier("shop-korea-minors")
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .sheet(item: $gateProduct, onDismiss: {
            // The purchase sheet waits until the gate has finished closing.
            if let product = passedProduct {
                passedProduct = nil
                buy(product)
            }
        }) { product in
            ParentalGate(onPass: { passedProduct = product; gateProduct = nil }, onCancel: { gateProduct = nil })
        }
    }

    /// The starter pack (once) and the piggy bank. Players of 13 and over only; no timers, nothing expires.
    @ViewBuilder private var extras: some View {
        if let starter = purchases.starterProduct, !model.progress.starterPackOwned {
            Button { Task { await purchases.buyExtra(starter) } } label: {
                HStack(spacing: 12) {
                    Text(verbatim: "🎁").font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Starter pack").font(Theme.title(18))
                        Text("\(StarterPack.coins) coins, \(StarterPack.hints) hints and the Golden Hour board. Once only.")
                            .font(Theme.body(13)).opacity(0.75).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Text(starter.displayPrice).font(Theme.title(17))
                }
            }
            .buttonStyle(SquishButtonStyle(fill: Theme.butter, text: Theme.plum))
            .accessibilityIdentifier("shop-starter")
        }
        if let piggy = purchases.piggyProduct {
            let bank = model.progress.piggy
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(verbatim: "🐷").font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Piggy bank").font(Theme.title(18))
                        Text("\(bank.coins) of \(PiggyBank.full) coins").font(Theme.body(14)).opacity(0.8)
                    }
                    Spacer(minLength: 4)
                }
                PiggyBar(fill: bank.fill)
                Text("Every win drops bonus coins in. It never loses coins. Break it open from \(PiggyBank.ready) coins.")
                    .font(Theme.body(13)).opacity(0.7)
                if bank.isReady {
                    Button { Task { await purchases.buyExtra(piggy) } } label: {
                        HStack {
                            Text("Break it open: \(bank.coins) coins")
                            Spacer()
                            Text(piggy.displayPrice)
                        }
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.bubblegum))
                    .accessibilityIdentifier("shop-piggy")
                }
            }
            .foregroundStyle(Theme.plum)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.plum.opacity(0.12), lineWidth: 2))
        }
    }

    private func buddyItem(_ item: Coins.Item, _ title: LocalizedStringKey, _ icon: String) -> some View {
        Button { model.buyForBuddyFromShop(item) } label: {
            VStack(spacing: 4) {
                Label(title, systemImage: icon)
                // Says what it gives: hearts fill the ring towards the Buddy's next trick.
                Label("+\(item == .gift ? BuddyState.heartsPerGift : BuddyState.heartsPerTreat)", systemImage: "heart.fill")
                    .font(Theme.body(14)).foregroundStyle(Theme.bubblegum)
                Text("\(item.price) coins").font(Theme.body(13)).opacity(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
        .disabled(!model.progress.wallet.canAfford(item))
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
                } else if theme == .gold {
                    Text("Starter pack").font(Theme.body(13)).opacity(0.7)
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

/// How full the piggy bank is. Only a bar: no price and no button outside the shop.
struct PiggyBar: View {
    let fill: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.plum.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [Theme.butter, Theme.bubblegum], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(10, geo.size.width * CGFloat(min(1, max(0, fill)))))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}
