import SwiftUI

/// Squishy Workshop: the little-kids app. A room to squeeze squishies in and the Workshop to make
/// new ones. No ads, no SDKs, nothing collected, no reading needed. It shares the squish engine,
/// the art, the sounds and the Workshop with Squish Sort (build flag KIDS).
@main
struct SquishyWorkshopApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            KidsRootView()
                .environmentObject(model)
                .environmentObject(model.purchases)
        }
    }
}

/// One level deep: the room is home, and the Workshop is one big door in it.
struct KidsRootView: View {
    @EnvironmentObject var model: AppModel
    @State private var grownUps = false

    var body: some View {
        ZStack {
            Theme.marshmallow.ignoresSafeArea()
            if model.screen == .maker {
                WorkshopView().frame(maxWidth: 760).transition(.opacity)
            } else {
                KidsRoomView().transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.screen)
        // Anything closed in the Workshop leads here: the gate first, then the Grown-ups corner.
        .fullScreenCover(isPresented: $model.grownUpAsk) {
            KidsGate(onPass: {
                model.grownUpAsk = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { grownUps = true }
            }, onCancel: { model.grownUpAsk = false })
        }
        .sheet(isPresented: $grownUps) {
            GrownUpsView().environmentObject(model).environmentObject(model.purchases)
        }
        .preferredColorScheme(.light)
    }
}
