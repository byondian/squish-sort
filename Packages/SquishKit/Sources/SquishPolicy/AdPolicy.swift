/// Ad request settings per age group (tech design, ads stack table).
/// No ATT prompt ever, so no IDFA in any group.
public enum AdContentRating: String, Codable, Sendable {
    case g = "G", pg = "PG", t = "T", ma = "MA"
}

public enum ConsentStatus: String, Codable, Sendable {
    case unknown, required, obtained, denied, notRequired
}

public struct AdRequestPolicy: Equatable, Sendable {
    public var tagForChildDirectedTreatment: Bool
    public var tagForUnderAgeOfConsent: Bool
    public var maxAdContentRating: AdContentRating
    public var allowPersonalisedAds: Bool
    /// Show Google's UMP consent form (EEA/UK adults only).
    public var showConsentForm: Bool
}

public enum AdPolicy {
    /// Apple's tracking prompt: only for players who may get personalised ads,
    /// never in gentle mode, once, after the first win at level 5 or later.
    public static func shouldAskTracking(profile: AgeProfile?, levelWon: Int, alreadyAsked: Bool) -> Bool {
        guard let profile, profile.group != .child, profile.mayPersonaliseAds, !alreadyAsked else { return false }
        return levelWon >= 5
    }

    /// EEA plus UK and Switzerland, where the consent form applies.
    public static let consentRegion: Set<String> = [
        "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC",
        "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
        "SVN", "ESP", "SWE", "ISL", "LIE", "NOR", "GBR", "CHE",
    ]

    public static func isConsentRegion(_ storefront: String) -> Bool {
        consentRegion.contains(storefront.uppercased())
    }

    /// - Parameters:
    ///   - mayPersonalise: the player is at or over the local personalisation age.
    ///   - trackingAllowed: the player tapped Allow on Apple's ATT prompt.
    public static func requestPolicy(group: AgeGroup, storefront: String, consent: ConsentStatus,
                                     mayPersonalise: Bool = false, trackingAllowed: Bool = false) -> AdRequestPolicy {
        let region = isConsentRegion(storefront)
        let personalised = group != .child && mayPersonalise && trackingAllowed && (region ? consent == .obtained : true)
        switch group {
        case .child:
            return AdRequestPolicy(tagForChildDirectedTreatment: true, tagForUnderAgeOfConsent: false,
                                   maxAdContentRating: .g, allowPersonalisedAds: false, showConsentForm: false)
        case .teen:
            // Teens at or over the consent age can personalise after ATT Allow;
            // below it they're tagged under the age of consent.
            return AdRequestPolicy(tagForChildDirectedTreatment: false, tagForUnderAgeOfConsent: !mayPersonalise,
                                   maxAdContentRating: .pg, allowPersonalisedAds: personalised,
                                   showConsentForm: region && mayPersonalise)
        case .adult:
            return AdRequestPolicy(tagForChildDirectedTreatment: false, tagForUnderAgeOfConsent: false,
                                   maxAdContentRating: .pg, allowPersonalisedAds: personalised,
                                   showConsentForm: region)
        }
    }
}
