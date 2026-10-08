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
            var scaleFactor = state.currentScale
            var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            if let start = state.effectStart {
                let p = Float((now - start) / max(state.effectDuration, 0.01))
                if p >= 1 {
                    state.effectStart = nil
                } else {
                    switch state.layer.effect {
                    case .pulse:
                        scaleFactor *= 1 + 0.045 * sin(p * 4 * .pi) * (1 - p)
                    case .turn:
                        rotation = simd_quatf(angle: Self.easeInOut(p) * 2 * .pi, axis: state.longAxis)
                    case .enlarge, .sweep, .nutrientFlow:
                        break
                    }
                }
            }

            // Scale and turn around the centre of the layer, not around its origin.
            let center = state.panelCenter
            let movedCenter = rotation.act(center * scaleFactor)
            entity.position = state.basePosition + center - movedCenter
            entity.orientation = rotation * state.baseOrientation
            entity.scale = state.baseScale * scaleFactor

            // Info panel follows the layer, lifting when the model scales up
            if let id = state.panelID, let panel = context.scene.findEntity(id: id) {
                let layerCenter = state.basePosition + center
                let scaleOffset: Float = scaleFactor > 1.01 ? 0.2 : 0
                panel.position = [layerCenter.x, state.panelBaseY + scaleOffset, layerCenter.z]
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
    }
}
