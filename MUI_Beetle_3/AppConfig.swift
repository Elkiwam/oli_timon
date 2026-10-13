import Foundation
import simd

/// Every value you are likely to tweak lives here.
enum AppConfig {

    // MARK: Scene identifiers
    static let welcomeWindowID = "WelcomeWindow"
    static let immersiveSpaceID = "LogSpace"

    // MARK: Reality Composer Pro
    /// Name of the scene (.usda) inside the RealityKitContent package that contains the five models.
    /// PLACEHOLDER: replace with your scene's name.
    static let sceneName = "Scene"

    // MARK: Placement (meters)
    // The immersive-space origin is on the floor below the user at launch.
    static let logPosition: SIMD3<Float> = [0, 1.2, -1.1]
    /// Control panel position relative to `logPosition`: below the log and closer to the user.
    static let controlPanelOffset: SIMD3<Float> = [0.1, -0.45, 0.15]
    /// Distance from the top of the log to the centre of an info panel.
    static let panelHeightAboveLog: Float = 0.22

    // MARK: Interaction17
    /// Hand movement is multiplied by this, so the bark can travel ~0.9 m with a comfortable arm movement.
    static let dragGain: Float = 1.8
    /// Released beyond this fraction of the way to its slot, a layer snaps apart; otherwise it springs back.
    static let snapThreshold: Float = 0.2
    /// Opacity of the layers that are not selected.
    static let fadedOpacity: Float = 0.25
    /// Smallest collision box edge, so tiny models (the beetle) stay easy to pinch.
    static let minimumColliderSize: Float = 0.1

    // MARK: Bore hole effect on the bark
    static let boreHoleCount = 3
    static let boreHoleRadius: Float = 0.004
    static let dustPerHole = 6
    static let dustRadius: Float = 0.003
    static let dustFallSpeed: Float = 0.06
    static let heapRadius: Float = 0.012
    static let boreHoleCycleDuration: Double = 7.0
    static let holeAppearTime: Float = 0.4
    static let holeStagger: Float = 2.0
    static let dustStartDelay: Float = 0.3
    static let dustDuration: Float = 1.8
    static let fadeOutDuration: Float = 0.5

    // MARK: Tunnel trace animation
    static let tunnelDotRadius: Float = 0.08        // mother beetle dot size (local space)
    static let larvaDotRadius: Float = 0.06          // larva dot size
    static let motherTravelTime: Float = 3.0         // seconds for mother to travel main tunnel
    static let larvaTravelTime: Float = 2.0          // seconds per larva arm
    static let larvaStartOffset: Float = 0.2         // delay after mother passes branch point
    static let tunnelCycleDuration: Float = 10.0     // total loop duration
    static let tunnelFadeOut: Float = 0.5            // fade at cycle end

    // MARK: Nutrient flow in the cambium
    static let particlesPerFlow = 20
    static let particleRadius: Float = 0.007      // world meters
    static let nutrientRadiusFactor: Float = 1.03 // >1 keeps the droplets just outside the surface so they stay visible
    static let nutrientSpeed: Float = 0.22        // fraction of the layer length per second
}
