import StoreKit
import SquishPolicy

/// Remove Ads with StoreKit 2, checked on the device (tech design).
/// Refunds turn ads back on through Transaction.updates.
@MainActor
final class PurchaseService: ObservableObject {
    static let removeAdsID = "com.ianatkinson.squishsort.removeads"

    @Published private(set) var product: Product?
    @Published private(set) var coinProducts: [Product] = []
    /// A coin pack was paid for: credit it (idempotent by transaction id).
    var onCoins: ((Coins.Pack, UInt64) -> Void)?
    @Published private(set) var ownsRemoveAds: Bool
    var onChange: ((Bool) -> Void)?
    private var updates: Task<Void, Never>?

    init(cachedOwnership: Bool) {
        ownsRemoveAds = cachedOwnership
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    deinit { updates?.cancel() }

    func start() async {
        let ids = [Self.removeAdsID] + Coins.packs.map(\.productID)
        let all = (try? await Product.products(for: ids)) ?? []
        product = all.first { $0.id == Self.removeAdsID }
        coinProducts = Coins.packs.compactMap { pack in all.first { $0.id == pack.productID } }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owns = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.removeAdsID, t.revocationDate == nil {
                owns = true
            }
        }
        set(owns)
    }

    @discardableResult
    func buy() async -> Bool {
        guard let product else { return false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    set(true)
                    return true
                }
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    @discardableResult
    func buyCoins(_ product: Product) async -> Bool {
        do {
            if case .success(let verification) = try await product.purchase(),
               case .verified(let t) = verification, onCoins != nil {
                credit(t)
                await t.finish()
                return true
            }
        } catch {}
        return false
    }

    /// Credits a coin pack once (the wallet ignores a transaction id it has seen).
    /// A refunded pack isn't taken back out of the balance: the coins may already
    /// be spent, and a negative balance would punish the player for Apple's refund.
    private func credit(_ t: Transaction) {
        if let pack = Coins.pack(for: t.productID), t.revocationDate == nil {
            onCoins?(pack, t.id)
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let t) = result else { return }
        if t.productID == Self.removeAdsID {
            set(t.revocationDate == nil)
        } else {
            // Never finish a coin purchase nobody could credit: StoreKit will deliver it again.
            guard onCoins != nil else { return }
            credit(t)
        }
        await t.finish()
    }

    private func set(_ owns: Bool) {
        guard owns != ownsRemoveAds else { return }
        ownsRemoveAds = owns
        onChange?(owns)
    }
}
