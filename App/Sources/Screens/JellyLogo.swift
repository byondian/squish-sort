import SwiftUI

/// The Squish Sort logo: ten jelly letters, each with a slow wobble of its own.
/// One spring pop-in on first show. With Reduce Motion the letters just sit there.
struct JellyLogo: View {
    /// 1 is the full size, 276 x 181 points.
    var scale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var start = Date()

    private static let size = CGSize(width: 276, height: 181)
    private static let loop = 2.6
    /// Image, left, top, width, height (points in the full logo) and wobble delay in seconds.
    private static let letters: [(String, CGFloat, CGFloat, CGFloat, CGFloat, Double)] = [
        ("logo-letter-01", 4, 4, 74.6, 105.1, 0.0),
        ("logo-letter-02", 51, 5.3, 69.8, 102.5, 0.08),
        ("logo-letter-03", 96.3, 5.6, 70.6, 101.9, 0.16),
        ("logo-letter-04", 141, 5.9, 47.9, 101.3, 0.24),
        ("logo-letter-05", 161.8, 5.2, 63.8, 102.6, 0.32),
        ("logo-letter-06", 199.2, 4.9, 72.7, 103.3, 0.4),
        ("logo-letter-07", 57, 84.5, 64.3, 90.6, 0.5),
        ("logo-letter-08", 96, 85, 63.4, 89.6, 0.58),
        ("logo-letter-09", 134.5, 85.1, 55.6, 89.4, 0.66),
        ("logo-letter-10", 163.8, 84.7, 57.5, 90.2, 0.74),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            ZStack(alignment: .topLeading) {
                ForEach(JellyLogo.letters, id: \.0) { letter in
                    let w = reduceMotion ? (x: 1.0, y: 1.0, dy: 0.0) : JellyLogo.wobble(at: t - letter.5 - 0.8)
                    Image(letter.0).resizable()
                        .frame(width: letter.3, height: letter.4)
                        .scaleEffect(x: w.x, y: w.y, anchor: .bottom)
                        .offset(y: w.dy)
                        .scaleEffect(shown || reduceMotion ? 1 : 0.6)
                        .opacity(shown || reduceMotion ? 1 : 0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.5).delay(letter.5), value: shown)
                        .offset(x: letter.1, y: letter.2)
                }
            }
            .frame(width: JellyLogo.size.width, height: JellyLogo.size.height, alignment: .topLeading)
        }
        .scaleEffect(scale)
        .frame(width: JellyLogo.size.width * scale, height: JellyLogo.size.height * scale)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Squish Sort"))
        .onAppear {
            start = Date()
            shown = true
        }
    }

    /// One 2.6 s loop: squash down a little at 45%, stretch up at 60%, back to rest.
    static func wobble(at time: Double) -> (x: Double, y: Double, dy: Double) {
        guard time > 0 else { return (1, 1, 0) }
        let p = time.truncatingRemainder(dividingBy: loop) / loop
        let keys: [(Double, Double, Double, Double)] = [(0, 1, 1, 0), (0.45, 1.06, 0.94, 2), (0.6, 0.97, 1.04, -3), (1, 1, 1, 0)]
        for i in 1..<keys.count where p <= keys[i].0 {
            let a = keys[i - 1], b = keys[i]
            let u = (p - a.0) / (b.0 - a.0)
            let e = u * u * (3 - 2 * u) // ease in and out
            return (a.1 + (b.1 - a.1) * e, a.2 + (b.2 - a.2) * e, a.3 + (b.3 - a.3) * e)
        }
        return (1, 1, 0)
    }
}

/// A glossy jelly button: a colour gradient with a shine across the top half and a darker rim.
struct JellyButtonStyle: ButtonStyle {
    let colors: [Color]
    var rim: Color
    var radius: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: radius).fill(rim).offset(y: 5)
                    RoundedRectangle(cornerRadius: radius)
                        .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: radius - 6)
                        .fill(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .padding(.horizontal, 8).padding(.top, 5)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .scaleEffect(x: 1, y: 0.5, anchor: .top)
                }
            }
            .scaleEffect(x: configuration.isPressed ? 1.04 : 1, y: configuration.isPressed ? 0.93 : 1, anchor: .bottom)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
