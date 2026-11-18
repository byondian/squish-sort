import SwiftUI
import SquishPolicy

/// Ask a grown-up: a multiplication answered on the gate's own number keys. One try per
/// question and a pause after a wrong answer, so it can't be passed by guessing.
/// Guards purchases, leaving gentle mode and links out of the app.
struct ParentalGate: View {
    var onPass: () -> Void
    var onCancel: () -> Void
    /// The pause after a wrong answer outlasts closing and reopening the gate.
    private static var lockedUntil: Double = 0
    @State private var gate: ParentalGateState = {
        var rng = SystemRandomNumberGenerator()
        return ParentalGateState(using: &rng, lockedUntil: ParentalGate.lockedUntil)
    }()
    @State private var answer = ""
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 14) {
            Text("Ask a grown-up").font(Theme.title(26)).foregroundStyle(Theme.plum)
            Text("What is \(gate.a) × \(gate.b)?").font(Theme.body(22)).foregroundStyle(Theme.plum)
                .accessibilityIdentifier("gate-question")
            // The gate has its own number keys. The system keyboard is not used: on a phone it
            // has no return key and can cover OK, and on a tablet it is a full keyboard.
            Text(answer.isEmpty ? " " : answer)
                .font(Theme.title(30)).foregroundStyle(Theme.plum)
                .frame(width: 180, height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.plum.opacity(0.2), lineWidth: 2))
                .accessibilityIdentifier("gate-answer")
            // Only this line follows the clock, so a tick never redraws the keys.
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let now = timeline.date.timeIntervalSince1970
                Group {
                    if gate.isLocked(now: now) {
                        Text("Not quite. Try again in \(gate.secondsLeft(now: now)) s.")
                    } else if wrong {
                        Text("Here's a new question.")
                    } else {
                        Text(" ")
                    }
                }
                .font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
            }
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(1..<4, id: \.self) { column in key(row * 3 + column) }
                    }
                }
                HStack(spacing: 10) {
                    Button { if !answer.isEmpty { answer.removeLast() } } label: {
                        Image(systemName: "delete.left.fill").font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.plum).frame(width: 72, height: 56)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.6)))
                    }
                    .accessibilityIdentifier("gate-delete")
                    key(0)
                    Button { submit() } label: {
                        Text("OK").font(Theme.title(20)).foregroundStyle(.white).frame(width: 72, height: 56)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.sky))
                    }
                    .disabled(answer.isEmpty)
                    .opacity(answer.isEmpty ? 0.5 : 1)
                    .accessibilityIdentifier("gate-ok")
                }
            }
            Button("Close", action: onCancel).buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
        }
        .padding(24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.marshmallow.ignoresSafeArea())
    }

    private func key(_ digit: Int) -> some View {
        Button { if answer.count < 6 { answer.append(String(digit)) } } label: {
            Text(String(digit)).font(Theme.title(24)).foregroundStyle(Theme.plum).frame(width: 72, height: 56)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.plum.opacity(0.15), lineWidth: 2))
        }
        .accessibilityIdentifier("gate-key-\(digit)")
    }

    private func submit() {
        var rng = SystemRandomNumberGenerator()
        if gate.submit(answer, now: Date().timeIntervalSince1970, using: &rng) {
            onPass()
        } else {
            wrong = true
            answer = ""
            ParentalGate.lockedUntil = gate.lockedUntil
        }
    }
}
