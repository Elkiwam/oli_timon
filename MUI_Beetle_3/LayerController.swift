import QuartzCore
import RealityKit
import RealityKitContent
import Spatial
import SwiftUI
import UIKit
import simd

/// Builds the log from the Reality Composer Pro scene and handles drag, tap and recombine.
/// Per-frame animation lives in `LayerMotionSystem` and `ProceduralEffectSystem`;
/// the controller only changes targets and starts effects.
@MainActor
final class LayerController {

    private let appModel: AppModel
    private var layerEntities: [Layer: Entity] = [:]
    private var panels: [Layer: Entity] = [:]
    private var activeDrag: ActiveDrag?

    private static let flowName = "NutrientFlow"
    private static let sweepName = "SweepDisc"

    private struct ActiveDrag {
        let layer: Layer
        let pointerStartX: Float
        let layerStartX: Float
    }

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    // MARK: - Scene construction

    /// Loads the five models, makes them interactive and returns the root entity to add to the view.
    func buildScene(onExit: @escaping @MainActor () -> Void) async -> Entity {
        appModel.resetInteractionState()
        layerEntities.removeAll()
        panels.removeAll()
        activeDrag = nil

        let root = Entity()
        root.name = "LogRoot"
        root.position = AppConfig.logPosition

        do {
            let scene = try await Entity(named: AppConfig.sceneName, in: realityKitContentBundle)
            root.addChild(scene)
            for layer in Layer.allCases {
                guard let entity = scene.findEntity(named: layer.entityName) else {
                    print("Entity '\(layer.entityName)' not found in scene '\(AppConfig.sceneName)'")
                    continue
                }
                root.addChild(entity, preservingWorldTransform: true)
                layerEntities[layer] = entity
            }
            scene.removeFromParent()
        } catch {
            print("Could not load scene '\(AppConfig.sceneName)': \(error)")
        }

        // Info panels float above the highest point of the log.
        let logTop = layerEntities.values
            .map { $0.visualBounds(relativeTo: root).max.y }
            .max() ?? 0
        let panelBaseY = logTop + AppConfig.panelHeightAboveLog

        for (layer, entity) in layerEntities {
            configure(layer, entity: entity, root: root, panelBaseY: panelBaseY)
        }

        root.addChild(makeBackdrop())
        root.addChild(makeControlPanel(onExit: onExit))
        return root
    }

    private func configure(_ layer: Layer, entity: Entity, root: Entity, panelBaseY: Float) {
        let rootBounds = entity.visualBounds(relativeTo: root)
        let localBounds = entity.visualBounds(relativeTo: entity)
        let axisIndex = Self.longestAxis(of: localBounds.extents)

        var state = LayerComponent(
            layer: layer,
            restPosition: entity.position,
            explodedPosition: entity.position + SIMD3<Float>(layer.explodedOffsetX, 0, 0),
            basePosition: entity.position,
            targetPosition: entity.position,
            baseScale: entity.scale,
            baseOrientation: entity.orientation,
            longAxis: entity.orientation.act(Self.basis(axisIndex)),
            panelCenter: rootBounds.center - entity.position,
            panelBaseY: panelBaseY
        )

        // Info panel (SwiftUI attachment), hidden until the layer is dragged or tapped.
        let panel = Entity()
        panel.name = "InfoPanel_\(layer.title)"
        panel.components.set(ViewAttachmentComponent(rootView: LayerInfoView(layer: layer, appModel: appModel)))
        panel.components.set(BillboardComponent())
        panel.position = [rootBounds.center.x, panelBaseY, rootBounds.center.z]
        panel.isEnabled = false
        root.addChild(panel)
        panels[layer] = panel
        state.panelID = panel.id

        makeInteractive(entity, localBounds: localBounds)

        switch layer.effect {
        case .nutrientFlow:
            addNutrientFlow(to: entity, bounds: localBounds, axisIndex: axisIndex)
        case .sweep:
            addSweepDisc(to: entity, bounds: localBounds, axisIndex: axisIndex)
        case .pulse, .enlarge, .turn:
            break
        }

        entity.components.set(state)
    }

    /// Collision box, input target and hover glow. The box is deliberately simple, so a layer is easy to pinch.
    private func makeInteractive(_ entity: Entity, localBounds: BoundingBox) {
        let worldScale = max(entity.scale(relativeTo: nil).x, 0.0001)
        let minimum = AppConfig.minimumColliderSize / worldScale
        let size = SIMD3<Float>(
            max(localBounds.extents.x, minimum),
            max(localBounds.extents.y, minimum),
            max(localBounds.extents.z, minimum)
        )
        let shape = ShapeResource.generateBox(size: size).offsetBy(translation: localBounds.center)
        entity.components.set(CollisionComponent(shapes: [shape]))
        entity.components.set(InputTargetComponent())
        entity.components.set(HoverEffectComponent(.highlight(.init(color: UIColor(red: 0.72, green: 0.52, blue: 0.32, alpha: 1), strength: 0.6))))
    }

    /// An invisible wall behind the log. A tap on empty space lands on it and clears the selection.
    private func makeBackdrop() -> Entity {
        let backdrop = Entity()
        backdrop.name = "Backdrop"
        backdrop.position = [0, 0.4, -3.0]
        backdrop.components.set(CollisionComponent(shapes: [.generateBox(size: [14, 7, 0.1])]))
        backdrop.components.set(InputTargetComponent())
        return backdrop
    }

    private func makeControlPanel(onExit: @escaping @MainActor () -> Void) -> Entity {
        let panel = Entity()
        panel.name = "ControlPanel"
        panel.components.set(ViewAttachmentComponent(rootView: ControlPanelView(
            appModel: appModel,
            onRecombine: { [weak self] in self?.recombine() },
            onExit: onExit
        )))
        panel.components.set(BillboardComponent())
        panel.position = AppConfig.controlPanelOffset
        return panel
    }

    // MARK: - Dragging

    func handleDragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        let point = value.convert(value.location3D, from: .local, to: .scene)
        let x = Float(point.x)

        guard let drag = activeDrag else {
            beginDrag(on: value.entity, pointerX: x)
            return
        }
        guard let entity = layerEntities[drag.layer],
              var state = entity.components[LayerComponent.self] else { return }

        let delta = (x - drag.pointerStartX) * AppConfig.dragGain
        let lower = min(state.restPosition.x, state.explodedPosition.x) - 0.05
        let upper = max(state.restPosition.x, state.explodedPosition.x) + 0.05
        state.basePosition.x = min(max(drag.layerStartX + delta, lower), upper)
        entity.components.set(state)
    }

    func handleDragEnded() {
        guard let drag = activeDrag else { return }
        activeDrag = nil
        appModel.draggingLayer = nil

        if let entity = layerEntities[drag.layer],
           var state = entity.components[LayerComponent.self] {
            let span = state.explodedPosition.x - state.restPosition.x
            let progress = span == 0 ? 0 : (state.basePosition.x - state.restPosition.x) / span
            state.isDragging = false
            state.isSeparated = progress >= AppConfig.snapThreshold
            state.targetPosition = state.isSeparated ? state.explodedPosition : state.restPosition
            entity.components.set(state)

            if state.isSeparated {
                appModel.separatedLayers.insert(drag.layer)
            } else {
                appModel.separatedLayers.remove(drag.layer)
            }
        }
        refreshPanels()
    }

    private func beginDrag(on entity: Entity, pointerX: Float) {
        guard let (layer, layerEntity) = layerOwner(of: entity),
              var state = layerEntity.components[LayerComponent.self] else { return }
        state.isDragging = true
        layerEntity.components.set(state)

        activeDrag = ActiveDrag(layer: layer, pointerStartX: pointerX, layerStartX: state.basePosition.x)
        appModel.draggingLayer = layer
        refreshPanels()
    }

    // MARK: - Selection and effects

    func handleTap(on entity: Entity) {
        if let (layer, _) = layerOwner(of: entity) {
            select(appModel.selectedLayer == layer ? nil : layer)
        } else {
            select(nil)
        }
    }

    /// Selects a layer, fades the others and starts the tap effect. Pass nil to clear.
    private func select(_ layer: Layer?) {
        appModel.selectedLayer = layer

        for (candidate, entity) in layerEntities {
            guard var state = entity.components[LayerComponent.self] else { continue }
            let isSelected = candidate == layer
            state.targetOpacity = (layer == nil || isSelected) ? 1 : AppConfig.fadedOpacity
            state.targetScale = isSelected ? candidate.selectedScale : 1
            entity.components.set(state)
        }

        if let layer, let entity = layerEntities[layer] {
            startEffect(for: layer, on: entity)
        }
        refreshPanels()
    }

    private func startEffect(for layer: Layer, on entity: Entity) {
        let now = CACurrentMediaTime()

        switch layer.effect {
        case .pulse, .turn:
            guard var state = entity.components[LayerComponent.self] else { return }
            state.effectStart = now
            state.effectDuration = layer.effectDuration
            entity.components.set(state)

        case .enlarge:
            break // handled by `targetScale` in select(_:)

        case .sweep:
            guard let disc = entity.findEntity(named: Self.sweepName),
                  var sweep = disc.components[SweepDiscComponent.self] else { return }
            sweep.startTime = now
            sweep.duration = layer.effectDuration
            sweep.runUntil = now + layer.effectDuration
            disc.components.set(sweep)
            disc.isEnabled = true

        case .nutrientFlow:
            guard let flow = entity.findEntity(named: Self.flowName) else { return }
            for droplet in flow.children {
                guard var particle = droplet.components[NutrientParticleComponent.self] else { continue }
                particle.startTime = now
                particle.runUntil = now + layer.effectDuration
                droplet.components.set(particle)
                droplet.isEnabled = true
            }
        }
    }

    // MARK: - Recombine

    /// Clears the selection and sends every layer back to its place in the log.
    func recombine() {
        activeDrag = nil
        appModel.draggingLayer = nil
        select(nil)

        for entity in layerEntities.values {
            guard var state = entity.components[LayerComponent.self] else { continue }
            state.isDragging = false
            state.isSeparated = false
            state.targetPosition = state.restPosition
            entity.components.set(state)
        }
        appModel.separatedLayers.removeAll()
        refreshPanels()
    }

    // MARK: - Helpers

    private func refreshPanels() {
        for (layer, panel) in panels {
            let isSeparated = appModel.separatedLayers.contains(layer)
            let isRevealed = layer == .innerLog && appModel.hasSeparatedLayers
            panel.isEnabled = appModel.selectedLayer == layer || appModel.draggingLayer == layer || isSeparated || isRevealed
        }
    }

    /// Walks up from a hit entity to the layer it belongs to.
    private func layerOwner(of entity: Entity) -> (Layer, Entity)? {
        var current: Entity? = entity
        while let candidate = current {
            if let component = candidate.components[LayerComponent.self] {
                return (component.layer, candidate)
            }
            current = candidate.parent
        }
        return nil
    }

    private static func longestAxis(of extents: SIMD3<Float>) -> Int {
        if extents.x >= extents.y && extents.x >= extents.z { return 0 }
        return extents.y >= extents.z ? 1 : 2
    }

    private static func basis(_ index: Int) -> SIMD3<Float> {
        var vector = SIMD3<Float>.zero
        vector[index] = 1
        return vector
    }

    /// The two axes perpendicular to `axisIndex`.
    private static func perpendicularIndices(to axisIndex: Int) -> (Int, Int) {
        switch axisIndex {
        case 0:  return (1, 2)
        case 1:  return (0, 2)
        default: return (0, 1)
        }
    }

    // MARK: - Procedural effect geometry

    private func addNutrientFlow(to entity: Entity, bounds: BoundingBox, axisIndex: Int) {
        var axis = Self.basis(axisIndex)
        // If the log stands upright, let the sugar run downward toward the roots.
        if entity.orientation.act(axis).y > 0.5 { axis = -axis }

        let (a, b) = Self.perpendicularIndices(to: axisIndex)
        let halfLength = bounds.extents[axisIndex] / 2
        let radius = max(bounds.extents[a], bounds.extents[b]) / 2
        let worldScale = max(entity.scale(relativeTo: nil).x, 0.0001)

        let mesh = MeshResource.generateSphere(radius: AppConfig.particleRadius / worldScale)
        let material = UnlitMaterial(color: UIColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1))

        let flow = Entity()
        flow.name = Self.flowName
        let count = AppConfig.particlesPerFlow
        for i in 0..<count {
            let droplet = ModelEntity(mesh: mesh, materials: [material])
            droplet.components.set(NutrientParticleComponent(
                center: bounds.center,
                axis: axis,
                perpA: Self.basis(a),
                perpB: Self.basis(b),
                halfLength: halfLength,
                radius: radius,
                phase: Float(i) / Float(count),
                angle: Float(i) * 2.39996,                     // golden angle spreads droplets around the layer
                radialJitter: 0.98 + 0.02 * Float(i % 3) / 2,
                speed: AppConfig.nutrientSpeed
            ))
            droplet.scale = SIMD3<Float>(repeating: 0.001)
            droplet.isEnabled = false
            flow.addChild(droplet)
        }
        entity.addChild(flow)
    }

    private func addSweepDisc(to entity: Entity, bounds: BoundingBox, axisIndex: Int) {
        let axis = Self.basis(axisIndex)
        let (a, b) = Self.perpendicularIndices(to: axisIndex)
        let halfLength = bounds.extents[axisIndex] / 2
        let radius = max(bounds.extents[a], bounds.extents[b]) / 2
        let worldScale = max(entity.scale(relativeTo: nil).x, 0.0001)

        var material = UnlitMaterial(color: UIColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1))
        material.blending = .transparent(opacity: 0.55)

        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.004 / worldScale, radius: radius * 1.1),
            materials: [material]
        )
        disc.name = Self.sweepName
        disc.orientation = simd_quatf(from: [0, 1, 0], to: axis)
        disc.position = bounds.center
        disc.scale = SIMD3<Float>(repeating: 0.001)
        disc.components.set(SweepDiscComponent(
            center: bounds.center,
            axis: axis,
            halfLength: halfLength,
            duration: Layer.feedingTunnel.effectDuration
        ))
        disc.isEnabled = false
        entity.addChild(disc)
    }
}
