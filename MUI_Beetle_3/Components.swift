import RealityKit
import simd

/// The two-phase reveal state of a layer during the upward-drag interaction.
enum RevealPhase: Int {
    /// Layer is hidden inside the physical log, not yet interacted with.
    case hidden = 0
    /// User is actively dragging the layer upward (phase 1: rise + fade in).
    case rising = 1
    /// Layer was released past threshold; auto-animating to its final side position (phase 2).
    case autoAnimating = 2
    /// Layer has arrived at its final position. Fully visible, interactive.
    case revealed = 3
}

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

    // --- Reveal (vertical drag) ---
    var revealPhase: RevealPhase = .hidden
    /// The Y offset from restPosition during the user-driven rise.
    var riseOffsetY: Float = 0
    /// Final position for the side-by-side layout above the log.
    var revealedPosition: SIMD3<Float> = .zero

    // Fade. Starts at 0; layers are invisible until revealed.
    var currentOpacity: Float = 0
    var targetOpacity: Float = 0
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

/// One bore hole on the bark surface. Scales in at a staggered time within the cycle.
struct BoreHoleComponent: Component {
    var holeIndex: Int
    var localPosition: SIMD3<Float>
    var startTime: Double = 0
    var runUntil: Double = 0
}

/// A falling sawdust particle or a heap at the base of the bark.
struct SawdustComponent: Component {
    var holeIndex: Int
    var originPosition: SIMD3<Float>
    var floorY: Float
    var lateralOffset: SIMD3<Float>
    var phase: Float
    var isHeap: Bool = false
    var startTime: Double = 0
    var runUntil: Double = 0
}

/// A dot tracing a tunnel path (mother beetle on the main tunnel, or a larva on a side arm).
struct TunnelDotComponent: Component {
    var pathStart: SIMD3<Float>
    var pathEnd: SIMD3<Float>
    var startDelay: Float           // seconds into the cycle before this dot begins
    var travelDuration: Float       // seconds to travel the path
    var isMother: Bool = false
    var startTime: Double = 0
    var runUntil: Double = 0
}

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
