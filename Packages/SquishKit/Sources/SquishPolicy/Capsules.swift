import Foundation

public enum Rarity: String, Codable, CaseIterable, Sendable {
    case common, rare, ultra, secret
}

/// A squishy. `id` is stable forever: the January accounts update migrates
/// collections by these ids.
public struct Collectible: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var world: String
    public var rarity: Rarity
    /// Morph Squad: turns into another squishy from its world when squeezed.
    public var shapeshifter: Bool
    /// Translated names by language code (ja, ko, zh-Hant). `name` is English.
    public var names: [String: String]

    public func name(in language: String) -> String { names[language] ?? name }

    public init(id: String, name: String, world: String, rarity: Rarity, shapeshifter: Bool = false) {
        self.id = id
        self.name = name
        self.world = world
        self.rarity = rarity
        self.shapeshifter = shapeshifter
        self.names = [:]
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        world = try c.decode(String.self, forKey: .world)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        shapeshifter = try c.decodeIfPresent(Bool.self, forKey: .shapeshifter) ?? false
        names = try c.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
    }
}

/// A Squish Room toy (not a collectible; starters are owned by everyone).
public struct RoomToy: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var names: [String: String]?

    public func name(in language: String) -> String { names?[language] ?? name }
}

public struct Roster: Codable, Sendable {
    public var collectibles: [Collectible]
    public var squishRoomToys: [RoomToy]

    public init(collectibles: [Collectible], squishRoomToys: [RoomToy] = []) {
        self.collectibles = collectibles
        self.squishRoomToys = squishRoomToys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collectibles = try c.decode([Collectible].self, forKey: .collectibles)
        squishRoomToys = try c.decodeIfPresent([RoomToy].self, forKey: .squishRoomToys) ?? []
    }

    /// What a Morph Squad squishy turns into on a squeeze: another non-secret
    /// squishy from its own world, never itself.
    public func morphTarget<R: RandomNumberGenerator>(for id: String, using rng: inout R) -> Collectible? {
        guard let me = collectible(id), me.shapeshifter else { return nil }
        let pool = collectibles.filter { $0.world == me.world && $0.id != id && !$0.shapeshifter && $0.rarity != .secret }
        return pool.randomElement(using: &rng)
    }

    public func world(_ world: String, _ rarity: Rarity) -> [Collectible] {
        collectibles.filter { $0.world == world && $0.rarity == rarity }
    }

    public func collectible(_ id: String) -> Collectible? {
        collectibles.first { $0.id == id }
    }

    public static func decode(_ data: Data) throws -> Roster {
        try JSONDecoder().decode(Roster.self, from: data)
    }
}

/// The player's book. Counts above 1 are spares.
public struct CollectionState: Codable, Equatable, Sendable {
    public var owned: [String: Int] = [:]
    public var capsulesOpened: [String: Int] = [:]
    public var totalCapsules = 0
    /// Every squishy earned, in order, with where it came from. Kept for the
    /// January migration and for support.
    public var earnedLog: [Earned] = []

    public struct Earned: Codable, Equatable, Sendable {
        public var id: String
        public var source: String
    }

    public init() {}

    /// Missing fields fall back to defaults, so new fields never lose a collection.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owned = try c.decodeIfPresent([String: Int].self, forKey: .owned) ?? [:]
        capsulesOpened = try c.decodeIfPresent([String: Int].self, forKey: .capsulesOpened) ?? [:]
        totalCapsules = try c.decodeIfPresent(Int.self, forKey: .totalCapsules) ?? 0
        earnedLog = try c.decodeIfPresent([Earned].self, forKey: .earnedLog) ?? []
    }

    public func owns(_ id: String) -> Bool { (owned[id] ?? 0) > 0 }
    public var spareCount: Int { owned.values.reduce(0) { $0 + max(0, $1 - 1) } }

    /// Commons join the book the first time a jar of them is completed.
    /// Returns true only that first time. Rares and ultras come from capsules only.
    public mutating func addSorted(_ squishy: Collectible) -> Bool {
        guard squishy.rarity == .common, !owns(squishy.id) else { return false }
        owned[squishy.id] = 1
        earnedLog.append(.init(id: squishy.id, source: "sorted"))
        return true
    }
}

/// Capsule odds, out of rare + ultra. Remote config can change the numbers.
public struct CapsuleOdds: Codable, Equatable, Sendable {
    public var rare = 80
    public var ultra = 20

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rare = max(0, try c.decodeIfPresent(Int.self, forKey: .rare) ?? 80)
        ultra = max(0, try c.decodeIfPresent(Int.self, forKey: .ultra) ?? 20)
        if rare + ultra == 0 { rare = 80; ultra = 20 }
    }
}

/// Capsule drops (rules approved 16 Nov 2026).
///
/// - Capsules hold only rares and ultras, 80 / 20. Commons join the book by
///   sorting, and secrets never drop.
/// - The first capsule in the game is always Peach Bun.
/// - New first: a roll gives a squishy you don't own while that tier has one
///   in the world, then the other tier, and only then a duplicate.
/// - An ultra is guaranteed by the 7th capsule of each world.
///
/// Remove Ads and coins never affect drops: nothing here takes purchase state,
/// and capsules can't be bought, sped up or re-rolled with money.
public enum CapsuleDrops {
    public static let firstCapsuleID = "peach-bun"
    public static let ultraPityCapsule = 7
    public static let sparesPerReroll = 3

    public static func open<R: RandomNumberGenerator>(world: String, roster: Roster, state: inout CollectionState,
                                                      rng: inout R, odds: CapsuleOdds = CapsuleOdds()) -> Collectible? {
        var pick: Collectible?
        if state.totalCapsules == 0, let first = roster.collectible(firstCapsuleID) {
            pick = first
        } else {
            var tier = rollTier(&rng, odds: odds)
            let opened = state.capsulesOpened[world] ?? 0
            let hasUltra = roster.world(world, .ultra).contains { state.owns($0.id) }
            if opened + 1 >= ultraPityCapsule && !hasUltra { tier = .ultra }
            pick = choose(world: world, tier: tier, roster: roster, state: state, rng: &rng)
        }
        guard let got = pick else { return nil }
        state.owned[got.id, default: 0] += 1
        state.capsulesOpened[world, default: 0] += 1
        state.totalCapsules += 1
        state.earnedLog.append(.init(id: got.id, source: "capsule"))
        return got
    }

    /// Squish 3 spares together for a squishy you don't have yet in `world`.
    /// Returns nil (and spends nothing) if there aren't 3 spares or nothing is missing.
    public static func rerollSpares<R: RandomNumberGenerator>(world: String, roster: Roster, state: inout CollectionState,
                                                              rng: inout R, odds: CapsuleOdds = CapsuleOdds()) -> Collectible? {
        guard state.spareCount >= sparesPerReroll else { return nil }
        let missing = roster.collectibles.filter { $0.world == world && $0.rarity != .secret && !state.owns($0.id) }
        guard !missing.isEmpty else { return nil }
        var tier = rollTier(&rng, odds: odds)
        if !missing.contains(where: { $0.rarity == tier }) { tier = missing[0].rarity }
        let pool = missing.filter { $0.rarity == tier }
        let got = pool[Int(rng.next() % UInt64(pool.count))]
        // Spend spares from the most duplicated first.
        var toSpend = sparesPerReroll
        while toSpend > 0 {
            let spares = state.owned.filter { $0.value > 1 }
            guard let top = spares.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }) else { break }
            state.owned[top.key] = top.value - 1
            toSpend -= 1
        }
        state.owned[got.id, default: 0] += 1
        state.earnedLog.append(.init(id: got.id, source: "reroll"))
        return got
    }

    static func rollTier<R: RandomNumberGenerator>(_ rng: inout R, odds: CapsuleOdds = CapsuleOdds()) -> Rarity {
        let total = max(1, odds.rare + odds.ultra)
        return Int(rng.next() % UInt64(total)) < odds.rare ? .rare : .ultra
    }

    static func choose<R: RandomNumberGenerator>(world: String, tier: Rarity, roster: Roster,
                                                 state: CollectionState, rng: inout R) -> Collectible? {
        let other: Rarity = tier == .ultra ? .rare : .ultra
        for t in [tier, other] {
            let unowned = roster.world(world, t).filter { !state.owns($0.id) }
            if !unowned.isEmpty { return unowned[Int(rng.next() % UInt64(unowned.count))] }
        }
        // Everything is owned: a spare from the rolled tier.
        var pool = roster.world(world, tier)
        if pool.isEmpty { pool = roster.world(world, other) }
        guard !pool.isEmpty else { return nil }
        return pool[Int(rng.next() % UInt64(pool.count))]
    }
}

/// Small deterministic generator for tests and reproducible drops.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
