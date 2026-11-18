import SwiftUI
import UIKit
import SquishWorkshop

/// The Workshop's pictures and lists, read once from the app bundle (Content/workshop, made from
/// the design thread's drawings).
enum WorkshopArt {
    private static var cache: [String: UIImage] = [:]

    /// A part, face piece or mould by its file name without ".png". Nil when there is no such picture.
    static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Content/workshop"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[name] = image
        return image
    }

    static func mould(_ id: String) -> UIImage? { image("mould-\(id)") }
    static func face(_ kind: String, _ id: String) -> UIImage? { id == "none" ? nil : image("face-\(kind)-\(id)") }
    static func part(_ category: String, _ id: String) -> UIImage? { image("part-\(category)-\(id)") }

    static let catalog: WorkshopCatalog? = {
        guard let url = Bundle.main.url(forResource: "workshop-parts", withExtension: "json", subdirectory: "Content"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? WorkshopCatalog(json: data)
    }()

    static let nameWheel: NameWheel? = {
        guard let url = Bundle.main.url(forResource: "name-wheel", withExtension: "json", subdirectory: "Content"),
              let data = try? Data(contentsOf: url) else { return nil }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let language = code == "zh" ? "zh-Hant" : code
        return try? NameWheel(json: data, language: language)
    }()

    static func colour(_ hex: UInt32) -> Color { Color(uiColor: UIColor(hex: hex)) }

    /// Where a part from each tray first lands on the body (0...1 across the picture).
    static func home(of category: String) -> (x: Double, y: Double) {
        switch category {
        case "ears", "horns-and-antlers", "antennae-and-hair": return (0.5, 0.25)
        case "hats-and-headwear": return (0.5, 0.2)
        case "wings": return (0.5, 0.52)
        case "tails": return (0.78, 0.7)
        case "glasses-and-face-wear": return (0.5, 0.5)
        case "neck-and-body": return (0.5, 0.74)
        case "held-items": return (0.2, 0.62)
        case "arms-and-feet": return (0.5, 0.8)
        default: return (0.5, 0.62)
        }
    }

    /// Wings and tails sit behind the body; everything else in front.
    static func isBehind(_ category: String) -> Bool { category == "wings" || category == "tails" }
}

/// A made squishy drawn from its Workshop design: goo in a mould, a face, and its parts.
struct WorkshopSquishyView: View {
    let design: WorkshopDesign
    /// How full the mould is while pouring, 0...1. A finished squishy is full.
    var fill: Double = 1
    /// Before it is baked the mould shows as a pale tray around the goo.
    var showsMould = false
    var showsFace = true
    /// Moves the wavy top of the goo while it is being poured.
    var wave: Double?

    private static let plum = Color(uiColor: .plum)
    /// The body takes this share of the picture, so ears and hats have room around it.
    static let bodyShare = CGFloat(WorkshopDesign.bodyShare)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let body = side * WorkshopSquishyView.bodyShare
            ZStack {
                ForEach(design.parts.filter { WorkshopArt.isBehind($0.category) }) { placed(part: $0, side: side) }
                if design.fx.contains("glow-in-dark") {
                    mask.frame(width: body, height: body).foregroundStyle(WorkshopArt.colour(design.mainColour))
                        .blur(radius: side * 0.06).opacity(0.8)
                }
                // The outline: the same shape, a little bigger, in plum.
                mask.frame(width: body, height: body).foregroundStyle(WorkshopSquishyView.plum)
                    .scaleEffect(1.07)
                if showsMould {
                    mask.frame(width: body, height: body).foregroundStyle(Color.white.opacity(0.9))
                }
                GooFill(design: design, fill: fill, wave: wave)
                    .frame(width: body, height: body)
                    .mask { mask.frame(width: body, height: body) }
                if let name = design.skin, let picture = PhotoSkins.image(name) {
                    // A drawing from paper: its lines and colours sit on the goo like felt pen, and the paper is clear.
                    Image(uiImage: picture).resizable().frame(width: body, height: body)
                        .blendMode(.multiply)
                        .mask { mask.frame(width: body, height: body) }
                }
                if showsFace {
                    face(body: body)
                }
                ForEach(design.stickers) { placed(part: $0, side: side) }
                ForEach(design.parts.filter { !WorkshopArt.isBehind($0.category) }) { placed(part: $0, side: side) }
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The body's shape in white: a mould picture, a drawn outline, or two moulds snapped together.
    @ViewBuilder private var mask: some View {
        ZStack {
            if design.mould == "draw-it", let outline = design.drawnOutline, outline.count > 2 {
                DrawnOutline(points: outline).fill(.foreground)
            } else if let image = WorkshopArt.mould(design.mould) ?? WorkshopArt.mould("bun") {
                Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
            }
            if let second = design.mould2, let image = WorkshopArt.mould(second) {
                GeometryReader { g in
                    Image(uiImage: image).renderingMode(.template).resizable().scaledToFit()
                        .frame(width: g.size.width * 0.62, height: g.size.height * 0.62)
                        .position(x: g.size.width / 2, y: g.size.height * 0.22)
                }
            }
        }
    }

    @ViewBuilder private func face(body: CGFloat) -> some View {
        let f = design.face
        // With a head snapped on top, the face moves up onto it.
        let lift: CGFloat = design.mould2 == nil ? 0.04 : -0.24
        let size = body * (design.mould2 == nil ? 0.78 : 0.5)
        ZStack {
            if let strokes = design.drawnFace, !strokes.isEmpty {
                DrawnStrokes(strokes: strokes)
                    .stroke(WorkshopSquishyView.plum, style: StrokeStyle(lineWidth: max(2, body * 0.035), lineCap: .round, lineJoin: .round))
                    .frame(width: body, height: body)
            } else {
                ForEach([("cheeks", f.cheeks), ("mouths", f.mouth), ("noses", f.nose), ("eyes", f.eyes), ("brows", f.brows)], id: \.0) { kind, id in
                    if let image = WorkshopArt.face(kind, id) {
                        Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
                    }
                }
                .offset(y: body * lift)
            }
        }
    }

    @ViewBuilder private func placed(part p: Placed, side: CGFloat) -> some View {
        if let image = WorkshopArt.part(p.category, p.part) {
            let size = side * 0.5 * CGFloat(p.scale)
            Image(uiImage: image).resizable().scaledToFit()
                .frame(width: size, height: size)
                .rotationEffect(.radians(p.angle))
                .position(x: side * CGFloat(p.x), y: side * CGFloat(p.y))
        }
    }
}

struct DrawnOutline: Shape {
    let points: [WorkshopPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        func at(_ q: WorkshopPoint) -> CGPoint { CGPoint(x: rect.minX + rect.width * q.x, y: rect.minY + rect.height * q.y) }
        p.move(to: at(first))
        for q in points.dropFirst() { p.addLine(to: at(q)) }
        p.closeSubpath()
        return p
    }
}

struct DrawnStrokes: Shape {
    let strokes: [[WorkshopPoint]]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            func at(_ q: WorkshopPoint) -> CGPoint { CGPoint(x: rect.minX + rect.width * q.x, y: rect.minY + rect.height * q.y) }
            p.move(to: at(first))
            if stroke.count == 1 { p.addLine(to: at(first)) }
            for q in stroke.dropFirst() { p.addLine(to: at(q)) }
        }
        return p
    }
}

/// The goo inside the mould: its layers from the bottom up, each with its pattern, then the
/// effects and a soft shine. Drawn as a square; the mould masks it.
struct GooFill: View {
    let design: WorkshopDesign
    var fill: Double = 1
    /// While pouring the top of the goo is wavy; this moves the wave along. Nil is a flat top.
    var wave: Double?

    var body: some View {
        Canvas { ctx, size in
            let layers = design.layers
            let bands = design.bands
            let level = CGFloat(min(1, max(0, fill)))
            // The goo's top edge: the mould fills from the bottom.
            let top = size.height * (1 - level)
            var goo = ctx
            goo.clip(to: GooFill.surface(top: top, size: size, wave: level < 1 ? wave : nil))
            for (i, layer) in layers.enumerated() {
                let y1 = size.height * (1 - CGFloat(bands[i].from) * level)
                // The top layer runs up past the wave so no gap shows under it.
                let y0 = i == layers.count - 1 ? 0 : size.height * (1 - CGFloat(bands[i].to) * level)
                let band = CGRect(x: 0, y: y0, width: size.width, height: max(0, y1 - y0))
                guard band.height > 0 else { continue }
                var inner = goo
                inner.clip(to: Path(band))
                GooFill.paint(layer, below: i > 0 ? layers[i - 1].colour : nil, in: band, size: size, ctx: &inner)
            }
            var fxCtx = goo
            GooFill.effects(design.fx, seed: design.layers.first?.seed ?? 0, size: size, ctx: &fxCtx)
            // A soft shine top left and a shade along the bottom make it read as a puffy toy.
            let shine = Path(ellipseIn: CGRect(x: size.width * 0.2, y: size.height * 0.2, width: size.width * 0.26, height: size.height * 0.14))
            fxCtx.fill(shine, with: .color(.white.opacity(design.goo == .gel ? 0.5 : 0.3)))
            fxCtx.fill(Path(CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28)),
                       with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.12)]),
                                             startPoint: CGPoint(x: 0, y: size.height * 0.72), endPoint: CGPoint(x: 0, y: size.height)))
        }
    }

    /// Everything under the goo's top edge. The edge is a gentle wave while it is being poured.
    static func surface(top: CGFloat, size: CGSize, wave: Double?) -> Path {
        guard let wave else { return Path(CGRect(x: 0, y: top, width: size.width, height: max(0, size.height - top))) }
        var p = Path()
        p.move(to: CGPoint(x: 0, y: size.height))
        let steps = 24
        for k in 0...steps {
            let x = size.width * CGFloat(k) / CGFloat(steps)
            let y = top + size.height * 0.015 * CGFloat(sin(wave * 6 + Double(k) * 0.8))
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.closeSubpath()
        return p
    }

    private static func random(_ seed: inout UInt64) -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) % 10_000) / 10_000
    }

    static func paint(_ layer: GooLayer, below: UInt32?, in band: CGRect, size: CGSize, ctx: inout GraphicsContext) {
        let base = WorkshopArt.colour(layer.colour)
        let light = WorkshopArt.colour(GooMix.mix(layer.colour, 0xFFFFFF, share: 0.45))
        let dark = WorkshopArt.colour(GooMix.mix(layer.colour, 0x3B2A4A, share: 0.25))
        var seed = UInt64(truncatingIfNeeded: layer.seed &* 7919 &+ 17)
        let w = size.width, h = size.height
        ctx.fill(Path(band), with: .color(base))
        switch layer.pattern {
        case "stripes":
            var x = -h
            while x < w + h {
                var p = Path()
                p.move(to: CGPoint(x: x, y: h)); p.addLine(to: CGPoint(x: x + h, y: 0))
                ctx.stroke(p, with: .color(light), lineWidth: w * 0.06)
                x += w * 0.16
            }
        case "ombre":
            let to = below.map { WorkshopArt.colour($0) } ?? light
            ctx.fill(Path(band), with: .linearGradient(Gradient(colors: [base, to]), startPoint: CGPoint(x: 0, y: band.minY),
                                                       endPoint: CGPoint(x: 0, y: band.maxY)))
        case "marble", "swirl", "tie-dye":
            let colours: [Color] = layer.pattern == "tie-dye" ? [light, dark, WorkshopArt.colour(GooMix.mix(layer.colour, 0xFFD86B))] : [light, dark]
            for k in 0..<6 {
                var p = Path()
                let y = h * (0.1 + 0.16 * CGFloat(k)) + h * 0.06 * random(&seed)
                p.move(to: CGPoint(x: -w * 0.1, y: y))
                p.addCurve(to: CGPoint(x: w * 1.1, y: y + h * (random(&seed) - 0.5) * 0.3),
                           control1: CGPoint(x: w * 0.3, y: y - h * (0.1 + 0.25 * random(&seed))),
                           control2: CGPoint(x: w * 0.7, y: y + h * (0.1 + 0.25 * random(&seed))))
                ctx.stroke(p, with: .color(colours[k % colours.count].opacity(0.75)),
                           style: StrokeStyle(lineWidth: w * (layer.pattern == "marble" ? 0.035 : 0.07), lineCap: .round))
            }
        case "spots", "speckle":
            let count = layer.pattern == "spots" ? 14 : 70
            for _ in 0..<count {
                let r = w * (layer.pattern == "spots" ? 0.035 + 0.035 * random(&seed) : 0.008 + 0.008 * random(&seed))
                let c = CGPoint(x: w * random(&seed), y: h * random(&seed))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .color(layer.pattern == "spots" ? light : dark.opacity(0.7)))
            }
        case "checks":
            let step = w / 8
            for row in 0..<8 {
                for col in 0..<8 where (row + col) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * step, y: CGFloat(row) * step, width: step, height: step)), with: .color(light))
                }
            }
        case "galaxy":
            ctx.fill(Path(band), with: .linearGradient(Gradient(colors: [dark, base, Color(uiColor: UIColor(hex: 0x8C7AE6))]),
                                                       startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: w, y: h)))
            for _ in 0..<40 {
                let r = w * (0.004 + 0.01 * random(&seed))
                let c = CGPoint(x: w * random(&seed), y: h * random(&seed))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.9)))
            }
        case "rainbow":
            let hexes: [UInt32] = [0xFF5A6E, 0xFFA25C, 0xFFD86B, 0x9ED67F, 0x4A9FE8, 0xA47CF0]
            let step = h / CGFloat(hexes.count)
            for (k, hex) in hexes.enumerated() {
                ctx.fill(Path(CGRect(x: 0, y: CGFloat(k) * step, width: w, height: step + 1)), with: .color(WorkshopArt.colour(hex)))
            }
        case "half-and-half":
            ctx.fill(Path(CGRect(x: w / 2, y: 0, width: w / 2, height: h)), with: .color(below.map { WorkshopArt.colour($0) } ?? light))
        default:
            break
        }
    }

    static func effects(_ fx: [String], seed start: Int, size: CGSize, ctx: inout GraphicsContext) {
        var seed = UInt64(truncatingIfNeeded: start &* 31 &+ 5)
        let w = size.width, h = size.height
        func dots(_ count: Int, _ radius: ClosedRange<CGFloat>, _ colours: [Color], ring: Bool = false) {
            for k in 0..<count {
                let r = w * (radius.lowerBound + (radius.upperBound - radius.lowerBound) * random(&seed))
                let c = CGPoint(x: w * random(&seed), y: h * random(&seed))
                let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                if ring { ctx.stroke(dot, with: .color(colours[k % colours.count]), lineWidth: max(1, w * 0.006)) } else {
                    ctx.fill(dot, with: .color(colours[k % colours.count]))
                }
            }
        }
        let bright = [0xFF7EB6, 0xFFD86B, 0x7FE0C4, 0x7CC8FF, 0xC9A7F5].map { WorkshopArt.colour(UInt32($0)) }
        for effect in fx {
            switch effect {
            case "glitter": dots(90, 0.004...0.01, [.white.opacity(0.9), Color(uiColor: UIColor(hex: 0xFFE9A0))])
            case "sparkle":
                for _ in 0..<10 {
                    let c = CGPoint(x: w * random(&seed), y: h * random(&seed))
                    let r = w * (0.02 + 0.025 * random(&seed))
                    var p = Path()
                    p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r))
                    p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
                    ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: max(1, w * 0.012), lineCap: .round))
                }
            case "confetti-bits": dots(36, 0.012...0.02, bright)
            case "sprinkles":
                for k in 0..<30 {
                    let c = CGPoint(x: w * random(&seed), y: h * random(&seed))
                    let a = random(&seed) * .pi
                    var p = Path()
                    p.move(to: c); p.addLine(to: CGPoint(x: c.x + cos(a) * w * 0.04, y: c.y + sin(a) * w * 0.04))
                    ctx.stroke(p, with: .color(bright[k % bright.count]), style: StrokeStyle(lineWidth: max(1.5, w * 0.014), lineCap: .round))
                }
            case "bubbles-inside": dots(16, 0.02...0.05, [.white.opacity(0.7)], ring: true)
            case "pearl-shine":
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [.white.opacity(0.45), .clear, .white.opacity(0.25)]),
                                               startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            case "holographic":
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: bright.map { $0.opacity(0.35) }), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            default: break
            }
        }
    }
}
