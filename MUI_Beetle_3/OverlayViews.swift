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

/// Floating tooltip shown above the log after object detection.
struct TooltipView: View {
    let appModel: AppModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.pinch")
                .font(.title2)
            Text(AppConfig.tooltipText)
                .font(.title3.weight(.medium))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .glassBackgroundEffect()
        .scaleEffect(1.5)
    }
}

/// Floating tooltip shown after all layers are revealed.
struct TapHintTooltipView: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.title2)
            Text("Tap a layer to reveal more information")
                .font(.title3.weight(.medium))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .glassBackgroundEffect()
        .scaleEffect(1.5)
    }
}

/// Combined control panel: instruction hint + recombine/exit buttons, below the log.
struct ControlPanelView: View {

    let appModel: AppModel
    let onRecombine: @MainActor () -> Void
    let onExit: @MainActor () -> Void

    // Hints moved to standalone tooltip views; kept for reference.
    // private var hint: String {
    //     if !appModel.logDetected {
    //         return "Point at the log to begin."
    //     } else if appModel.selectedLayer != nil {
    //         return "Tap again to deselect."
    //     } else if appModel.hasSeparatedLayers {
    //         return "Tap a layer to inspect it."
    //     } else {
    //         return "Pinch a layer and swipe up."
    //     }
    // }

    var body: some View {
        VStack(spacing: 12) {
            // Text(hint)
            //     .font(.title3)
            //     .foregroundStyle(.secondary)

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

/// Drag handle below the control panel. Reacts to hover and drag.
struct DragBarView: View {

    let appModel: AppModel
    @State private var isHovered = false

    private var isDragging: Bool { appModel.isDraggingControlPanel }

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.white.opacity(isHovered || isDragging ? 0.7 : 0.35))
            .frame(width: isDragging ? 56 : 40, height: 6)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
}
