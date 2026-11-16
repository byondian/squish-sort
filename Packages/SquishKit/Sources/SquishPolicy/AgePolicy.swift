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

/// What the app keeps about age: the group and a coarse band, never the birth year.
public struct AgeProfile: Codable, Equatable, Sendable {
    /// The group worked out at the age step. Use `AgePolicy.group(of:storefront:)`
    /// for decisions, which re-checks it against the storefront the player is in now.
    public var group: AgeGroup
    public var source: AgeSource
    /// Storefront at the age step ("" when it wasn't known yet). For support only.
    public var storefront: String
    /// "At least this old", kept only from 13 up and capped at 18, so nothing
    /// finer than a band is stored. Nil for children and unknown ages. Ad
    /// personalisation and the child cut-off are re-derived from this and the
    /// current storefront every time, never frozen at the age step.
    public var ageBand: Int?

    public init(group: AgeGroup, source: AgeSource, storefront: String, lowerBound: Int? = nil) {
        self.group = group
        self.source = source
        self.storefront = storefront
        self.ageBand = AgeProfile.band(lowerBound, group: group)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        group = try c.decode(AgeGroup.self, forKey: .group)
        source = try c.decodeIfPresent(AgeSource.self, forKey: .source) ?? .skipped
        storefront = try c.decodeIfPresent(String.self, forKey: .storefront) ?? ""
        ageBand = AgeProfile.band(try c.decodeIfPresent(Int.self, forKey: .ageBand), group: group)
    }

    private static func band(_ lowerBound: Int?, group: AgeGroup) -> Int? {
        guard group != .child, let lowerBound, lowerBound >= 13 else { return nil }
        return min(lowerBound, AgePolicy.adultAge)
    }

    public var isGentleMode: Bool { group == .child }
}

public enum AgePolicy {
    /// Age gates to ask Apple's Declared Age Range API for (iOS 26+). Apple needs
    /// every range to span at least two years, so 13 and 14 can't both be gates:
    /// the child cut-off for the storefront comes first, then 16 and 18.
    public static func declaredAgeGates(storefront: String) -> [Int] {
        [childCutoff(storefront: storefront), 16, adultAge]
    }
    /// Teens are everyone from the child cut-off up to this age. Treating all
    /// under-18s as teens keeps ads non-personalised for them everywhere
    /// (UK Children's Code, EU consent ages from 13 to 16).
    public static let adultAge = 18

    /// Under this age is a child. Storefront codes are ISO 3166 alpha-3, as StoreKit gives them.
    /// An unknown storefront ("") gets the strictest cut-off, Korea's 14.
    public static func childCutoff(storefront: String) -> Int {
        let code = storefront.uppercased()
        return code == "KOR" || code.isEmpty ? 14 : 13
    }

    /// The group to act on now. The stored group can only get younger here: a
    /// 13-year-old who was a teen on the US storefront is a child on the Korean
    /// one, and anyone without a known age band is never treated as older.
    public static func group(of profile: AgeProfile?, storefront: String) -> AgeGroup {
        guard let profile else { return .child }
        if profile.group == .teen, let band = profile.ageBand, band < childCutoff(storefront: storefront) { return .child }
        return profile.group
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
    /// Switzerland has no fixed age in law, so it uses the default.
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
    /// An unknown storefront ("") also means 18: it might be the UK.
    public static func personalisationAge(storefront: String) -> Int {
        let code = storefront.uppercased()
        return code == "GBR" || code.isEmpty ? adultAge : consentAge(storefront: code)
    }

    /// Whether this player may be offered personalised ads on the storefront they
    /// are in now. Worked out fresh each time, so a move to the UK or a storefront
    /// that only becomes known later can't leave an old "yes" behind.
    public static func mayPersonaliseAds(profile: AgeProfile?, storefront: String) -> Bool {
        guard let profile, group(of: profile, storefront: storefront) != .child, let band = profile.ageBand else { return false }
        return band >= personalisationAge(storefront: storefront)
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
