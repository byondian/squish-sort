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
    /// EEA plus UK and Switzerland, where the consent form applies.
    public static let consentRegion: Set<String> = [
        "AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC",
        "HUN", "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK",
        "SVN", "ESP", "SWE", "ISL", "LIE", "NOR", "GBR", "CHE",
    ]

    public static func isConsentRegion(_ storefront: String) -> Bool {
        consentRegion.contains(storefront.uppercased())
    }

    public static func requestPolicy(group: AgeGroup, storefront: String, consent: ConsentStatus) -> AdRequestPolicy {
        switch group {
        case .child:
            return AdRequestPolicy(tagForChildDirectedTreatment: true, tagForUnderAgeOfConsent: false,
                                   maxAdContentRating: .g, allowPersonalisedAds: false, showConsentForm: false)
        case .teen:
            return AdRequestPolicy(tagForChildDirectedTreatment: false, tagForUnderAgeOfConsent: true,
                                   maxAdContentRating: .pg, allowPersonalisedAds: false, showConsentForm: false)
        case .adult:
            let region = isConsentRegion(storefront)
            return AdRequestPolicy(tagForChildDirectedTreatment: false, tagForUnderAgeOfConsent: false,
                                   maxAdContentRating: .pg,
                                   allowPersonalisedAds: region ? consent == .obtained : true,
                                   showConsentForm: region)
        }
    }
}
