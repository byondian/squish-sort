import SwiftUI
import UIKit

/// Soft Pop palette (game design doc). Text is plum on cream or white on bubblegum.
enum Theme {
    static let marshmallow = Color("Marshmallow")
    static let bubblegum = Color("Bubblegum")
    static let butter = Color("Butter")
    static let mint = Color("Mint")
    static let sky = Color("Sky")
    static let grape = Color("Grape")
    static let plum = Color("Plum")

    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func body(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static let plum = UIColor(hex: 0x3B2A4A)
    static let wrapper = UIColor(hex: 0xE4DCF0)
    static let ice = UIColor(hex: 0xBFE8FF)
}

/// Chunky pill button that squashes when pressed.
struct SquishButtonStyle: ButtonStyle {
    var fill: Color = Theme.bubblegum
    var text: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(18))
            .foregroundStyle(text)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(Theme.plum.opacity(0.15), lineWidth: 2))
            .scaleEffect(x: configuration.isPressed ? 1.08 : 1, y: configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.45), value: configuration.isPressed)
    }
}

/// The press squish alone, for buttons that draw their own shape.
struct PressSquish: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(x: configuration.isPressed ? 1.06 : 1, y: configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.45), value: configuration.isPressed)
    }
}

/// A gold coin, drawn the same everywhere coins appear. It takes its size from the font around it.
struct CoinIcon: View {
    var body: some View {
        ZStack {
            Image(systemName: "circle.fill").foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.22))
            Image(systemName: "circle").foregroundStyle(Color(red: 0.80, green: 0.53, blue: 0.08))
            Image(systemName: "star.fill").scaleEffect(0.45).foregroundStyle(Color(red: 1.0, green: 0.93, blue: 0.62))
        }
        .accessibilityHidden(true)
    }
}
