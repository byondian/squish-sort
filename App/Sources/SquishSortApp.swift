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
            case .map:
                MapView()
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
        .fullScreenCover(item: $model.capsule) { c in
            CapsuleView(collectible: c) { model.capsuleClosed() }
                .environmentObject(model)
        }
        .fullScreenCover(isPresented: $model.askAge) {
            AgeQuestionView().environmentObject(model)
        }
        .preferredColorScheme(.light)
    }
}
