import SwiftUI
import SquishPolicy

/// A squishy drawn in SwiftUI (book, capsule, Squish Room), matching the board look.
struct SquishyView: View {
    let id: String
    var rarity: Rarity = .common
    var silhouette = false
    var squash: CGFloat = 0 // 0 = resting, 1 = fully pressed

    var body: some View {
        Canvas { ctx, size in
            let d = min(size.width, size.height) * 0.78
            let style = SquishyStyle.forID(id)
            ctx.translateBy(x: size.width / 2, y: size.height * 0.55)
            ctx.scaleBy(x: 1 + squash * 0.25, y: -(1 - squash * 0.35)) // flip to CG's y-up
            let plum = Color(uiColor: .plum)
            let fill = silhouette ? plum.opacity(0.18) : Color(uiColor: style.color)
            for p in style.featurePaths(diameter: d) {
                let path = Path(p)
                ctx.fill(path, with: .color(silhouette ? fill : Color(uiColor: style.featureColor)))
                if !silhouette { ctx.stroke(path, with: .color(plum), lineWidth: d * 0.035) }
            }
            let body = Path(style.bodyPath(diameter: d))
            ctx.fill(body, with: .color(fill))
            guard !silhouette else { return }
            if rarity == .ultra || rarity == .secret {
                let colors: [Color] = rarity == .secret ? [Theme.butter, .orange, Theme.butter] : [Theme.sky, Theme.grape, Theme.bubblegum, Theme.mint]
                ctx.fill(body, with: .linearGradient(Gradient(colors: colors.map { $0.opacity(0.55) }),
                                                    startPoint: CGPoint(x: -d / 2, y: -d / 2), endPoint: CGPoint(x: d / 2, y: d / 2)))
            }
            ctx.stroke(body, with: .color(plum), lineWidth: d * 0.04)
            // Gloss
            ctx.fill(Path(ellipseIn: CGRect(x: -d * 0.31, y: d * 0.14, width: d * 0.22, height: d * 0.12)), with: .color(.white.opacity(0.55)))
            // Face (squints when squashed)
            let eyeH = d * 0.13 * (1 - squash * 0.8)
            for side: CGFloat in [-1, 1] {
                ctx.fill(Path(ellipseIn: CGRect(x: side * d * 0.17 - d * 0.065, y: d * 0.04 - eyeH / 2, width: d * 0.13, height: eyeH)), with: .color(plum))
                ctx.fill(Path(ellipseIn: CGRect(x: side * d * 0.29 - d * 0.08, y: -d * 0.115, width: d * 0.16, height: d * 0.07)), with: .color(Color(red: 1, green: 0.62, blue: 0.71).opacity(0.7)))
            }
            var mouth = Path()
            mouth.addArc(center: CGPoint(x: 0, y: -d * 0.04), radius: d * 0.06, startAngle: .radians(.pi * 1.15), endAngle: .radians(.pi * 1.85), clockwise: false)
            ctx.stroke(mouth, with: .color(plum), style: StrokeStyle(lineWidth: d * 0.03, lineCap: .round))
            if rarity == .rare {
                for (x, y) in [(-0.25, 0.3), (0.3, 0.25), (0.05, -0.3)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: d * x, y: d * y, width: d * 0.05, height: d * 0.05)), with: .color(.white))
                }
            }
        }
        .accessibilityLabel(Text(id))
    }
}
