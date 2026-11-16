/// Age groups drive ads, purchases and pressure mechanics.
///
/// Compliance rules (launch plan must-fixes):
/// - Nothing that sends data (ads SDK, telemetry) starts before the age step.
/// - Unknown age, a skipped question or an unclear answer is treated as a child.
/// - Korea uses an under-14 child cut-off; everywhere else under-13.
/// - Moving to an older group needs the parental gate; moving younger never does.
public enum AgeGroup: String, Codable, CaseIterable, Sendable, Comparable {
    case child, teen, adult

    private var rank: Int {
        switch self {
        case .child: return 0
        case .teen: return 1
        case .adult: return 2
        }
    }

    public static func < (a: AgeGroup, b: AgeGroup) -> Bool { a.rank < b.rank }
}

/// Inclusive age bounds, as Apple's Declared Age Range API reports them
/// (nil means open-ended on that side).
public struct AgeRange: Equatable, Sendable {
    public var lower: Int?
    public var upper: Int?

    public init(lower: Int?, upper: Int?) {
        self.lower = lower
        self.upper = upper
    }
}

public enum AgeSource: String, Codable, Sendable {
    case declaredAgeRange, birthYear, skipped, parentSetGentleMode
}

/// What the app keeps about age: the group only, never the birth year.
public struct AgeProfile: Codable, Equatable, Sendable {
    public var group: AgeGroup
    public var source: AgeSource
    public var storefront: String

    public init(group: AgeGroup, source: AgeSource, storefront: String) {
        self.group = group
        self.source = source
        self.storefront = storefront
    }

    public var isGentleMode: Bool { group == .child }
}

public enum AgePolicy {
    /// Thresholds to ask the Declared Age Range API for (iOS 26+).
    public static let declaredAgeThresholds = [13, 14, 18]
    /// Teens are everyone from the child cut-off up to this age. Treating all
    /// under-18s as teens keeps ads non-personalised for them everywhere
    /// (UK Children's Code, EU consent ages from 13 to 16).
    public static let adultAge = 18

    /// Under this age is a child. Storefront codes are ISO 3166 alpha-3, as StoreKit gives them.
    public static func childCutoff(storefront: String) -> Int {
        storefront.uppercased() == "KOR" ? 14 : 13
    }

    /// Group from an age range. Anything uncertain resolves to the younger group.
    public static func group(for range: AgeRange?, storefront: String) -> AgeGroup {
        guard let range, let lower = range.lower, lower >= 0 else { return .child }
        if lower >= adultAge { return .adult }
        if lower >= childCutoff(storefront: storefront) { return .teen }
        return .child
    }

    /// Range from a birth year. The birthday may not have happened yet this year,
    /// so the lower bound is one less than the year difference.
    public static func range(birthYear: Int?, currentYear: Int) -> AgeRange? {
        guard let birthYear, birthYear <= currentYear, currentYear - birthYear <= 120 else { return nil }
        let oldest = currentYear - birthYear
        return AgeRange(lower: max(0, oldest - 1), upper: oldest)
    }

    /// Changing group: older needs the parental gate, younger is always allowed.
    public static func needsParentalGate(from: AgeGroup, to: AgeGroup) -> Bool {
        to > from
    }
}
