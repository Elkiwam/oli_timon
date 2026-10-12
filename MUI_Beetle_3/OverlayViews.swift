import SwiftUI

/// Title panel attached to a layer. Shown while the layer is dragged, separated, or selected.
struct LayerInfoView: View {

    let layer: Layer
    let appModel: AppModel

    private var isFaded: Bool {
        appModel.selectedLayer != nil && appModel.selectedLayer != layer
    }

    var body: some View {
        Text(layer.title)
            .font(.system(size: 32, weight: .semibold, design: .default))
            .padding(28)
            .glassBackgroundEffect()
            .scaleEffect(1.5)
            .opacity(isFaded ? Double(AppConfig.fadedOpacity) : 1)
    }
}

/// Description panel below a layer. Shown only when the layer is selected.
struct LayerDescriptionView: View {

    let layer: Layer

    var body: some View {
        Text(layer.summary)
            .font(.title3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(28)
            .frame(width: 500, alignment: .leading)
            .glassBackgroundEffect()
            .scaleEffect(1.5)
    }
}

/// Combined control panel: instruction hint + recombine/exit buttons, below the log.
struct ControlPanelView: View {

    let appModel: AppModel
    let onRecombine: @MainActor () -> Void
    let onExit: @MainActor () -> Void

    private var hint: String {
        if appModel.selectedLayer != nil {
            return "Tap again to deselect."
        } else if appModel.hasSeparatedLayers {
            return "Tap a layer to inspect it."
        } else {
            return "Pinch a layer and pull it aside."
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(hint)
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    onRecombine()
                } label: {
                    Label("Recombine", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .disabled(!appModel.hasSeparatedLayers && appModel.selectedLayer == nil)

                Button {
                    onExit()
                } label: {
                    Label("", systemImage: "xmark")
                }
            }
        }
        .padding(16)
        .glassBackgroundEffect()
    }
}
