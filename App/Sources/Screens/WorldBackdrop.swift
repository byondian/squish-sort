import SwiftUI

/// The room behind the jars. Each world has its own, kept soft and low in contrast
/// so the squishies stay the hero (level screen spec).
struct WorldBackdrop: View {
    let world: String

    /// Starlight Stage and Space Station are night scenes: jars glow and loose text turns white.
    static func isDark(_ world: String) -> Bool { world == "starlight" || world == "spacestation" }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                switch world {
                case "sweetfactory": sweetFactory(w, h)
                case "starlight": starlight(w, h)
                case "bubblebath": bubbleBath(w, h)
                case "junglejam": jungle(w, h)
                case "spacestation": spaceStation(w, h)
                case "morphlab": morphLab(w, h)
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

    /// Pale blue tiles, drifting bubbles and the white edge of the bath.
    @ViewBuilder private func bubbleBath(_ w: CGFloat, _ h: CGFloat) -> some View {
        Color(hex: 0xDFF6FF)
        stripes(w, Color.white.opacity(0.7), width: 3, gap: 41)
        VStack(spacing: 41) {
            ForEach(0..<Int(h / 44) + 2, id: \.self) { _ in Rectangle().fill(Color.white.opacity(0.7)).frame(height: 3) }
        }
        .frame(width: w, height: h, alignment: .top)
        .clipped()
        ForEach(0..<14, id: \.self) { i in
            let x = CGFloat((i * 67 + 23) % 100) / 100, y = CGFloat((i * 43 + 11) % 72) / 100
            let d: CGFloat = 14 + CGFloat(i % 4) * 9
            Circle().fill(Color.white.opacity(0.35))
                .overlay(Circle().stroke(i % 3 == 0 ? Color(hex: 0xFFC9DE) : Color.white, lineWidth: 2))
                .frame(width: d, height: d)
                .position(x: x * w, y: y * h)
        }
        shelf(w, h, top: Color.white, front: Color(hex: 0xFFC9DE))
    }

    /// Leafy green, hanging vines and a wooden plank.
    @ViewBuilder private func jungle(_ w: CGFloat, _ h: CGFloat) -> some View {
        Color(hex: 0xE3F5D8)
        ForEach(0..<8, id: \.self) { i in
            let x = CGFloat((i * 59 + 9) % 100) / 100, y = CGFloat((i * 37 + 5) % 60) / 100
            Ellipse().fill(Color(hex: 0xB8EBA8).opacity(0.7))
                .frame(width: 120, height: 54)
                .rotationEffect(.degrees(Double(i * 47 % 140) - 70))
                .position(x: x * w, y: y * h)
        }
        ForEach(0..<5, id: \.self) { i in
            let long: CGFloat = h * (0.1 + 0.04 * CGFloat(i % 3))
            Capsule().fill(Color(hex: 0x7CCB6B).opacity(0.75))
                .frame(width: 6, height: long)
                .position(x: w * (0.08 + 0.21 * CGFloat(i)), y: long / 2 - 4)
            Ellipse().fill(Color(hex: 0xFFE066).opacity(0.8))
                .frame(width: 13, height: 9)
                .position(x: w * (0.08 + 0.21 * CGFloat(i)), y: long)
        }
        shelf(w, h, top: Color(hex: 0xC99A66), front: Color(hex: 0x9C6E42))
    }

    /// Deep space through the station's portholes: star dots, one soft ringed planet, a metal shelf.
    @ViewBuilder private func spaceStation(_ w: CGFloat, _ h: CGFloat) -> some View {
        LinearGradient(colors: [Color(hex: 0x2E2A55), Color(hex: 0x3D3670)], startPoint: .top, endPoint: .bottom)
        ForEach(0..<30, id: \.self) { i in
            let x = CGFloat((i * 61 + 7) % 100) / 100, y = CGFloat((i * 37 + 11) % 74) / 100
            let size: CGFloat = 1.5 + CGFloat(i % 4) * 0.5
            Circle().fill(Color.white.opacity(0.5)).frame(width: size, height: size).position(x: x * w, y: y * h)
        }
        Ellipse().stroke(Color(hex: 0xFFB37A).opacity(0.3), lineWidth: 6)
            .frame(width: 190, height: 50)
            .rotationEffect(.degrees(-16))
            .position(x: w * 0.84, y: h * 0.17)
        Circle().fill(Color(hex: 0xC9A7F5).opacity(0.35)).frame(width: 110, height: 110).position(x: w * 0.84, y: h * 0.17)
        ForEach(0..<3, id: \.self) { i in
            Circle().fill(Color(hex: 0x4A4380))
                .overlay(Circle().stroke(Color(hex: 0x8C84C9), lineWidth: 4))
                .frame(width: 46, height: 46)
                .position(x: w * (0.16 + 0.2 * CGFloat(i)), y: h * 0.07)
        }
        shelf(w, h, top: Color(hex: 0x9AA6C2), front: Color(hex: 0x6E7A98))
    }

    /// A pale mint lab: outlined bubbles rising, a top shelf of flask shapes, a lilac bench.
    @ViewBuilder private func morphLab(_ w: CGFloat, _ h: CGFloat) -> some View {
        Color(hex: 0xE9FBF3)
        ForEach(0..<8, id: \.self) { i in
            let x = CGFloat((i * 53 + 13) % 100) / 100, y = CGFloat((i * 41 + 17) % 62) / 100
            let size: CGFloat = 12 + CGFloat(i * 7 % 29)
            Circle().stroke(Color(hex: 0xA8F0D8).opacity(0.6), lineWidth: 3)
                .frame(width: size, height: size)
                .position(x: x * w, y: (0.12 + y) * h)
        }
        ForEach(0..<6, id: \.self) { i in
            let tint: Color = [Color(hex: 0xFFC9DE), Color(hex: 0xC9A7F5), Color(hex: 0xB6F06A)][i % 3]
            let tall: CGFloat = 34 + CGFloat(i % 2) * 10
            RoundedRectangle(cornerRadius: 9).fill(tint.opacity(0.5))
                .frame(width: 24, height: tall)
                .position(x: w * (0.1 + 0.16 * CGFloat(i)), y: h * 0.075 - tall / 2 + 22)
        }
        shelf(w, h, top: Color(hex: 0xE3D3FF), front: Color(hex: 0xB9A3E8))
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
