import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform
import SquishPolicy

/// AdMob behind one small surface. Started only after the age step, with the
/// flags for the player's age group (tech design, ads stack). No ATT prompt ever.
@MainActor
final class AdsService: NSObject, ObservableObject, FullScreenContentDelegate {
    /// Google's public test units until the AdMob account is verified.
    /// Release ids replace these through AdUnits before submission.
    enum AdUnits {
        static let interstitial = "ca-app-pub-3940256099942544/4411468910"
        static let rewarded = "ca-app-pub-3940256099942544/1712485313"
    }

    @Published private(set) var rewardedReady = false
    private(set) var started = false
    private var policy: AdRequestPolicy?
    private var interstitial: InterstitialAd?
    private var rewarded: RewardedAd?
    private var onDismiss: (() -> Void)?

    func start(policy: AdRequestPolicy) async {
        guard !started else { return }
        self.policy = policy
        let config = MobileAds.shared.requestConfiguration
        config.tagForChildDirectedTreatment = NSNumber(value: policy.tagForChildDirectedTreatment)
        config.tagForUnderAgeOfConsent = NSNumber(value: policy.tagForUnderAgeOfConsent)
        config.maxAdContentRating = policy.maxAdContentRating == .g ? .general : .parentalGuidance
        if policy.showConsentForm {
            await gatherConsent()
            guard ConsentInformation.shared.canRequestAds else { return }
        }
        _ = await MobileAds.shared.start()
        started = true
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

    private func request() -> Request {
        let r = Request()
        if let policy, !policy.allowPersonalisedAds && !policy.showConsentForm {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            r.register(extras)
        }
        return r
    }

    private func loadInterstitial() async {
        interstitial = try? await InterstitialAd.load(with: AdUnits.interstitial, request: request())
        interstitial?.fullScreenContentDelegate = self
    }

    private func loadRewarded() async {
        rewarded = try? await RewardedAd.load(with: AdUnits.rewarded, request: request())
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
