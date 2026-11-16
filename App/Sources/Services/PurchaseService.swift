import StoreKit

/// Remove Ads with StoreKit 2, checked on the device (tech design).
/// Refunds turn ads back on through Transaction.updates.
@MainActor
final class PurchaseService: ObservableObject {
    static let removeAdsID = "com.ianatkinson.squishsort.removeads"

    @Published private(set) var product: Product?
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
        product = try? await Product.products(for: [Self.removeAdsID]).first
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

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let t) = result else { return }
        if t.productID == Self.removeAdsID { set(t.revocationDate == nil) }
        await t.finish()
    }

    private func set(_ owns: Bool) {
        guard owns != ownsRemoveAds else { return }
        ownsRemoveAds = owns
        onChange?(owns)
    }
}
