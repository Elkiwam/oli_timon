import Foundation
import QuartzCore
import RealityKit
import simd

// MARK: - Layer motion

/// Every frame: eases layers to their targets, fades them, scales and turns them,
/// and keeps each info panel floating above its layer.
@MainActor
struct LayerMotionSystem: System {

    private static let query = EntityQuery(where: .has(LayerComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(min(context.deltaTime, 1.0 / 20.0))
        let now = CACurrentMediaTime()

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var state = entity.components[LayerComponent.self] else { continue }

            // Position: follow the hand while dragging, otherwise ease toward the target slot.
            if !state.isDragging {
                let k = 1 - exp(-20 * dt)
                state.basePosition += (state.targetPosition - state.basePosition) * k
                if simd_distance(state.basePosition, state.targetPosition) < 0.0005 {
                    state.basePosition = state.targetPosition
                }
            }

            // Opacity
            let ko = 1 - exp(-8 * dt)
            state.currentOpacity += (state.targetOpacity - state.currentOpacity) * ko
            if abs(state.targetOpacity - state.currentOpacity) < 0.002 {
                state.currentOpacity = state.targetOpacity
            }
            if abs(state.currentOpacity - state.appliedOpacity) > 0.001 {
                entity.components.set(OpacityComponent(opacity: state.currentOpacity))
                state.appliedOpacity = state.currentOpacity
            }

            // Persistent scale
            let ks = 1 - exp(-7 * dt)
            state.currentScale += (state.targetScale - state.currentScale) * ks
            if abs(state.targetScale - state.currentScale) < 0.001 {
                state.currentScale = state.targetScale
            }

            // Transient effects
            let scaleFactor = state.currentScale
            var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

            // Continuous spin while enlarged/selected
            if scaleFactor > 1.01 {
                switch state.layer.effect {
                case .enlarge:
                    let angle = Float(now) * 0.5   // ~one turn every 12.6 s
                    rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
                case .turn:
                    let angle = Float(now) * 0.5
                    rotation = simd_quatf(angle: angle, axis: state.longAxis)
                default:
                    break
                }
            }

            // Scale and turn around the centre of the layer, not around its origin.
            let center = state.panelCenter
            let movedCenter = rotation.act(center * scaleFactor)
            entity.position = state.basePosition + center - movedCenter
            entity.orientation = rotation * state.baseOrientation
            entity.scale = state.baseScale * scaleFactor

            // Info panel: smooth opacity fade and vertical slide
            let kp = 1 - exp(-8 * dt)
            state.panelCurrentOpacity += (state.panelTargetOpacity - state.panelCurrentOpacity) * kp
            if abs(state.panelTargetOpacity - state.panelCurrentOpacity) < 0.002 {
                state.panelCurrentOpacity = state.panelTargetOpacity
            }

            let layerCenter = state.basePosition + center
            if let id = state.panelID, let panel = context.scene.findEntity(id: id) {
                let visible = state.panelCurrentOpacity > 0.01
                panel.isEnabled = visible
                if visible {
                    panel.components.set(OpacityComponent(opacity: state.panelCurrentOpacity))
                    let scaleOffset = min(0.2, max(0, scaleFactor - 1) * 2.0)
                    // Slide up as it fades in; slide down as it fades out.
                    let slideOffset = (1 - state.panelCurrentOpacity) * -0.08
                    let targetPos = SIMD3<Float>(layerCenter.x, state.panelBaseY + scaleOffset + slideOffset, layerCenter.z)
                    // Animate toward the target; called each frame so the panel
                    // smoothly lifts on selection and lowers on deselection.
                    panel.move(
                        to: Transform(scale: .one, rotation: panel.orientation, translation: targetPos),
                        relativeTo: panel.parent,
                        duration: 0.1,
                        timingFunction: .easeOut
                    )
                }
            }

            // Description panel: only set initial position, don't override user repositioning
            if let id = state.descriptionPanelID, let descPanel = context.scene.findEntity(id: id),
               !descPanel.isEnabled {
                let bounds = entity.visualBounds(relativeTo: entity.parent)
                descPanel.position = [layerCenter.x, bounds.min.y - 0.45, layerCenter.z]
            }

            entity.components.set(state)
        }
    }

    private static func easeInOut(_ t: Float) -> Float {
        t * t * (3 - 2 * t)
    }
}

// MARK: - Procedural effects

/// Drives the sugar droplets in the cambium and the light sweep along the feeding tunnels.
@MainActor
struct ProceduralEffectSystem: System {

    private static let particleQuery = EntityQuery(where: .has(NutrientParticleComponent.self))
    private static let sweepQuery = EntityQuery(where: .has(SweepDiscComponent.self))
    private static let boreHoleQuery = EntityQuery(where: .has(BoreHoleComponent.self))
    private static let sawdustQuery = EntityQuery(where: .has(SawdustComponent.self))
    private static let tunnelDotQuery = EntityQuery(where: .has(TunnelDotComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let now = CACurrentMediaTime()

        for entity in context.entities(matching: Self.particleQuery, updatingSystemWhen: .rendering) {
            guard let p = entity.components[NutrientParticleComponent.self] else { continue }
            if now >= p.runUntil {
                entity.isEnabled = false
                continue
            }
            let raw = p.phase + Float(now - p.startTime) * p.speed
            let t = raw - floor(raw)                       // 0...1 along the layer
            let along = (t - 0.5) * 2 * p.halfLength
            let distance = p.radius * AppConfig.nutrientRadiusFactor * p.radialJitter
            let offset = (cos(p.angle) * p.perpA + sin(p.angle) * p.perpB) * distance
            entity.position = p.center + p.axis * along + offset

            // Droplets shrink in and out at the ends of the layer.
            let edge = max(min(1, min(t, 1 - t) * 8), 0.001)
            entity.scale = SIMD3<Float>(repeating: edge)
        }

        for entity in context.entities(matching: Self.sweepQuery, updatingSystemWhen: .rendering) {
            guard let d = entity.components[SweepDiscComponent.self] else { continue }
            if now >= d.runUntil {
                entity.isEnabled = false
                continue
            }
            let progress = Float((now - d.startTime) / max(d.duration, 0.01))
            let raw = progress * Float(d.passes)
            let t = raw - floor(raw)
            let along = (t - 0.5) * 2 * d.halfLength
            entity.position = d.center + d.axis * along

            let edge = max(min(1, min(t, 1 - t) * 6), 0.001)
            entity.scale = SIMD3<Float>(repeating: edge)
        }

        // MARK: Bore holes
        let cycle = Float(AppConfig.boreHoleCycleDuration)
        let stagger = AppConfig.holeStagger
        let appear = AppConfig.holeAppearTime
        let fadeOut = AppConfig.fadeOutDuration

        for entity in context.entities(matching: Self.boreHoleQuery, updatingSystemWhen: .rendering) {
            guard let h = entity.components[BoreHoleComponent.self] else { continue }
            if now >= h.runUntil {
                entity.scale = SIMD3<Float>(repeating: 0.001)
                entity.isEnabled = false
                continue
            }
            entity.isEnabled = true
            let elapsed = Float(fmod(now - h.startTime, Double(cycle)))
            let onset = Float(h.holeIndex) * stagger

            // Fade-out phase at end of cycle
            let fadeStart = cycle - fadeOut
            if elapsed >= fadeStart {
                let f = 1 - (elapsed - fadeStart) / fadeOut
                entity.scale = SIMD3<Float>(repeating: max(f, 0.001))
            } else if elapsed < onset {
                entity.scale = SIMD3<Float>(repeating: 0.001)
            } else if elapsed < onset + appear {
                let f = (elapsed - onset) / appear
                entity.scale = SIMD3<Float>(repeating: max(f, 0.001))
            } else {
                entity.scale = SIMD3<Float>(repeating: 1)
            }
        }

        // MARK: Sawdust particles and heaps
        let dustDelay = AppConfig.dustStartDelay
        let dustDur = AppConfig.dustDuration
        let fallSpeed = AppConfig.dustFallSpeed

        for entity in context.entities(matching: Self.sawdustQuery, updatingSystemWhen: .rendering) {
            guard let s = entity.components[SawdustComponent.self] else { continue }
            if now >= s.runUntil {
                entity.scale = SIMD3<Float>(repeating: 0.001)
                entity.isEnabled = false
                continue
            }
            entity.isEnabled = true
            let elapsed = Float(fmod(now - s.startTime, Double(cycle)))
            let dustStart = Float(s.holeIndex) * stagger + dustDelay
            let dustEnd = dustStart + dustDur
            let fadeStart = cycle - fadeOut

            if s.isHeap {
                // Heap grows during dust window, fades at cycle end
                if elapsed >= fadeStart {
                    let f = 1 - (elapsed - fadeStart) / fadeOut
                    entity.scale = SIMD3<Float>(max(f, 0.001), max(f * 0.3, 0.001), max(f, 0.001))
                } else if elapsed >= dustStart && elapsed < dustEnd {
                    let f = (elapsed - dustStart) / dustDur
                    entity.scale = SIMD3<Float>(f, f * 0.3, f)
                } else if elapsed >= dustEnd && elapsed < fadeStart {
                    entity.scale = SIMD3<Float>(1, 0.3, 1)
                } else {
                    entity.scale = SIMD3<Float>(repeating: 0.001)
                }
            } else {
                // Falling dust particle
                let particleDur = dustDur / Float(AppConfig.dustPerHole)
                let particleStart = dustStart + s.phase * (dustDur - particleDur)
                let particleEnd = particleStart + particleDur

                if elapsed >= fadeStart {
                    entity.scale = SIMD3<Float>(repeating: 0.001)
                } else if elapsed >= particleStart && elapsed < particleEnd {
                    let t = (elapsed - particleStart) / particleDur
                    let fallDist = t * fallSpeed
                    entity.position = s.originPosition + SIMD3<Float>(0, -fallDist, 0) + s.lateralOffset * t
                    // Clamp at floor
                    if entity.position.y < s.floorY {
                        entity.position.y = s.floorY
                    }
                    // Quick scale in, fade near end
                    let scaleIn = min(t * 5, 1.0)
                    let scaleOut = max(1 - (t - 0.7) / 0.3, 0.0)
                    entity.scale = SIMD3<Float>(repeating: max(min(scaleIn, scaleOut), 0.001))
                } else {
                    entity.scale = SIMD3<Float>(repeating: 0.001)
                }
            }
        }

        // MARK: Tunnel dots (mother beetle + larvae)
        let tCycle = AppConfig.tunnelCycleDuration
        let tFade = AppConfig.tunnelFadeOut

        for entity in context.entities(matching: Self.tunnelDotQuery, updatingSystemWhen: .rendering) {
            guard let d = entity.components[TunnelDotComponent.self] else { continue }
            if now >= d.runUntil {
                entity.scale = SIMD3<Float>(repeating: 0.001)
                entity.isEnabled = false
                continue
            }
            entity.isEnabled = true
            let elapsed = Float(fmod(now - d.startTime, Double(tCycle)))
            let travelEnd = d.startDelay + d.travelDuration
            let fadeStart = tCycle - tFade

            if elapsed < d.startDelay {
                // Not started yet in this cycle
                entity.scale = SIMD3<Float>(repeating: 0.001)
            } else if elapsed < travelEnd {
                // Traveling along the path
                let t = (elapsed - d.startDelay) / d.travelDuration
                entity.position = d.pathStart + (d.pathEnd - d.pathStart) * t
                // Quick scale-in at start
                let s = min(t * 6, 1.0)
                entity.scale = SIMD3<Float>(repeating: max(s, 0.001))
            } else if elapsed < fadeStart {
                // Arrived at end, hold position
                entity.position = d.pathEnd
                entity.scale = SIMD3<Float>(repeating: 1)
            } else {
                // Fade out at cycle end
                let f = 1 - (elapsed - fadeStart) / tFade
                entity.scale = SIMD3<Float>(repeating: max(f, 0.001))
            }
        }
    }
}
