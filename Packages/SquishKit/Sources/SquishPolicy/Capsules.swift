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

    public init(id: String, name: String, world: String, rarity: Rarity, shapeshifter: Bool = false) {
        self.id = id
        self.name = name
        self.world = world
        self.rarity = rarity
        self.shapeshifter = shapeshifter
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        world = try c.decode(String.self, forKey: .world)
        rarity = try c.decode(Rarity.self, forKey: .rarity)
        shapeshifter = try c.decodeIfPresent(Bool.self, forKey: .shapeshifter) ?? false
    }
}

/// A Squish Room toy (not a collectible; starters are owned by everyone).
public struct RoomToy: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
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
    public var rareOrBetterOpened: [String: Int] = [:]
    public var totalCapsules = 0
    /// Every squishy earned, in order, with where it came from. Kept for the
    /// January migration and for support.
    public var earnedLog: [Earned] = []

    public struct Earned: Codable, Equatable, Sendable {
        public var id: String
        public var source: String
    }

    public init() {}

    public func owns(_ id: String) -> Bool { (owned[id] ?? 0) > 0 }
    public var spareCount: Int { owned.values.reduce(0) { $0 + max(0, $1 - 1) } }
}

/// Capsule drops (game design doc).
///
/// - Odds 70 / 25 / 5 for common / rare / ultra-rare; secrets never drop.
/// - The first capsule in the game is always Peach Bun.
/// - A rare or better is guaranteed by the 4th capsule of each world.
/// - New first: a roll gives a squishy you don't own while that tier has one.
///
/// Remove Ads never affects drops: nothing here takes purchase state, and
/// capsules can't be bought, sped up or re-rolled with money.
public enum CapsuleDrops {
    public static let firstCapsuleID = "peach-bun"
    public static let pityCapsule = 4
    public static let odds: [(Rarity, Int)] = [(.common, 70), (.rare, 25), (.ultra, 5)]
    public static let sparesPerReroll = 3

    public static func open<R: RandomNumberGenerator>(world: String, roster: Roster,
                                                      state: inout CollectionState, rng: inout R) -> Collectible? {
        var pick: Collectible?
        if state.totalCapsules == 0, let first = roster.collectible(firstCapsuleID) {
            pick = first
        } else {
            var tier = rollTier(&rng)
            let opened = state.capsulesOpened[world] ?? 0
            if opened + 1 >= pityCapsule && (state.rareOrBetterOpened[world] ?? 0) == 0 && tier == .common {
                tier = .rare
            }
            pick = choose(world: world, tier: tier, roster: roster, state: state, rng: &rng)
        }
        guard let got = pick else { return nil }
        state.owned[got.id, default: 0] += 1
        state.capsulesOpened[world, default: 0] += 1
        if got.rarity != .common { state.rareOrBetterOpened[world, default: 0] += 1 }
        state.totalCapsules += 1
        state.earnedLog.append(.init(id: got.id, source: "capsule"))
        return got
    }

    /// Squish 3 spares together for a squishy you don't have yet in `world`.
    /// Returns nil (and spends nothing) if there aren't 3 spares or nothing is missing.
    public static func rerollSpares<R: RandomNumberGenerator>(world: String, roster: Roster,
                                                              state: inout CollectionState, rng: inout R) -> Collectible? {
        guard state.spareCount >= sparesPerReroll else { return nil }
        let missing = roster.collectibles.filter { $0.world == world && $0.rarity != .secret && !state.owns($0.id) }
        guard !missing.isEmpty else { return nil }
        var tier = rollTier(&rng)
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

    static func rollTier<R: RandomNumberGenerator>(_ rng: inout R) -> Rarity {
        let total = odds.reduce(0) { $0 + $1.1 }
        var r = Int(rng.next() % UInt64(total))
        for (tier, weight) in odds {
            if r < weight { return tier }
            r -= weight
        }
        return .common
    }

    static func choose<R: RandomNumberGenerator>(world: String, tier: Rarity, roster: Roster,
                                                 state: CollectionState, rng: inout R) -> Collectible? {
        var pool = roster.world(world, tier)
        if pool.isEmpty { pool = roster.world(world, .common) }
        guard !pool.isEmpty else { return nil }
        let unowned = pool.filter { !state.owns($0.id) }
        let from = unowned.isEmpty ? pool : unowned
        return from[Int(rng.next() % UInt64(from.count))]
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
