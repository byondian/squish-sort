import SwiftUI
import SquishPolicy

/// The birthday question, asked by the collection book after the first capsule
/// and before any ad, tracking or purchase screen exists.
/// iOS 26+: Apple's Declared Age Range first. Otherwise a neutral choice of decade
/// then year, with no default; skip means gentle mode.
struct AgeQuestionView: View {
    @EnvironmentObject var model: AppModel
    @State private var year: Int?
    @State private var decade: Int?
    @State private var triedSystem = false

    private var currentYear: Int { Calendar(identifier: .gregorian).component(.year, from: Date()) }

    /// This decade back to a hundred years ago, newest first.
    private var decades: [Int] {
        let newest = currentYear / 10 * 10
        return stride(from: newest, through: newest - 100, by: -10).map { $0 }
    }

    private func choice(_ title: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(Theme.body(17))
                .foregroundStyle(chosen ? .white : Theme.plum)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(RoundedRectangle(cornerRadius: 14).fill(chosen ? Theme.bubblegum : Color.white))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.plum.opacity(0.15), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            // The Buddy asks (Peach Bun, unless the player has swapped already).
            SpeechBubble(text: String(localized: "What year were you born? This helps us show the right ads and settings."))
            SquishRefView(ref: model.progress.buddy.squishy ?? "peach-bun").frame(width: 120, height: 120)
            // Two taps and no wheel: the decade, then the year. Nothing is chosen to begin with.
            if let decade {
                HStack {
                    Button { withAnimation { self.decade = nil; year = nil } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(verbatim: "\(decade)s")
                        }
                    }
                    .font(Theme.body(16)).foregroundStyle(Theme.plum.opacity(0.7))
                    .accessibilityIdentifier("age-back")
                    Spacer()
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach((decade...min(decade + 9, currentYear)), id: \.self) { y in
                        choice(String(y), chosen: year == y) { year = y }
                            .accessibilityIdentifier("year-\(y)")
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(decades, id: \.self) { d in
                        choice("\(String(d))s", chosen: false) { withAnimation { decade = d } }
                            .accessibilityIdentifier("decade-\(d)")
                    }
                }
            }
            Button("Continue") {
                model.setAge(range: AgePolicy.range(birthYear: year, currentYear: currentYear), source: .birthYear)
            }
            .buttonStyle(SquishButtonStyle())
            .disabled(year == nil)
            .opacity(year == nil ? 0.5 : 1)
            Button("Skip") { model.setAge(range: nil, source: .skipped) }
                .font(Theme.body(16))
                .foregroundStyle(Theme.plum.opacity(0.7))
            Spacer()
        }
        .padding(24)
        .background(Theme.marshmallow.ignoresSafeArea())
        .task {
            guard !triedSystem else { return }
            triedSystem = true
            if let range = await DeclaredAge.request(storefront: model.storefront) {
                model.setAge(range: range, source: .declaredAgeRange)
            }
        }
    }
}
