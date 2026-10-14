import SwiftUI
import RealityKit
import simd
import UIKit

// MARK: - Trunk layers

/// Trunk layers, ordered from outside to inside (= order of dissection).
enum TrunkLayer: String, CaseIterable, Identifiable {
    case rinde, bast, kambium, splint, kern

    var id: String { rawValue }

    /// Name of the asset in your RealityKitContent package, without ".usdz".
    /// EDIT THESE to match your files exactly (case-sensitive).
    var modelName: String {
        switch self {
        case .rinde:   "Rinde"
        case .bast:    "Bast"
        case .kambium: "Kambium"
        case .splint:  "Splint"
        case .kern:    "Kern"
        }
    }

    var title: String {
        switch self {
        case .rinde:   "Rinde (Bark)"
        case .bast:    "Bast (Phloem)"
        case .kambium: "Kambium (Cambium)"
        case .splint:  "Splint (Sapwood)"
        case .kern:    "Kern (Heartwood)"
        }
    }

    var info: String {
        switch self {
        case .rinde:
            "Protects the tree. Bark beetles bore through it to reach the layer beneath."
        case .bast:
            "Transports sugars down from the crown. Beetles lay eggs here and the larvae eat the typical gallery patterns."
        case .kambium:
            "A very thin growth layer that forms new bast and wood. The feeding tunnels run along it, and if they cut around it, the tree dies."
        case .splint:
            "Living wood that carries water and nutrients upward. Infested trees dry out because this flow is interrupted."
        case .kern:
            "Dead, stable inner wood. It gives the trunk strength but takes no part in transport."
        }
    }

    /// Fine-tune a layer's position in metres, relative to the trunk centre
    /// (x = right, y = up, z = towards you).
    var manualOffset: SIMD3<Float> {
        switch self {
        case .rinde:   [0, 0, 0]
        case .bast:    [0, 0, 0]
        case .kambium: [0, 0, 0]
        case .splint:  [0, 0, 0]
        case .kern:    [0, 0, 0]
        }
    }

    /// Fine-tune a layer's orientation in degrees (x = pitch, y = yaw, z = roll),
    /// rotating around the trunk centre.
    var manualRotationDegrees: SIMD3<Float> {
        switch self {
        case .rinde:   [0, -90, 0]
        case .bast:    [0, -90, 0]
        case .kambium: [0, -90, 0]
        case .splint:  [0, -90, 0]
        case .kern:    [0, -90, 0]
        }
    }

    // Placeholder look, used only when an asset fails to load
    var placeholderRadius: Float {
        switch self {
        case .rinde: 0.20
        case .bast: 0.18
        case .kambium: 0.172
        case .splint: 0.15
        case .kern: 0.07
        }
    }

    var placeholderColor: UIColor {
        switch self {
        case .rinde:   UIColor(red: 0.36, green: 0.25, blue: 0.16, alpha: 1)
        case .bast:    UIColor(red: 0.85, green: 0.75, blue: 0.55, alpha: 1)
        case .kambium: UIColor(red: 0.55, green: 0.75, blue: 0.40, alpha: 1)
        case .splint:  UIColor(red: 0.90, green: 0.80, blue: 0.60, alpha: 1)
        case .kern:    UIColor(red: 0.55, green: 0.35, blue: 0.22, alpha: 1)
        }
    }
}

/// Anything that can be tapped and inspected: the five layers, the feeding tunnel, the beetle.
enum Inspectable: Equatable {
    case layer(TrunkLayer)
    case tunnel
    case beetle

    init?(entityName: String) {
        if let layer = TrunkLayer(rawValue: entityName) { self = .layer(layer) }
        else if entityName == Layout.feedingTunnel { self = .tunnel }
        else if entityName == Layout.beetle { self = .beetle }
        else { return nil }
    }

    var entityName: String {
        switch self {
        case .layer(let layer): layer.rawValue
        case .tunnel:           Layout.tunnelEntityName
        case .beetle:           Layout.beetle
        }
    }

    var title: String {
        switch self {
        case .layer(let layer): layer.title
        case .tunnel:           "Feeding tunnel (Fraßgang)"
        case .beetle:           "Bark beetle (Borkenkäfer)"
        }
    }

    var info: String {
        switch self {
        case .layer(let layer): layer.info
        case .tunnel: "The beetles bore tunnels just under the bark. The mother beetle lays her eggs along the main tunnel, and the hatching larvae eat side tunnels of their own. Together they form the typical gallery pattern. These tunnels interrupt the sugar transport, and if they girdle the trunk the cambium dies."
        case .beetle: "Bark beetles are only a few millimetres long. Pioneers bore into weakened trees and release scent signals that attract thousands of others. This mass attack overwhelms the tree's resin defence within days."
        }
    }
}
// MARK: - Scene configuration (metres / degrees, relative to the user's starting position)

enum Layout {
    /// Extra distance (metres) to push the whole scene away from the viewer.
    static let sceneDepth: Float = 0

    // Trunk
    static let trunkCenter: SIMD3<Float> = [0, 1.25, -1.9 - sceneDepth]
    static let trunkDiameter: Float = 0.3

    // Feeding tunnel and beetle: keep your current constants (unchanged)
    static let feedingTunnel = "feedingTunnel"   // asset name in RealityKitContent
    static let tunnelEntityName = "feedingTunnel"
    static let beetle = "beetle"
    static let tunnelFitFraction: Float = 0.55
    static let tunnelRotationDegrees: SIMD3<Float> = [90, -90, 90]
    static let tunnelOffset: SIMD3<Float> = [0, -0.15, 0]
    static let beetleLength: Float = 0.06
    static let beetleRotationDegrees: SIMD3<Float> = [90, 90, 90]
    static let beetleOffset: SIMD3<Float> = [0, -0.15, 0]
    static let beetleAlongTunnel: Float = 0.15

    // Table: directly in front of the viewer, tilted up
    static let tableModelName = "Table"
    static let tableWidth: Float = 1.5                       // model is scaled to this width
    static let tableModelScale: Float = 1
    static let tableModelRotationDegrees: SIMD3<Float> = [0, 0, 0]   // [0, 180, 0] if flat edge faces away
    static let tableModelOffset: SIMD3<Float> = [0, 0, 0]
    /// Middle of the table's flat (near) edge, on its top surface.
    static let tablePosition: SIMD3<Float> = [0, 1.05, -0.55 - sceneDepth]
    static let tableTiltDegrees: Float = 12

    // Magnetic pads: 7 = 5 layers + tunnel + beetle
    static let slotCount = 7
    static let slotSpacing: Float = 0.33
    static let nearRowDistance: Float = 0.22
    static let snapDistance: Float = 0.3

    // Phase 3 (inspect): enlarged model + info panel floating in front of the viewer.
    // Deliberately independent of `sceneDepth`, so it always stays within arm's reach.
    static let showcaseHost = "ShowcaseHost"
    static let showcasePrefix = "showcase:"
    static let panelID = "infoPanel"
    static let showcasePosition: SIMD3<Float> = [0, 1.5, -0.85]   // centre between model and panel
    static let showcaseOffset: SIMD3<Float> = [-0.25, 0, 0]       // enlarged model, left of centre
    static let panelOffset: SIMD3<Float> = [0.25, 0, 0]           // info panel, right of centre
    static let showcaseSize: Float = 0.42                          // longest side of the enlarged model (m)
    static let showcaseTiltDegrees: Float = 25                     // tilts the top towards the viewer
    static let showcaseSpinPerMetre: Float = 8                     // drag-to-rotate sensitivity (rad / m)

    static var tableRotation: simd_quatf { rotation(degrees: [tableTiltDegrees, 0, 0]) }

    /// Pads 0-3: near row (4). Pads 4-6: far row (3), staggered between them.
    static func slotLocal(_ i: Int) -> SIMD3<Float> {
        if i < 4 {
            return [(Float(i) - 1.5) * slotSpacing, 0, -nearRowDistance]
        } else {
            return [(Float(i - 4) - 1) * slotSpacing, 0, -(nearRowDistance + slotSpacing * 0.866)]
        }
    }

    // slotWorld(_:lift:) and rotation(degrees:) stay exactly as they are
    /// Slot position in room coordinates, lifted by `lift` metres along the table's normal.
    static func slotWorld(_ i: Int, lift: Float = 0) -> SIMD3<Float> {
        tablePosition + tableRotation.act(slotLocal(i) + [0, lift, 0])
    }

    /// Euler degrees (x pitch, y yaw, z roll) to a quaternion.
    static func rotation(degrees d: SIMD3<Float>) -> simd_quatf {
        let k = Float.pi / 180
        return simd_quatf(angle: d.y * k, axis: [0, 1, 0])
             * simd_quatf(angle: d.x * k, axis: [1, 0, 0])
             * simd_quatf(angle: d.z * k, axis: [0, 0, 1])
    }
}

// MARK: - Phases and state

enum Phase: Int, CaseIterable {
    case intro, dissect, arrange, review
}

@Observable @MainActor
final class AppModel {
    static let spaceID = "TrunkSpace"

    var phase: Phase = .intro
    var detached: Set<TrunkLayer> = []
    var placed: [TrunkLayer: Int] = [:]      // layer -> slot index
    var selected: TrunkLayer?
    var selectedLayer: Layer?                     // currently selected layer (tap highlight)
    var draggingLayer: Layer?                     // layer currently being dragged
    var separatedLayers: Set<Layer> = []          // layers that have been pulled apart
    var innerLogRevealed = false                  // true after the user's first tap on inner wood
    var isDraggingControlPanel = false            // drives drag bar visual feedback
    var hasSeparatedLayers: Bool { !separatedLayers.isEmpty }

    // MARK: Object Tracking
    /// True once the ARKit ObjectTrackingProvider has detected the physical log.
    var logDetected = false
    /// True when all layers have been revealed (separated).
    var allLayersRevealed: Bool { separatedLayers.count == Layer.allCases.count }
    /// Controls tooltip visibility: detected but not all revealed.
    var showTooltip: Bool { logDetected && !allLayersRevealed }
    /// Dragging is only enabled after the log is detected.
    var isDragEnabled: Bool { logDetected }

    /// The next layer the user must drag, enforcing the outside-to-inside sequence.
    var nextDraggableLayer: Layer? {
        Layer.allCases.first { !separatedLayers.contains($0) }
    }
    var inspected: Inspectable?                   // phase 3: model currently shown enlarged
    var extraSlots: [String: Int] = [:]           // tunnel / beetle (by entity name) -> pad index

    var occupiedSlots: Set<Int> {
        Set(placed.values).union(extraSlots.values)
    }

    /// The outermost layer that is still attached to the trunk.
    var nextToDetach: TrunkLayer? {
        TrunkLayer.allCases.first { !detached.contains($0) }
    }

    func markDetached(_ layer: TrunkLayer) {
        detached.insert(layer)
        if detached.count == TrunkLayer.allCases.count { phase = .arrange }
    }

    func markPlaced(_ layer: TrunkLayer, slot: Int) {
        placed[layer] = slot
        if placed.count == TrunkLayer.allCases.count { phase = .review }
    }

    /// Clears drag/selection/separation state without changing the phase.
    func resetInteractionState() {
        selectedLayer = nil
        draggingLayer = nil
        separatedLayers = []
        innerLogRevealed = false
    }

    /// Back to the initial starting state.
    func reset() {
        phase = .intro
        detached = []
        placed = [:]
        selected = nil
        inspected = nil
        extraSlots = [:]
        logDetected = false
        resetInteractionState()
    }
}

