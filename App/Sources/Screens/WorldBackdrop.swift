import SwiftUI

/// The room behind the jars. Each world has its own, kept soft and low in contrast
/// so the squishies stay the hero (level screen spec).
struct WorldBackdrop: View {
    let world: String

    /// Starlight Stage is a night scene: jars glow and loose text turns white.
    static func isDark(_ world: String) -> Bool { world == "starlight" }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                switch world {
                case "sweetfactory": sweetFactory(w, h)
                case "starlight": starlight(w, h)
                case "christmas": grotto(w, h)
                default: toyShop(w, h)
                }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func stripes(_ w: CGFloat, _ color: Color, width: CGFloat = 26, gap: CGFloat = 26) -> some View {
        HStack(spacing: gap) {
            ForEach(0..<Int(w / (width + gap)) + 2, id: \.self) { _ in Rectangle().fill(color).frame(width: width) }
        }
        .frame(width: w, alignment: .leading)
        .clipped()
    }

    /// Pink and cream wallpaper, bunting, and a wooden shelf.
    @ViewBuilder private func toyShop(_ w: CGFloat, _ h: CGFloat) -> some View {
        Color(hex: 0xFFF4E8)
        stripes(w, Color(hex: 0xFFD9E6).opacity(0.55))
        // Bunting along the top.
        HStack(spacing: 6) {
            ForEach(0..<Int(w / 40) + 1, id: \.self) { i in
                Triangle().fill([Color(hex: 0xFF9EC4), Color(hex: 0xFFE08A), Color(hex: 0x9FE3CF), Color(hex: 0xA9D4FF)][i % 4].opacity(0.7))
                    .frame(width: 34, height: 30)
            }
        }
        .frame(width: w)
        .position(x: w / 2, y: h * 0.075)
        shelf(w, h, top: Color(hex: 0xE9C7A0), front: Color(hex: 0xD3A877))
    }

    /// A mint wall with candy stripes, white pipes, a conveyor belt and a cream floor.
    @ViewBuilder private func sweetFactory(_ w: CGFloat, _ h: CGFloat) -> some View {
        Color(hex: 0xDDF6EC)
        stripes(w, Color.white.opacity(0.45), width: 18, gap: 34)
        VStack(spacing: 8) {
            Capsule().fill(Color.white.opacity(0.9)).frame(width: w * 1.1, height: 14)
            Capsule().fill(Color.white.opacity(0.7)).frame(width: w * 1.1, height: 9)
        }
        .position(x: w / 2, y: h * 0.07)
        Rectangle().fill(Color(hex: 0xFFF6E6)).frame(width: w, height: h * 0.2).position(x: w / 2, y: h * 0.9)
        // The belt, with rollers.
        ZStack {
            Capsule().fill(Color(hex: 0xBFA9C9).opacity(0.75)).frame(width: w * 0.96, height: 20)
            HStack(spacing: 22) {
                ForEach(0..<Int(w / 34), id: \.self) { _ in Circle().fill(Color.white.opacity(0.7)).frame(width: 9, height: 9) }
            }
        }
        .position(x: w / 2, y: h * 0.8)
    }

    /// Night purple with stars, a spotlight beam and a curved stage with footlights.
    @ViewBuilder private func starlight(_ w: CGFloat, _ h: CGFloat) -> some View {
        LinearGradient(colors: [Color(hex: 0x3B2C66), Color(hex: 0x241A45)], startPoint: .top, endPoint: .bottom)
        ForEach(0..<28, id: \.self) { i in
            let x = CGFloat((i * 73 + 31) % 100) / 100, y = CGFloat((i * 41 + 17) % 70) / 100
            Circle().fill(Color.white.opacity(i % 3 == 0 ? 0.8 : 0.4))
                .frame(width: i % 4 == 0 ? 4 : 2.5, height: i % 4 == 0 ? 4 : 2.5)
                .position(x: x * w, y: y * h)
        }
        // The spotlight.
        Path { p in
            p.move(to: CGPoint(x: w * 0.5, y: -20))
            p.addLine(to: CGPoint(x: w * 0.02, y: h * 0.8))
            p.addLine(to: CGPoint(x: w * 0.98, y: h * 0.8))
            p.closeSubpath()
        }
        .fill(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
        // The stage.
        Ellipse().fill(Color(hex: 0x5A3F8F)).frame(width: w * 1.5, height: h * 0.36).position(x: w / 2, y: h * 0.96)
        Ellipse().stroke(Color(hex: 0xC9A8FF).opacity(0.6), lineWidth: 3).frame(width: w * 1.5, height: h * 0.36).position(x: w / 2, y: h * 0.96)
        HStack(spacing: w / 9) {
            ForEach(0..<7, id: \.self) { _ in
                Circle().fill(Color(hex: 0xFFE08A).opacity(0.85)).frame(width: 9, height: 9).shadow(color: Color(hex: 0xFFE08A), radius: 5)
            }
        }
        .position(x: w / 2, y: h * 0.795)
    }

    /// Warm red and cream, fairy lights, snow on the shelf.
    @ViewBuilder private func grotto(_ w: CGFloat, _ h: CGFloat) -> some View {
        Color(hex: 0xFFF3E6)
        stripes(w, Color(hex: 0xF2B4AE).opacity(0.4))
        HStack(spacing: 22) {
            ForEach(0..<Int(w / 34) + 1, id: \.self) { i in
                Circle().fill([Color(hex: 0xFFD86B), Color(hex: 0xFF8FBE), Color(hex: 0x9FE3CF), Color(hex: 0xA9D4FF)][i % 4])
                    .frame(width: 11, height: 11)
                    .offset(y: i % 2 == 0 ? 0 : 7)
            }
        }
        .position(x: w / 2, y: h * 0.07)
        shelf(w, h, top: Color.white, front: Color(hex: 0xD3A877))
    }

    @ViewBuilder private func shelf(_ w: CGFloat, _ h: CGFloat, top: Color, front: Color) -> some View {
        Rectangle().fill(front.opacity(0.8)).frame(width: w, height: 16).position(x: w / 2, y: h * 0.8 + 13)
        RoundedRectangle(cornerRadius: 5).fill(top.opacity(0.95)).frame(width: w * 1.02, height: 12).position(x: w / 2, y: h * 0.8)
    }
}

/// A pennant, point down.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
