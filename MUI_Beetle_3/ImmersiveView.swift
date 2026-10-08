import RealityKit
import SwiftUI

/// The immersive space: the log, its gestures, and the way back to the welcome window.
struct ImmersiveView: View {

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @State private var controller: LayerController?

    var body: some View {
        RealityView { content in
            let controller = LayerController(appModel: appModel)
            self.controller = controller
            let root = await controller.buildScene(onExit: {
                Task { await dismissImmersiveSpace() }
            })
            content.add(root)
        }
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { controller?.handleDragChanged($0) }
                .onEnded { _ in controller?.handleDragEnded() }
        )
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { controller?.handleTap(on: $0.entity) }
        )
        .onDisappear {
            appModel.reset()
            openWindow(id: AppConfig.welcomeWindowID)
        }
    }
}
