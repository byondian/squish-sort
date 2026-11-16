import UIKit

/// Light and soft, never a rattle (game design doc, haptics).
@MainActor
final class Haptics {
    var enabled = true { didSet { if !enabled { squish.letGo() } } }
    /// The haptics that follow a soft squishy.
    let squish = SquishHaptics()
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notify = UINotificationFeedbackGenerator()

    func lift() { guard enabled else { return }; soft.impactOccurred(intensity: 0.5) }
    func land() { guard enabled else { return }; light.impactOccurred(intensity: 0.7) }

    /// A soft swell that fades, like pressing foam.
    func complete() {
        guard enabled else { return }
        for (i, intensity) in [0.4, 0.7, 1.0, 0.6, 0.3].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) { [soft] in
                soft.impactOccurred(intensity: intensity)
            }
        }
    }

    /// Two tiny taps, the head-shake.
    func reject() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [light] in light.impactOccurred(intensity: 0.4) }
    }

    func win() { guard enabled else { return }; notify.notificationOccurred(.success) }
    func star() { guard enabled else { return }; light.impactOccurred(intensity: 0.8) }
}
