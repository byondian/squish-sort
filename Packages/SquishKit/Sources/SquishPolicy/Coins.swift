/// Coins (Ian, 16 Nov 2026): earned by winning, also sold in packs. Spent on
/// hints, extra jars and board themes only. Nothing paid leads to squishies or
/// capsules: capsules come only from finishing levels, and every level can be
/// finished free (no move limit, unlimited retries, auto-softening).
public enum Coins {
    public static func earned(forWinWithStars stars: Int) -> Int { stars >= 3 ? 10 : 5 }

    public enum Item: String, Codable, CaseIterable, Sendable {
        case hint, extraJar, theme

        public var price: Int {
            switch self {
            case .hint: return 25
            case .extraJar: return 40
            case .theme: return 300
            }
        }
    }

    public struct Pack: Equatable, Sendable {
        public let productID: String
        public let coins: Int
    }

    public static let packs: [Pack] = [
        Pack(productID: "com.ianatkinson.squishsort.coins100", coins: 100),
        Pack(productID: "com.ianatkinson.squishsort.coins350", coins: 350),
        Pack(productID: "com.ianatkinson.squishsort.coins750", coins: 750),
    ]

    public static func pack(for productID: String) -> Pack? { packs.first { $0.productID == productID } }

    /// Free gift from the opt-in bonus gift box (a rewarded ad). Fixed, never random.
    public static let bonusGift = 20
}

public struct CoinWallet: Codable, Equatable, Sendable {
    public private(set) var balance = 0
    /// StoreKit transaction ids already credited, so a pack is never counted twice.
    public private(set) var creditedTransactions: Set<UInt64> = []

    public init() {}

    public mutating func earn(_ amount: Int) {
        balance += max(0, amount)
    }

    /// Returns false (and credits nothing) if this transaction was already counted.
    @discardableResult
    public mutating func credit(pack: Coins.Pack, transactionID: UInt64) -> Bool {
        guard !creditedTransactions.contains(transactionID) else { return false }
        creditedTransactions.insert(transactionID)
        balance += pack.coins
        return true
    }

    public func canAfford(_ item: Coins.Item) -> Bool { balance >= item.price }

    @discardableResult
    public mutating func spend(on item: Coins.Item) -> Bool {
        guard canAfford(item) else { return false }
        balance -= item.price
        return true
    }
}
