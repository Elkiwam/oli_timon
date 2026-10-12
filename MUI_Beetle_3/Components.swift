import RealityKit
import simd

/// Runtime state of one layer. Added to each of the five layer entities by `LayerController`.
/// `LayerMotionSystem` reads it every frame, so the controller only ever changes targets.
struct LayerComponent: Component {
    var layer: Layer

    // Positions are in the space of the log root (the layers' parent).
    var restPosition: SIMD3<Float>
    var explodedPosition: SIMD3<Float>
    /// Logical position. Follows the hand while dragging, otherwise eases toward `targetPosition`.
    var basePosition: SIMD3<Float>
    var targetPosition: SIMD3<Float>

    var baseScale: SIMD3<Float>
    var baseOrientation: simd_quatf
    /// Direction of the layer's long axis in the log root's space.
    var longAxis: SIMD3<Float>

    /// Centre of the layer's bounds relative to its origin (log root space, at rest).
    /// Scaling and turning happen around this point, so the layer never drifts.
    var panelCenter: SIMD3<Float>
    /// Height (log root space) at which the info panel floats.
    var panelBaseY: Float
    var panelID: Entity.ID?
    var descriptionPanelID: Entity.ID?

    // Info-panel fade (smooth show/hide on select).
    var panelTargetOpacity: Float = 0
    var panelCurrentOpacity: Float = 0

    var isDragging = false
    var isSeparated = false

    // Fade. Starts at 0 so the log fades in when it appears.
    var currentOpacity: Float = 0
    var targetOpacity: Float = 1
    var appliedOpacity: Float = -1

    // Persistent scale (the beetle grows while selected).
    var currentScale: Float = 1
    var targetScale: Float = 1

    // Transient effect (bark pulse, inner log turn).
    var effectStart: Double?
    var effectDuration: Double = 1
}

/// Tag for the draggable control panel so gestures can identify it.
struct ControlPanelTag: Component {}

/// Tag for description panels so tap gestures can ignore them.
struct DescriptionPanelTag: Component {}

/// One sugar droplet streaming along the cambium. All numbers are in the layer's local space.
struct NutrientParticleComponent: Component {
    var center: SIMD3<Float>
    var axis: SIMD3<Float>
    var perpA: SIMD3<Float>
    var perpB: SIMD3<Float>
    var halfLength: Float
    var radius: Float
    /// Offset along the flow, 0...1, so the droplets are spread out.
    var phase: Float
    /// Angle around the layer.
    var angle: Float
    /// Slight variation of the distance from the axis.
    var radialJitter: Float
    /// Layer lengths travelled per second.
    var speed: Float
    var startTime: Double = 0
    /// The droplet is hidden once the clock passes this time.
    var runUntil: Double = 0
}

/// A glowing disc that sweeps back and forth along the feeding tunnels.
struct SweepDiscComponent: Component {
    var center: SIMD3<Float>
    var axis: SIMD3<Float>
    var halfLength: Float
    var duration: Double
    var passes: Int = 2
    var startTime: Double = 0
    var runUntil: Double = 0
}
