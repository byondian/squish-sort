import SwiftUI

/// A comic speech bubble with a wobbly edge and a tail that points down at the Buddy.
struct WobblyBubble: Shape {
    /// Where along the bottom the tail sits, 0 to 1.
    var tailAt: CGFloat = 0.5
    var tail: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(1, rect.height - tail))
        let r = min(22, body.height / 2, body.width / 2)
        // Walk round a rounded box and push each point in and out a little, so the line looks hand drawn.
        let straightW = body.width - 2 * r, straightH = body.height - 2 * r
        let around = 2 * (straightW + straightH) + 2 * .pi * r
        let steps = max(48, Int(around / 6))
        var points: [CGPoint] = []
        for i in 0..<steps {
            var d = around * CGFloat(i) / CGFloat(steps)
            var p = CGPoint.zero, n = CGPoint.zero
            let corners: [(CGPoint, CGFloat)] = [
                (CGPoint(x: body.maxX - r, y: body.minY + r), -CGFloat.pi / 2), (CGPoint(x: body.maxX - r, y: body.maxY - r), 0),
                (CGPoint(x: body.minX + r, y: body.maxY - r), CGFloat.pi / 2), (CGPoint(x: body.minX + r, y: body.minY + r), CGFloat.pi),
            ]
            let sides: [(CGPoint, CGPoint, CGFloat, CGPoint)] = [
                (CGPoint(x: body.minX + r, y: body.minY), CGPoint(x: 1, y: 0), straightW, CGPoint(x: 0, y: -1)),
                (CGPoint(x: body.maxX, y: body.minY + r), CGPoint(x: 0, y: 1), straightH, CGPoint(x: 1, y: 0)),
                (CGPoint(x: body.maxX - r, y: body.maxY), CGPoint(x: -1, y: 0), straightW, CGPoint(x: 0, y: 1)),
                (CGPoint(x: body.minX, y: body.maxY - r), CGPoint(x: 0, y: -1), straightH, CGPoint(x: -1, y: 0)),
            ]
            var placed = false
            for k in 0..<4 where !placed {
                let side = sides[k]
                if d <= side.2 {
                    p = CGPoint(x: side.0.x + side.1.x * d, y: side.0.y + side.1.y * d)
                    n = side.3
                    placed = true
                    break
                }
                d -= side.2
                let arc = CGFloat.pi / 2 * r
                if d <= arc {
                    let a = corners[k].1 + d / max(r, 0.001)
                    n = CGPoint(x: cos(a), y: sin(a))
                    p = CGPoint(x: corners[k].0.x + n.x * r, y: corners[k].0.y + n.y * r)
                    placed = true
                    break
                }
                d -= arc
            }
            if !placed { continue }
            let wobble = sin(CGFloat(i) * 0.9) * 1.1 + sin(CGFloat(i) * 0.37 + 1) * 0.9
            points.append(CGPoint(x: p.x + n.x * wobble, y: p.y + n.y * wobble))
        }
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        // The tail.
        let x = body.minX + r + (body.width - 2 * r) * min(1, max(0, tailAt))
        var t = Path()
        t.move(to: CGPoint(x: x - 11, y: body.maxY - 2))
        t.addQuadCurve(to: CGPoint(x: x + 2, y: rect.maxY), control: CGPoint(x: x - 6, y: body.maxY + tail * 0.5))
        t.addQuadCurve(to: CGPoint(x: x + 11, y: body.maxY - 2), control: CGPoint(x: x + 8, y: body.maxY + tail * 0.5))
        t.closeSubpath()
        return path.union(t)
    }
}

/// What the Buddy says on Home: it pops in, writes itself on with tiny blips, and makes one word big.
/// Tinted by the kind of line. `extra` sits inside the same bubble (the mood faces).
struct BuddyBubble<Extra: View>: View {
    let text: String
    /// The line's trigger ("joke", "fact", "win", ...), which picks the tint.
    var kind = ""
    /// Shown before the line when the Buddy asks something ("Mochi asks:").
    var asker: String?
    var sounds: SoundService?
    @ViewBuilder var extra: () -> Extra
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0
    @State private var popped = false

    private var tint: Color {
        switch kind {
        case "joke": return Theme.butter
        case "fact": return Theme.mint
        case "win", "win_3star", "treat", "milestone", "capsule", "reply_happy": return Theme.bubblegum
        default: return Theme.sky
        }
    }

    /// The longest word of a line that has spaces: the one to make big. Nothing for languages without spaces.
    private var keyWord: Range<String.Index>? {
        var best: Range<String.Index>?
        var start: String.Index?
        var i = text.startIndex
        func close(_ end: String.Index) {
            guard let s = start else { return }
            if text.distance(from: s, to: end) >= 4,
               best.map({ text.distance(from: $0.lowerBound, to: $0.upperBound) < text.distance(from: s, to: end) }) ?? true {
                best = s..<end
            }
            start = nil
        }
        while i < text.endIndex {
            if text[i].isLetter { if start == nil { start = i } } else { close(i) }
            i = text.index(after: i)
        }
        close(text.endIndex)
        guard text.contains(" "), let found = best, text.distance(from: found.lowerBound, to: found.upperBound) <= 12 else { return nil }
        return found
    }

    private var written: AttributedString {
        let count = text.count
        let upTo = text.index(text.startIndex, offsetBy: min(shown, count))
        var out = AttributedString()
        func piece(_ range: Range<String.Index>, key: Bool) {
            guard range.lowerBound < range.upperBound else { return }
            let visibleEnd = min(range.upperBound, upTo)
            if range.lowerBound < visibleEnd {
                var a = AttributedString(String(text[range.lowerBound..<visibleEnd]))
                if key {
                    a.font = Theme.title(21)
                    a.foregroundColor = Theme.grape
                }
                out.append(a)
            }
            // The rest is there but see-through, so the bubble does not change size as it writes.
            if visibleEnd < range.upperBound, range.upperBound > upTo {
                var a = AttributedString(String(text[max(range.lowerBound, upTo)..<range.upperBound]))
                if key { a.font = Theme.title(21) }
                a.foregroundColor = Color.clear
                out.append(a)
            }
        }
        if let key = keyWord {
            piece(text.startIndex..<key.lowerBound, key: false)
            piece(key, key: true)
            piece(key.upperBound..<text.endIndex, key: false)
        } else {
            piece(text.startIndex..<text.endIndex, key: false)
        }
        return out
    }

    var body: some View {
        VStack(spacing: 8) {
            if let asker {
                Text("\(asker) asks:").font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.7))
            }
            Text(written)
                .font(Theme.body(16))
                .foregroundStyle(Theme.plum)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: text))
                .accessibilityIdentifier("buddy-says")
            extra()
        }
        .padding(.horizontal, 16).padding(.top, 11).padding(.bottom, 25)
        .background(WobblyBubble().fill(Color.white))
        .background(WobblyBubble().fill(tint).offset(x: 3, y: 4))
        .overlay(WobblyBubble().stroke(Theme.plum.opacity(0.75), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round)))
        .scaleEffect(popped ? 1 : 0.3, anchor: .bottom)
        .opacity(popped ? 1 : 0)
        .task(id: text) { await write() }
    }

    @MainActor private func write() async {
        shown = reduceMotion ? text.count : 0
        popped = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { popped = true }
        guard !reduceMotion else { return }
        let count = text.count
        var i = 0
        while i < count {
            try? await Task.sleep(nanoseconds: 28_000_000)
            if Task.isCancelled { return }
            i += 1
            shown = i
            if i % 4 == 1, !AppModel.isUITesting { sounds?.play("bubble_0\(1 + (i / 4) % 6)", volume: 0.12) }
        }
    }
}

extension BuddyBubble where Extra == EmptyView {
    init(text: String, kind: String = "", sounds: SoundService? = nil) {
        self.init(text: text, kind: kind, asker: nil, sounds: sounds) { EmptyView() }
    }
}
