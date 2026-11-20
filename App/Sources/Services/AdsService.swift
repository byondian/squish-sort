#if !KIDS
import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform
import SquishPolicy

/// AdMob behind one small surface. Started only after the age step, with the
/// flags for the player's age group (tech design, ads stack).
@MainActor
final class AdsService: NSObject, ObservableObject, FullScreenContentDelegate {
    /// The ad units come from the build (Info.plist, set by project.yml and the TestFlight workflow).
    /// Without them, Google's public test units.
    enum AdUnits {
        private static func unit(_ key: String, _ test: String) -> String {
            guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, value.hasPrefix("ca-app-pub-") else { return test }
            return value
        }
        static let interstitial = unit("AdMobInterstitialUnit", "ca-app-pub-3940256099942544/4411468910")
        static let rewarded = unit("AdMobRewardedUnit", "ca-app-pub-3940256099942544/1712485313")
    }

    @Published private(set) var rewardedReady = false
    private(set) var started = false
    private var policy: AdRequestPolicy?
    private var interstitial: InterstitialAd?
    private var rewarded: RewardedAd?
    private var onDismiss: (() -> Void)?

    var consentStatus: SquishPolicy.ConsentStatus {
        switch UserMessagingPlatform.ConsentInformation.shared.consentStatus {
        case .obtained: return .obtained
        case .required: return .required
        case .notRequired: return .notRequired
        default: return .unknown
        }
    }

    /// New flags after the age step, the tracking prompt, a storefront change or a
    /// switch to gentle mode. Ads already loaded were requested under the old
    /// flags, so they're thrown away and loaded again under the new ones.
    func update(policy: AdRequestPolicy) {
        let changed = policy != self.policy
        self.policy = policy
        guard started, changed else { return }
        apply(policy)
        interstitial = nil
        rewarded = nil
        rewardedReady = false
        Task {
            await loadInterstitial()
            await loadRewarded()
        }
    }

    private func apply(_ policy: AdRequestPolicy) {
        let config = MobileAds.shared.requestConfiguration
        config.tagForChildDirectedTreatment = NSNumber(value: policy.tagForChildDirectedTreatment)
        config.tagForUnderAgeOfConsent = NSNumber(value: policy.tagForUnderAgeOfConsent)
        config.maxAdContentRating = policy.maxAdContentRating == .g ? .general : .parentalGuidance
    }

    func start(policy: AdRequestPolicy) async {
        guard !started else { return }
        self.policy = policy
        apply(policy)
        // UI tests can't drive Google's consent form, so they start the SDK without it.
        if (policy.tagForChildDirectedTreatment || policy.tagForUnderAgeOfConsent) && !AppModel.isUITesting {
            // Children and teens under the consent age: tell Google's consent
            // platform so, which means no form and no consent-based ads. Ads don't wait on it.
            let underAge = RequestParameters()
            underAge.isTaggedForUnderAgeOfConsent = true
            try? await ConsentInformation.shared.requestConsentInfoUpdate(with: underAge)
        }
        if policy.showConsentForm && !AppModel.isUITesting {
            await gatherConsent()
            guard ConsentInformation.shared.canRequestAds else { return }
        }
        _ = await MobileAds.shared.start()
        started = true
        // The policy may have changed while the SDK was starting (gentle mode, storefront).
        if let latest = self.policy { apply(latest) }
        await loadInterstitial()
        await loadRewarded()
    }

    private func gatherConsent() async {
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            if let vc = Self.topViewController() {
                try await ConsentForm.loadAndPresentIfRequired(from: vc)
            }
        } catch {
            // No form means no consent: ads stay off until next launch.
        }
    }

    func setMuted(_ muted: Bool) {
        guard started else { return }
        MobileAds.shared.isApplicationMuted = muted
    }

    /// Google needs a way back to the consent form where it applies (UK, EEA, Switzerland).
    var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func showPrivacyOptions() async {
        guard let vc = Self.topViewController() else { return }
        try? await ConsentForm.presentPrivacyOptionsForm(from: vc)
    }

    private func request() -> Request {
        let r = Request()
        if let policy, !policy.allowPersonalisedAds {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            r.register(extras)
        }
        return r
    }

    /// An ad that finishes loading after the policy changed is dropped, never shown.
    private func loadInterstitial() async {
        let requestedUnder = policy
        let ad = try? await InterstitialAd.load(with: AdUnits.interstitial, request: request())
        guard requestedUnder == policy else { return }
        interstitial = ad
        interstitial?.fullScreenContentDelegate = self
    }

    private func loadRewarded() async {
        let requestedUnder = policy
        let ad = try? await RewardedAd.load(with: AdUnits.rewarded, request: request())
        guard requestedUnder == policy else { return }
        rewarded = ad
        rewarded?.fullScreenContentDelegate = self
        rewardedReady = rewarded != nil
    }

    /// Shows an interstitial if one is loaded; `done` always runs. No fill is fine.
    func showInterstitial(done: @escaping () -> Void) -> Bool {
        guard started, let ad = interstitial, let vc = Self.topViewController() else {
            done()
            return false
        }
        onDismiss = done
        interstitial = nil
        ad.present(from: vc)
        return true
    }

    /// Opt-in rewarded ad. `completion(true)` only if the reward was earned.
    func showRewarded(completion: @escaping (Bool) -> Void) {
        guard started, let ad = rewarded, let vc = Self.topViewController() else {
            completion(false)
            return
        }
        var earned = false
        rewarded = nil
        rewardedReady = false
        onDismiss = { completion(earned) }
        ad.present(from: vc) { earned = true }
    }

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in self.finishPresentation() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.finishPresentation() }
    }

    private func finishPresentation() {
        let done = onDismiss
        onDismiss = nil
        done?()
        Task {
            if interstitial == nil { await loadInterstitial() }
            if rewarded == nil { await loadRewarded() }
        }
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
#else
import SwiftUI
import SquishPolicy

/// Squishy Workshop (the Kids category app) has no ads and no ad SDK at all: nothing is linked,
/// nothing is loaded, and every call here does nothing.
@MainActor
final class AdsService: ObservableObject {
    @Published private(set) var rewardedReady = false
    let started = false
    var consentStatus: SquishPolicy.ConsentStatus { .notRequired }
    var privacyOptionsRequired: Bool { false }
    func update(policy: AdRequestPolicy) {}
    func start(policy: AdRequestPolicy) async {}
    func setMuted(_ muted: Bool) {}
    func showPrivacyOptions() async {}
    func showInterstitial(done: @escaping () -> Void) -> Bool {
        done()
        return false
    }
    func showRewarded(completion: @escaping (Bool) -> Void) { completion(false) }
}
#endif
