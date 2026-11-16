import UIKit

/// Placeholder look for each squishy until the Soft Pop art sheet lands:
/// a body shape, a colour and one silhouette feature, so board pieces can be
/// told apart by shape alone (colour-blind friendly).
struct SquishyStyle {
    enum Shape: CaseIterable { case bun, blob, drop, bean, star, heart }
    enum Feature: CaseIterable { case none, ears, leaf, fins, hat, antenna }

    let color: UIColor
    let shape: Shape
    let feature: Feature

    static func forID(_ id: String) -> SquishyStyle {
        if let s = table[id] { return s }
        // Collectibles without a board role get a stable look from their id.
        let h = id.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        let colors: [UInt32] = [0xFFB3C7, 0xFFD1A1, 0xFFF0A0, 0xBDF0C8, 0xB5DCFF, 0xD9C2FF, 0xF7C6E8, 0xC9F2EC]
        return SquishyStyle(color: UIColor(hex: colors[Int(h % UInt32(colors.count))]),
                            shape: Shape.allCases[Int((h / 7) % UInt32(Shape.allCases.count))],
                            feature: Feature.allCases[Int((h / 13) % UInt32(Feature.allCases.count))])
    }

    private static let table: [String: SquishyStyle] = [
        // Toy Shop
        "strawbie": .init(color: UIColor(hex: 0xFF5E6C), shape: .bun, feature: .leaf),
        "tango": .init(color: UIColor(hex: 0xFF9A3C), shape: .drop, feature: .ears),
        "sunny": .init(color: UIColor(hex: 0xFFD54A), shape: .bean, feature: .antenna),
        "minty": .init(color: UIColor(hex: 0x5CCB8A), shape: .blob, feature: .none),
        "blu": .init(color: UIColor(hex: 0x4F9BF0), shape: .heart, feature: .fins),
        "grapey": .init(color: UIColor(hex: 0x9B6BFF), shape: .star, feature: .hat),
        // Sweet Factory
        "macaron": .init(color: UIColor(hex: 0xFF9ECF), shape: .bean, feature: .none),
        "donut": .init(color: UIColor(hex: 0xC98A5A), shape: .bun, feature: .hat),
        "jelly": .init(color: UIColor(hex: 0x3FD0BE), shape: .drop, feature: .none),
        "cupcake": .init(color: UIColor(hex: 0xC9A7FF), shape: .blob, feature: .leaf),
        "gummy-bear": .init(color: UIColor(hex: 0xB8E05A), shape: .star, feature: .none),
        "lolly": .init(color: UIColor(hex: 0x6EC6FF), shape: .heart, feature: .antenna),
        // Starlight Stage
        "lumi": .init(color: UIColor(hex: 0xFF8FC8), shape: .bun, feature: .ears),
        "riff": .init(color: UIColor(hex: 0x5B8DEF), shape: .blob, feature: .hat),
        "zuzu": .init(color: UIColor(hex: 0x9B6BFF), shape: .drop, feature: .ears),
        "pip": .init(color: UIColor(hex: 0xFFD54A), shape: .bean, feature: .antenna),
        "nova": .init(color: UIColor(hex: 0xA9B8D6), shape: .star, feature: .none),
        "coco": .init(color: UIColor(hex: 0x5CCB8A), shape: .heart, feature: .fins),
        // Christmas Workshop
        "santa": .init(color: UIColor(hex: 0xE5484D), shape: .bun, feature: .hat),
        "elfie": .init(color: UIColor(hex: 0x3FB56F), shape: .drop, feature: .ears),
        "reindeer": .init(color: UIColor(hex: 0x8B5E3C), shape: .bean, feature: .antenna),
        "snowbo": .init(color: UIColor(hex: 0xF4F7FB), shape: .blob, feature: .hat),
        "ginger": .init(color: UIColor(hex: 0xD9844A), shape: .star, feature: .none),
        "waddles": .init(color: UIColor(hex: 0x34495E), shape: .heart, feature: .fins),
    ]

    /// Body outline centred on the origin, `d` wide.
    func bodyPath(diameter d: CGFloat) -> CGPath {
        let r = d / 2
        switch shape {
        case .bun:
            return CGPath(ellipseIn: CGRect(x: -r, y: -r * 0.9, width: d, height: d * 0.9), transform: nil)
        case .blob:
            return CGPath(roundedRect: CGRect(x: -r * 0.95, y: -r * 0.85, width: d * 0.95, height: d * 0.85),
                          cornerWidth: d * 0.32, cornerHeight: d * 0.32, transform: nil)
        case .bean:
            return CGPath(ellipseIn: CGRect(x: -r, y: -r * 0.75, width: d, height: d * 0.75), transform: nil)
        case .drop:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: r))
            p.addCurve(to: CGPoint(x: r * 0.9, y: -r * 0.35), control1: CGPoint(x: r * 0.35, y: r * 0.6),
                       control2: CGPoint(x: r * 0.95, y: r * 0.15))
            p.addArc(center: CGPoint(x: 0, y: -r * 0.35), radius: r * 0.9, startAngle: 0, endAngle: .pi, clockwise: true)
            p.addCurve(to: CGPoint(x: 0, y: r), control1: CGPoint(x: -r * 0.95, y: r * 0.15),
                       control2: CGPoint(x: -r * 0.35, y: r * 0.6))
            p.closeSubpath()
            return p
        case .star:
            let p = CGMutablePath()
            let points = 5
            for i in 0..<(points * 2) {
                let angle = CGFloat(i) * .pi / CGFloat(points) + .pi / 2
                let radius = i % 2 == 0 ? r : r * 0.62
                let pt = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius - r * 0.05)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            return p.copy(strokingWithWidth: d * 0.12, lineCap: .round, lineJoin: .round, miterLimit: 1)
                .union(p)
        case .heart:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: -r * 0.85))
            p.addCurve(to: CGPoint(x: 0, y: r * 0.45), control1: CGPoint(x: r * 1.25, y: -r * 0.1),
                       control2: CGPoint(x: r * 0.7, y: r * 1.05))
            p.addCurve(to: CGPoint(x: 0, y: -r * 0.85), control1: CGPoint(x: -r * 0.7, y: r * 1.05),
                       control2: CGPoint(x: -r * 1.25, y: -r * 0.1))
            p.closeSubpath()
            return p
        }
    }

    /// Feature shapes, drawn behind the body in the body colour.
    func featurePaths(diameter d: CGFloat) -> [CGPath] {
        let r = d / 2
        switch feature {
        case .none:
            return []
        case .ears:
            return [CGPath(ellipseIn: CGRect(x: -r * 0.75, y: r * 0.35, width: r * 0.55, height: r * 0.7), transform: nil),
                    CGPath(ellipseIn: CGRect(x: r * 0.2, y: r * 0.35, width: r * 0.55, height: r * 0.7), transform: nil)]
        case .leaf:
            return [CGPath(ellipseIn: CGRect(x: -r * 0.15, y: r * 0.6, width: r * 0.6, height: r * 0.35), transform: nil)]
        case .fins:
            let left = CGMutablePath()
            left.move(to: CGPoint(x: -r * 0.8, y: 0))
            left.addLine(to: CGPoint(x: -r * 1.15, y: r * 0.25))
            left.addLine(to: CGPoint(x: -r * 1.1, y: -r * 0.25))
            left.closeSubpath()
            let right = CGMutablePath()
            right.move(to: CGPoint(x: r * 0.8, y: 0))
            right.addLine(to: CGPoint(x: r * 1.15, y: r * 0.25))
            right.addLine(to: CGPoint(x: r * 1.1, y: -r * 0.25))
            right.closeSubpath()
            return [left, right]
        case .hat:
            return [CGPath(roundedRect: CGRect(x: -r * 0.4, y: r * 0.55, width: r * 0.8, height: r * 0.45),
                           cornerWidth: r * 0.12, cornerHeight: r * 0.12, transform: nil)]
        case .antenna:
            let p = CGMutablePath()
            p.addEllipse(in: CGRect(x: -r * 0.12, y: r * 0.95, width: r * 0.24, height: r * 0.24))
            p.addRect(CGRect(x: -r * 0.04, y: r * 0.6, width: r * 0.08, height: r * 0.4))
            return [p]
        }
    }

    var featureColor: UIColor {
        switch feature {
        case .leaf: return UIColor(hex: 0x7FE0C4)
        case .hat: return UIColor(hex: 0xFFD86B)
        default: return color
        }
    }
}
