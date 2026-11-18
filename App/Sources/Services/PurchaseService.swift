import StoreKit
import SquishPolicy

/// Remove Ads with StoreKit 2, checked on the device (tech design).
/// Refunds turn ads back on through Transaction.updates.
@MainActor
final class PurchaseService: ObservableObject {
    #if KIDS
    /// Squishy Workshop sells one thing, once: "Unlock everything". It sits behind the grown-up gate.
    static let removeAdsID = "com.ianatkinson.squishyworkshop.unlock"
    #else
    static let removeAdsID = "com.ianatkinson.squishsort.removeads"
    #endif

    @Published private(set) var product: Product?
    @Published private(set) var coinProducts: [Product] = []
    /// A coin pack was paid for: credit it (idempotent by transaction id).
    var onCoins: ((Coins.Pack, UInt64) -> Void)?
    /// The one-time starter pack and the piggy bank (13 and over; the screens decide who sees them).
    @Published private(set) var starterProduct: Product?
    @Published private(set) var piggyProduct: Product?
    var onStarter: ((UInt64) -> Void)?
    var onPiggy: ((UInt64) -> Void)?
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
        #if KIDS
        let ids = [Self.removeAdsID]
        #else
        let ids = [Self.removeAdsID, StarterPack.productID, PiggyBank.productID] + Coins.packs.map(\.productID)
        #endif
        let all = (try? await Product.products(for: ids)) ?? []
        product = all.first { $0.id == Self.removeAdsID }
        coinProducts = Coins.packs.compactMap { pack in all.first { $0.id == pack.productID } }
        starterProduct = all.first { $0.id == StarterPack.productID }
        piggyProduct = all.first { $0.id == PiggyBank.productID }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owns = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            if t.productID == Self.removeAdsID { owns = true }
            // The starter pack is bought once and comes back with Restore; the wallet counts it once.
            if t.productID == StarterPack.productID { onStarter?(t.originalID) }
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

    /// The starter pack or the piggy bank. Credited once by transaction id, like a coin pack.
    @discardableResult
    func buyExtra(_ product: Product) async -> Bool {
        do {
            if case .success(let verification) = try await product.purchase(),
               case .verified(let t) = verification, onStarter != nil, onPiggy != nil {
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
        guard t.revocationDate == nil else { return }
        if let pack = Coins.pack(for: t.productID) {
            onCoins?(pack, t.id)
        } else if t.productID == StarterPack.productID {
            onStarter?(t.originalID)
        } else if t.productID == PiggyBank.productID {
            onPiggy?(t.id)
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
            guard onCoins != nil, onStarter != nil, onPiggy != nil else { return }
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
