import SwiftUI
import UIKit
import SquishPolicy
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// Apple's Declared Age Range API (iOS 26+). Returns nil when it isn't
/// available or the person declines, and the app falls back to its own
/// neutral birth-year question.
enum DeclaredAge {
    @MainActor
    static func request(storefront: String) async -> AgeRange? {
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.0, *) {
            guard let vc = topViewController() else { return nil }
            // Each range must span at least two years, so the gates depend on the storefront.
            let gates = AgePolicy.declaredAgeGates(storefront: storefront)
            do {
                let response = try await AgeRangeService.shared.requestAgeRange(ageGates: gates[0], gates[1], gates[2], in: vc)
                switch response {
                case .declinedSharing:
                    return nil
                case .sharing(let range):
                    return AgeRange(lower: range.lowerBound, upper: range.upperBound)
                @unknown default:
                    return nil
                }
            } catch {
                #if DEBUG
                print("DeclaredAgeRange request failed: \(error)")
                #endif
                return nil
            }
        }
        #endif
        return nil
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
