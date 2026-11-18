import SwiftUI
import SquishPolicy

/// Ask a grown-up: a multiplication answered on the number pad. One try per
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
    @FocusState private var typing: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let now = timeline.date.timeIntervalSince1970
            let locked = gate.isLocked(now: now)
            VStack(spacing: 18) {
                Text("Ask a grown-up").font(Theme.title(26)).foregroundStyle(Theme.plum)
                Text("What is \(gate.a) × \(gate.b)?").font(Theme.body(22)).foregroundStyle(Theme.plum)
                    .accessibilityIdentifier("gate-question")
                TextField("Answer", text: $answer)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.body(22))
                    .multilineTextAlignment(.center)
                    .frame(width: 140)
                    .focused($typing)
                    .disabled(locked)
                    .accessibilityIdentifier("gate-answer")
                if locked {
                    Text("Not quite. Try again in \(gate.secondsLeft(now: now)) s.")
                        .font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
                } else if wrong {
                    Text("Here's a new question.").font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
                }
                Button("OK") { submit() }
                    .buttonStyle(SquishButtonStyle(fill: Theme.sky))
                    .disabled(locked || answer.isEmpty)
                    .opacity(locked || answer.isEmpty ? 0.5 : 1)
                    .accessibilityIdentifier("gate-ok")
                Button("Close", action: onCancel).buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
            }
            .padding(28)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.marshmallow.ignoresSafeArea())
        .onAppear { typing = true }
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
