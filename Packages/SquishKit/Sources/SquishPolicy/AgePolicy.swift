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
    /// At or over the age where personalised ads may be offered (after ATT Allow).
    /// Stored as a yes/no only; the age itself is never kept.
    public var mayPersonaliseAds: Bool

    public init(group: AgeGroup, source: AgeSource, storefront: String, mayPersonaliseAds: Bool = false) {
        self.group = group
        self.source = source
        self.storefront = storefront
        self.mayPersonaliseAds = mayPersonaliseAds && group != .child
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = try c.decode(AgeGroup.self, forKey: .group)
        source = try c.decode(AgeSource.self, forKey: .source)
        storefront = try c.decode(String.self, forKey: .storefront)
        mayPersonaliseAds = (try c.decodeIfPresent(Bool.self, forKey: .mayPersonaliseAds) ?? false) && group != .child
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

    /// Age of digital consent (GDPR Art. 8 national ages; 13 elsewhere, 14 in Korea).
    public static func consentAge(storefront: String) -> Int {
        let code = storefront.uppercased()
        return max(consentAges[code] ?? 13, childCutoff(storefront: code))
    }

    static let consentAges: [String: Int] = [
        "AUT": 14, "BEL": 13, "BGR": 14, "HRV": 16, "CYP": 14, "CZE": 15, "DNK": 13,
        "EST": 13, "FIN": 13, "FRA": 15, "DEU": 16, "GRC": 15, "HUN": 16, "IRL": 16,
        "ITA": 14, "LVA": 13, "LTU": 14, "LUX": 16, "MLT": 13, "NLD": 16, "POL": 16,
        "PRT": 13, "ROU": 16, "SVK": 16, "SVN": 15, "ESP": 14, "SWE": 13,
        "ISL": 13, "LIE": 16, "NOR": 13, "GBR": 13, "KOR": 14,
    ]

    /// Youngest age that may be offered personalised ads (Ian, 16 Nov 2026: the
    /// local consent age). The UK stays at 18 because the Children's Code expects
    /// profiling off for all under-18s.
    public static func personalisationAge(storefront: String) -> Int {
        storefront.uppercased() == "GBR" ? adultAge : consentAge(storefront: storefront)
    }

    /// True only when the whole range is at or over the personalisation age.
    public static func mayPersonaliseAds(range: AgeRange?, storefront: String) -> Bool {
        guard let lower = range?.lower else { return false }
        return lower >= personalisationAge(storefront: storefront)
    }

    /// Changing group: older needs the parental gate, younger is always allowed.
    public static func needsParentalGate(from: AgeGroup, to: AgeGroup) -> Bool {
        to > from
    }
}
