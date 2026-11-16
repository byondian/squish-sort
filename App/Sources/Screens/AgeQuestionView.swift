import SwiftUI
import SquishPolicy

/// The birthday question, asked by the collection book after the first capsule
/// and before any ad, tracking or purchase screen exists.
/// iOS 26+: Apple's Declared Age Range first. Otherwise a neutral year picker
/// with no default; skip means gentle mode.
struct AgeQuestionView: View {
    @EnvironmentObject var model: AppModel
    @State private var year: Int?
    @State private var triedSystem = false

    private var currentYear: Int { Calendar(identifier: .gregorian).component(.year, from: Date()) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            SquishyView(id: "peach-bun", rarity: .rare).frame(width: 120, height: 120)
            Text("To set up your collection book, what year were you born?")
                .font(Theme.title(24))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.plum)
            Picker("Year", selection: $year) {
                Text("—").tag(Int?.none)
                ForEach((currentYear - 100...currentYear).reversed(), id: \.self) { y in
                    Text(String(y)).tag(Int?.some(y))
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
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
