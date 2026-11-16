import SwiftUI

@main
struct SquishSortApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.purchases)
        }
    }
}

/// No title screen: the first thing a new player sees is Level 1.
struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.marshmallow.ignoresSafeArea()
            switch model.screen {
            case .level(let i) where model.levels.indices.contains(i):
                LevelView(index: i, model: model).id(i)
            case .level:
                Text("Levels missing from the bundle").font(Theme.body())
            case .home:
                HomeView()
            case .map:
                MapView()
            case .mystery:
                MysteryBagView()
            case .maker:
                MakerView()
            case .book:
                BookView()
            case .room:
                SquishRoomView()
            case .settings:
                SettingsView()
            case .shop:
                ShopView()
            }
        }
        .overlay {
            if let news = model.showingNews {
                NewsCard(news: news).id(news.id).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.showingNews)
        .fullScreenCover(item: $model.capsule, onDismiss: { model.capsuleDismissed() }) { c in
            CapsuleView(collectible: c) { model.capsuleClosed() }
                .environmentObject(model)
        }
        .fullScreenCover(isPresented: $model.askAge) {
            AgeQuestionView().environmentObject(model)
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                // A short thank-you that fades by itself. Never blocks a tap.
                Text(verbatim: toast).font(Theme.body(15)).foregroundStyle(Theme.plum)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.white))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_600_000_000)
                        model.toast = nil
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.toast)
        .preferredColorScheme(.light)
    }
}
