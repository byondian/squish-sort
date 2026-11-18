/// Ad request settings per age group (tech design, ads stack table).
/// Personalised ads need three things: old enough for the storefront, Allow on
/// Apple's tracking prompt, and consent where the consent form applies.
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
    /// never in gentle mode, once, at the start of level 7 (or the first level
    /// started after it), with the board already on screen.
    public static let trackingPromptLevel = 7

    public static func shouldAskTracking(profile: AgeProfile?, storefront: String, levelStarting: Int, alreadyAsked: Bool) -> Bool {
        guard AgePolicy.mayPersonaliseAds(profile: profile, storefront: storefront), !alreadyAsked else { return false }
        return levelStarting >= trackingPromptLevel
    }

    /// The request policy for this player right now, from their profile and the current storefront.
    public static func requestPolicy(profile: AgeProfile?, storefront: String, consent: ConsentStatus,
                                     trackingAllowed: Bool) -> AdRequestPolicy {
        requestPolicy(group: AgePolicy.group(of: profile, storefront: storefront), storefront: storefront, consent: consent,
                      mayPersonalise: AgePolicy.mayPersonaliseAds(profile: profile, storefront: storefront),
                      trackingAllowed: trackingAllowed)
    }

    /// EEA plus UK and Switzerland, where the consent form applies.
    public static let consentRegion: Set<String> = [
        "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC",
        "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
        "SVN", "ESP", "SWE", "ISL", "LIE", "NOR", "GBR", "CHE",
    ]

    /// An unknown storefront ("") counts as inside the region, to be safe.
    public static func isConsentRegion(_ storefront: String) -> Bool {
        storefront.isEmpty || consentRegion.contains(storefront.uppercased())
    }

    /// - Parameters:
    ///   - mayPersonalise: the player is at or over the local personalisation age.
    ///   - trackingAllowed: the player tapped Allow on Apple's ATT prompt.
    public static func requestPolicy(group: AgeGroup, storefront: String, consent: ConsentStatus,
                                     mayPersonalise: Bool = false, trackingAllowed: Bool = false) -> AdRequestPolicy {
        let region = isConsentRegion(storefront)
        // With an unknown storefront Google's own check decides whether a form is needed.
        let consented = consent == .obtained || (storefront.isEmpty && consent == .notRequired)
        let personalised = group != .child && mayPersonalise && trackingAllowed && (region ? consented : true)
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
