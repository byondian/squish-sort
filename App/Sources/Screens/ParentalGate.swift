import SwiftUI

/// Ask a grown-up: a multiplication with four answers. Guards purchases and
/// leaving gentle mode.
struct ParentalGate: View {
    var onPass: () -> Void
    var onCancel: () -> Void
    @State private var a = Int.random(in: 6...9)
    @State private var b = Int.random(in: 6...9)
    @State private var options: [Int] = []
    @State private var wrong = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Ask a grown-up").font(Theme.title(26)).foregroundStyle(Theme.plum)
            Text("What is \(a) × \(b)?").font(Theme.body(22)).foregroundStyle(Theme.plum)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(options, id: \.self) { n in
                    Button("\(n)") {
                        if n == a * b { onPass() } else { wrong = true; reshuffle() }
                    }
                    .buttonStyle(SquishButtonStyle(fill: Theme.sky))
                }
            }
            if wrong { Text("Not quite. Try again.").font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7)) }
            Button("Close", action: onCancel).buttonStyle(SquishButtonStyle(fill: .white, text: Theme.plum))
        }
        .padding(28)
        .background(Theme.marshmallow.ignoresSafeArea())
        .onAppear(perform: reshuffle)
    }

    private func reshuffle() {
        a = Int.random(in: 6...9)
        b = Int.random(in: 6...9)
        var set: Set<Int> = [a * b]
        while set.count < 4 { set.insert(a * b + Int.random(in: -12...12)) }
        options = set.filter { $0 > 0 }.shuffled()
        if options.count < 4 { reshuffle() }
    }
}
