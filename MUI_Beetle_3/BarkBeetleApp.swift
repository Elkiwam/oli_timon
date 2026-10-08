import RealityKit
import SwiftUI

@main
struct BarkBeetleApp: App {

    @State private var appModel = AppModel()

    init() {
        LayerComponent.registerComponent()
        NutrientParticleComponent.registerComponent()
        SweepDiscComponent.registerComponent()
        LayerMotionSystem.registerSystem()
        ProceduralEffectSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup(id: AppConfig.welcomeWindowID) {
            WelcomeView()
                .environment(appModel)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: AppConfig.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
