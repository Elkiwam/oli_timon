import SwiftUI

/// Info panel attached to a layer. Shown while the layer is dragged or selected.
struct LayerInfoView: View {

    let layer: Layer
    let appModel: AppModel

    private var isSelected: Bool { appModel.selectedLayer == layer }
    private var isDragging: Bool { appModel.draggingLayer == layer }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(layer.title)
                .font(.system(size: 32, weight: .semibold, design: .default))

            if isSelected {
                Text(layer.summary)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                //tap again to deselect info text
                Text(" ")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(width: isSelected ? 500 : nil, alignment: .leading)
        .glassBackgroundEffect()
        .scaleEffect(1.5)
    }
}

/// Control panel low in the user's view: recombine the log, or leave the experience.
struct ControlPanelView: View {

    let appModel: AppModel
    let onRecombine: @MainActor () -> Void
    let onExit: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button {
                onRecombine()
            } label: {
                Label("Recombine layers", systemImage: "arrow.down.right.and.arrow.up.left")
            }
            .disabled(!appModel.hasSeparatedLayers && appModel.selectedLayer == nil)

            Button {
                onExit()
            } label: {
                Label("Exit", systemImage: "xmark")
            }
        }
        .padding(12)
        .glassBackgroundEffect()
        .scaleEffect(0.7)
    }
}
