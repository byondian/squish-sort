import SwiftUI
import SquishPolicy

/// Twist of the week: this week's theme, its five boards, the prize and the sticker card.
/// Nothing counts down and nothing is lost: every theme comes back, and boards won stay won.
struct WeeklyTwistView: View {
    @EnvironmentObject var model: AppModel
    /// Closes the sheet; the play button also starts the board.
    let close: () -> Void

    static let stickerTray = "stickers-and-patterns"

    var body: some View {
        let theme = model.weeklyTheme ?? WeeklyTwist.themes[0]
        let played = model.weeklyPlayed
        let owned = model.progress.weekly.hasSticker(theme)
        ScrollView {
            VStack(spacing: 14) {
                Text("Twist of the week").font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.7))
                Text(AppModel.weeklyName(theme)).font(Theme.title(30)).foregroundStyle(Theme.plum)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("weekly-theme")
                Text(verbatim: AppModel.weeklyRule(theme)?.line ?? String(localized: "A bit of everything!"))
                    .font(Theme.body(15)).foregroundStyle(Theme.plum.opacity(0.8)).multilineTextAlignment(.center)
                // The five boards: a tick for each one played this week.
                HStack(spacing: 10) {
                    ForEach(1...WeeklyTwist.boardsPerTheme, id: \.self) { n in
                        ZStack {
                            Circle().fill(played.contains(n) ? Theme.mint : Color.white)
                            Circle().stroke(Theme.plum.opacity(0.15), lineWidth: 2)
                            if played.contains(n) {
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .heavy)).foregroundStyle(.white)
                            } else {
                                Text(verbatim: "\(n)").font(Theme.title(17)).foregroundStyle(Theme.plum.opacity(0.6))
                            }
                        }
                        .frame(width: 42, height: 42)
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(Text(verbatim: "\(played.count)/\(WeeklyTwist.boardsPerTheme)"))
                prize(theme: theme, owned: owned)
                if let next = model.weeklyNext {
                    Button {
                        close()
                        model.playWeekly()
                    } label: {
                        Text("Play board \(next)").font(Theme.title(22)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 58)
                            .background(Capsule().fill(Theme.bubblegum))
                    }
                    .buttonStyle(PressSquish())
                    .accessibilityIdentifier("weekly-play")
                } else {
                    Text("All five done! A new twist is on its way.").font(Theme.title(18)).foregroundStyle(Theme.plum)
                        .multilineTextAlignment(.center)
                }
                stickerCard(current: theme)
                if AppModel.isTesterBuild {
                    Button { model.testerNextWeek() } label: { Text(verbatim: "Tester: next week's twist") }
                        .font(Theme.body(14))
                }
            }
            .padding(22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.marshmallow.ignoresSafeArea())
    }

    /// What the theme gives: its sticker and a wearable, or coins once the sticker is on the card.
    private func prize(theme: String, owned: Bool) -> some View {
        HStack(spacing: 12) {
            WeeklyTwistView.sticker(theme, size: 54)
            if !owned, let gift = WeeklyTwist.gift(theme: theme), let image = WorkshopArt.part(gift.category, gift.part) {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 54, height: 54)
            }
            Group {
                if owned {
                    Text("You have this sticker. All 5 boards this week give \(WeeklyTwist.coinsWhenOwned) more coins.")
                } else {
                    Text("Win all 5 boards for the sticker and a prize your Buddy can wear.")
                }
            }
            .font(Theme.body(14)).foregroundStyle(Theme.plum).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
    }

    /// One place for each theme's sticker. A theme not finished yet shows how far it is.
    private func stickerCard(current: String) -> some View {
        let state = model.progress.weekly
        return VStack(spacing: 10) {
            Text("Sticker card \(state.stickers.count)/\(WeeklyTwist.themes.count)").font(Theme.title(18)).foregroundStyle(Theme.plum)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(WeeklyTwist.themes, id: \.self) { theme in
                    let has = state.hasSticker(theme)
                    VStack(spacing: 3) {
                        WeeklyTwistView.sticker(theme, size: 46)
                            .saturation(has ? 1 : 0).opacity(has ? 1 : 0.3)
                        Text(verbatim: has ? "✓" : "\(state.towardsSticker(theme))/\(WeeklyTwist.boardsPerTheme)")
                            .font(Theme.body(12)).foregroundStyle(Theme.plum.opacity(0.7))
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14).fill(theme == current ? Theme.butter.opacity(0.5) : .white))
                    .accessibilityElement()
                    .accessibilityLabel(Text(AppModel.weeklyName(theme)))
                }
            }
            Text("Every twist comes back soon. Boards you won stay won.")
                .font(Theme.body(13)).foregroundStyle(Theme.plum.opacity(0.7)).multilineTextAlignment(.center)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.6)))
        .accessibilityIdentifier("sticker-card")
    }

    /// A theme's sticker: one of the Workshop's sticker pictures.
    @ViewBuilder static func sticker(_ theme: String, size: CGFloat) -> some View {
        if let image = WorkshopArt.part(stickerTray, WeeklyTwist.sticker(theme: theme)) {
            Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: "star.circle.fill").font(.system(size: size * 0.8)).foregroundStyle(Theme.butter)
                .frame(width: size, height: size)
        }
    }
}
