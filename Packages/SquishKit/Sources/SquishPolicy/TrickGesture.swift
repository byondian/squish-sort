import Foundation

/// The finger movements that ask the Buddy for a trick. A plain tap or a knead is none of them.
public enum TrickGesture: Equatable, Sendable {
    /// A quick flick upwards: flip.
    case swipeUp
    /// Round the Buddy once: spin.
    case circle

    /// Reads one finger's path. Points count y downwards, like the page. `centre` is the middle of
    /// the Buddy and `size` its width, so the same movement works on a small and a big phone.
    public static func classify(points: [(x: Double, y: Double)], seconds: Double,
                                centre: (x: Double, y: Double), size: Double) -> TrickGesture? {
        guard points.count >= 3, size > 0, let first = points.first, let last = points.last else { return nil }
        // Round the middle: add up the turn, leaving out the part of the path that is right on the
        // middle, where the direction means nothing.
        var turned = 0.0
        var before: Double?
        for p in points {
            let dx = p.x - centre.x, dy = p.y - centre.y
            guard (dx * dx + dy * dy).squareRoot() > size * 0.15 else { before = nil; continue }
            let angle = atan2(dy, dx)
            if let b = before {
                var step = angle - b
                if step > .pi { step -= 2 * .pi }
                if step < -.pi { step += 2 * .pi }
                turned += step
            }
            before = angle
        }
        if abs(turned) >= 5.2 { return .circle }
        let up = first.y - last.y, across = abs(last.x - first.x)
        if seconds <= 0.5, up >= max(40, size * 0.25), across <= up * 0.6 { return .swipeUp }
        return nil
    }
}
