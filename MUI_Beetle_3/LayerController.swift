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
    private var descriptionPanels: [Layer: Entity] = [:]
    private var activeDrag: ActiveDrag?

    private static let flowName = "NutrientFlow"
    private static let sweepName = "SweepDisc"

    private struct ActiveDrag {
        let layer: Layer
        let pointerStartX: Float
        let layerStartX: Float
    }

    private struct ActivePanelDrag {
        let entity: Entity
        let startPosition: SIMD3<Float>
        let pointerStart: SIMD3<Float>
    }
    private var activePanelDrag: ActivePanelDrag?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    // MARK: - Scene construction

    /// Loads the five models, makes them interactive and returns the root entity to add to the view.
    func buildScene(onExit: @escaping @MainActor () -> Void) async -> Entity {
        appModel.resetInteractionState()
        layerEntities.removeAll()
        panels.removeAll()
        descriptionPanels.removeAll()
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

        // Description panel below the model, visible only when selected.
        let descPanel = Entity()
        descPanel.name = "DescPanel_\(layer.title)"
        descPanel.components.set(ViewAttachmentComponent(rootView: LayerDescriptionView(layer: layer)))
        descPanel.components.set(BillboardComponent())
        descPanel.components.set(DescriptionPanelTag())
        descPanel.components.set(CollisionComponent(shapes: [.generateBox(size: [0.5, 0.2, 0.05])]))
        descPanel.components.set(InputTargetComponent())
        let logBottom = rootBounds.min.y
        descPanel.position = [rootBounds.center.x, logBottom - 0.45, rootBounds.center.z]
        descPanel.isEnabled = false
        root.addChild(descPanel)
        descriptionPanels[layer] = descPanel
        state.descriptionPanelID = descPanel.id

        makeInteractive(entity, localBounds: localBounds, isDraggable: layer == appModel.nextDraggableLayer)

        switch layer.effect {
        case .boreHole:
            addBoreHoleEffect(to: entity, bounds: localBounds, axisIndex: axisIndex)
        case .nutrientFlow:
            addNutrientFlow(to: entity, bounds: localBounds, axisIndex: axisIndex)
        case .sweep:
            addTunnelAnimation(to: entity, bounds: localBounds)
        case .enlarge, .turn:
            break
        }

        entity.components.set(state)
    }

    /// Collision box, input target and hover glow. The box is deliberately simple, so a layer is easy to pinch.
    private func makeInteractive(_ entity: Entity, localBounds: BoundingBox, isDraggable: Bool) {
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
        if isDraggable {
            entity.components.set(HoverEffectComponent(.highlight(.init(color: UIColor(red: 0.72, green: 0.52, blue: 0.32, alpha: 1), strength: 0.6))))
        }
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

        // Drag bar: a child entity with its own view attachment.
        // Only this entity has collision, so the panel's SwiftUI buttons stay clickable.
        let dragBar = Entity()
        dragBar.name = "ControlPanelDragBar"
        dragBar.components.set(ViewAttachmentComponent(rootView: DragBarView(appModel: appModel)))
        dragBar.components.set(BillboardComponent())
        dragBar.components.set(ControlPanelTag())
        dragBar.components.set(CollisionComponent(shapes: [.generateBox(size: [0.15, 0.03, 0.05])]))
        dragBar.components.set(InputTargetComponent())
        dragBar.position = [0, -0.065, 0]
        panel.addChild(dragBar)

        return panel
    }

    // MARK: - Dragging

    func handleDragChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        let point = value.convert(value.location3D, from: .local, to: .scene)

        // Check if dragging a description panel
        if let panelDrag = activePanelDrag {
            let delta = SIMD3<Float>(Float(point.x), Float(point.y), Float(point.z)) - panelDrag.pointerStart
            panelDrag.entity.position = panelDrag.startPosition + delta
            return
        }

        // Start a new panel drag if the entity is a description panel or control panel drag bar
        var target = value.entity
        while target.parent != nil {
            if target.components[DescriptionPanelTag.self] != nil {
                activePanelDrag = ActivePanelDrag(
                    entity: target,
                    startPosition: target.position,
                    pointerStart: SIMD3<Float>(Float(point.x), Float(point.y), Float(point.z))
                )
                return
            }
            if target.components[ControlPanelTag.self] != nil {
                // Move the parent panel, not the drag bar child.
                let panel = target.parent ?? target
                activePanelDrag = ActivePanelDrag(
                    entity: panel,
                    startPosition: panel.position,
                    pointerStart: SIMD3<Float>(Float(point.x), Float(point.y), Float(point.z))
                )
                appModel.isDraggingControlPanel = true
                return
            }
            target = target.parent!
        }

        // Otherwise handle layer drag
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
        if activePanelDrag != nil {
            activePanelDrag = nil
            appModel.isDraggingControlPanel = false
            return
        }
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

        // Enforce the forced drag sequence: only the next layer in order can be dragged.
        guard layer == appModel.nextDraggableLayer else { return }

        // Reveal inner wood title on first touch (drag or tap).
        if layer == .innerLog && !appModel.innerLogRevealed {
            appModel.innerLogRevealed = true
        }

        state.isDragging = true
        layerEntity.components.set(state)

        activeDrag = ActiveDrag(layer: layer, pointerStartX: pointerX, layerStartX: state.basePosition.x)
        appModel.draggingLayer = layer
        refreshPanels()
    }

    // MARK: - Selection and effects

    func handleTap(on entity: Entity) {
        // Ignore taps on description panels and the control panel drag bar
        var current: Entity? = entity
        while let candidate = current {
            if candidate.components[DescriptionPanelTag.self] != nil
                || candidate.components[ControlPanelTag.self] != nil { return }
            current = candidate.parent
        }

        if let (layer, _) = layerOwner(of: entity) {
            select(appModel.selectedLayer == layer ? nil : layer)
        } else {
            select(nil)
        }
    }

    /// Selects a layer, fades the others and starts the tap effect. Pass nil to clear.
    private func select(_ layer: Layer?) {
        // Inner log first tap: reveal the title but skip animation and description.
        let isInnerLogFirstTap = layer == .innerLog && !appModel.innerLogRevealed

        appModel.selectedLayer = layer

        for (candidate, entity) in layerEntities {
            guard var state = entity.components[LayerComponent.self] else { continue }
            let isSelected = candidate == layer
            state.targetOpacity = (layer == nil || isSelected) ? 1 : AppConfig.fadedOpacity
            state.targetScale = isSelected && !isInnerLogFirstTap ? candidate.selectedScale : 1
            entity.components.set(state)
        }

        // Stop looping effects when their layer is deselected.
        if let barkEntity = layerEntities[.bark], layer != .bark {
            stopBoreHoleEffect(on: barkEntity)
        }
        if let tunnelEntity = layerEntities[.feedingTunnel], layer != .feedingTunnel {
            stopTunnelAnimation(on: tunnelEntity)
        }

        if let layer, let entity = layerEntities[layer], !isInnerLogFirstTap {
            startEffect(for: layer, on: entity)
        }

        // refreshPanels reads innerLogRevealed, so set it AFTER so the
        // description stays hidden during the first-tap selection.
        refreshPanels()

        if isInnerLogFirstTap {
            appModel.innerLogRevealed = true
        }
    }

    private func startEffect(for layer: Layer, on entity: Entity) {
        let now = CACurrentMediaTime()

        switch layer.effect {
        case .boreHole:
            guard let container = entity.findEntity(named: Self.boreHoleName) else { return }
            let farFuture = now + 3600    // loops until explicitly stopped
            for child in container.children {
                if var h = child.components[BoreHoleComponent.self] {
                    h.startTime = now
                    h.runUntil = farFuture
                    child.components.set(h)
                    child.isEnabled = true
                }
                if var s = child.components[SawdustComponent.self] {
                    s.startTime = now
                    s.runUntil = farFuture
                    child.components.set(s)
                    child.isEnabled = true
                }
            }

        case .turn:
            guard var state = entity.components[LayerComponent.self] else { return }
            state.effectStart = now
            state.effectDuration = layer.effectDuration
            entity.components.set(state)

        case .enlarge:
            break // handled by `targetScale` in select(_:)

        case .sweep:
            guard let container = entity.findEntity(named: Self.tunnelAnimName) else { return }
            let farFuture = now + 3600
            for child in container.children {
                if var dot = child.components[TunnelDotComponent.self] {
                    dot.startTime = now
                    dot.runUntil = farFuture
                    child.components.set(dot)
                    child.isEnabled = true
                }
            }

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

    /// Immediately stops the bore hole looping effect on the bark entity.
    private func stopBoreHoleEffect(on entity: Entity) {
        guard let container = entity.findEntity(named: Self.boreHoleName) else { return }
        for child in container.children {
            if var h = child.components[BoreHoleComponent.self] {
                h.runUntil = 0
                child.components.set(h)
            }
            if var s = child.components[SawdustComponent.self] {
                s.runUntil = 0
                child.components.set(s)
            }
        }
    }

    /// Immediately stops the tunnel dot animation on the feeding tunnel entity.
    private func stopTunnelAnimation(on entity: Entity) {
        guard let container = entity.findEntity(named: Self.tunnelAnimName) else { return }
        for child in container.children {
            if var dot = child.components[TunnelDotComponent.self] {
                dot.runUntil = 0
                child.components.set(dot)
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
        appModel.innerLogRevealed = false
        refreshPanels()
    }

    // MARK: - Helpers

    private func refreshPanels() {
        let nextDraggable = appModel.nextDraggableLayer

        for (layer, _) in panels {
            let isSeparated = appModel.separatedLayers.contains(layer)
            let innerLogSticky = layer == .innerLog && appModel.innerLogRevealed
            let shouldShow = appModel.selectedLayer == layer
                || appModel.draggingLayer == layer
                || isSeparated
                || innerLogSticky

            // Drive the panel's opacity target on the layer entity; the system eases it.
            if let entity = layerEntities[layer],
               var state = entity.components[LayerComponent.self] {
                state.panelTargetOpacity = shouldShow ? 1 : 0
                entity.components.set(state)
            }
        }
        for (layer, descPanel) in descriptionPanels {
            // Inner log description is hidden until after its first tap.
            let showDesc = appModel.selectedLayer == layer
                && (layer != .innerLog || appModel.innerLogRevealed)
            descPanel.isEnabled = showDesc
        }

        // Hover highlight: during the forced sequence only the next layer glows.
        // Once all outer layers are separated, every model gets the glow.
        let allOuterSeparated = nextDraggable == .innerLog || nextDraggable == nil
        let hoverEffect = HoverEffectComponent(.highlight(.init(color: UIColor(red: 0.72, green: 0.52, blue: 0.32, alpha: 1), strength: 0.6)))
        for (layer, entity) in layerEntities {
            if allOuterSeparated || layer == nextDraggable {
                if entity.components[HoverEffectComponent.self] == nil {
                    entity.components.set(hoverEffect)
                }
            } else {
                entity.components.remove(HoverEffectComponent.self)
            }
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

    private static let boreHoleName = "BoreHoles"

    private func addBoreHoleEffect(to entity: Entity, bounds: BoundingBox, axisIndex: Int) {
        let axis = Self.basis(axisIndex)
        let (a, b) = Self.perpendicularIndices(to: axisIndex)
        let halfLength = bounds.extents[axisIndex] / 2
        let radius = max(bounds.extents[a], bounds.extents[b]) / 2
        let worldScale = max(entity.scale(relativeTo: nil).x, 0.0001)

        // Floor Y for heaps: bottom of the bark in local space.
        let floorY = bounds.min.y

        // Distribute holes along the long axis and around the surface.
        let holeAngles: [Float] = [0.3, -0.5, 0.8]            // radians around the surface
        let holeAlongs: [Float] = [-0.25, 0.15, 0.4]           // fraction of halfLength

        // Materials
        let holeMaterial = UnlitMaterial(color: UIColor(red: 0.08, green: 0.05, blue: 0.03, alpha: 1))
        let dustMaterial = UnlitMaterial(color: UIColor(red: 0.72, green: 0.58, blue: 0.36, alpha: 1))

        let holeMesh = MeshResource.generateSphere(radius: AppConfig.boreHoleRadius / worldScale)
        let dustMesh = MeshResource.generateSphere(radius: AppConfig.dustRadius / worldScale)
        let heapMesh = MeshResource.generateSphere(radius: AppConfig.heapRadius / worldScale)

        let container = Entity()
        container.name = Self.boreHoleName

        for i in 0..<AppConfig.boreHoleCount {
            let along = holeAlongs[i] * halfLength
            let angle = holeAngles[i]
            let surfaceOffset = (cos(angle) * Self.basis(a) + sin(angle) * Self.basis(b)) * radius
            let holePos = bounds.center + axis * along + surfaceOffset

            // Bore hole sphere
            let hole = ModelEntity(mesh: holeMesh, materials: [holeMaterial])
            hole.position = holePos
            hole.scale = SIMD3<Float>(repeating: 0.001)
            hole.components.set(BoreHoleComponent(holeIndex: i, localPosition: holePos))
            container.addChild(hole)

            // Dust particles
            for j in 0..<AppConfig.dustPerHole {
                let dust = ModelEntity(mesh: dustMesh, materials: [dustMaterial])
                let jitter = SIMD3<Float>(
                    Float.random(in: -0.008...0.008),
                    0,
                    Float.random(in: -0.008...0.008)
                )
                dust.position = holePos
                dust.scale = SIMD3<Float>(repeating: 0.001)
                dust.isEnabled = false
                dust.components.set(SawdustComponent(
                    holeIndex: i,
                    originPosition: holePos,
                    floorY: floorY,
                    lateralOffset: jitter,
                    phase: Float(j) / Float(AppConfig.dustPerHole)
                ))
                container.addChild(dust)
            }

            // Heap at the base below the hole
            let heap = ModelEntity(mesh: heapMesh, materials: [dustMaterial])
            heap.position = SIMD3<Float>(holePos.x, floorY, holePos.z)
            heap.scale = SIMD3<Float>(0.001, 0.001, 0.001)
            heap.isEnabled = false
            heap.components.set(SawdustComponent(
                holeIndex: i,
                originPosition: holePos,
                floorY: floorY,
                lateralOffset: .zero,
                phase: 0,
                isHeap: true
            ))
            container.addChild(heap)
        }

        entity.addChild(container)
    }

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

    private static let tunnelAnimName = "TunnelAnim"

    private func addTunnelAnimation(to entity: Entity, bounds: BoundingBox) {
        let cX = bounds.center.x
        let cZ = bounds.center.z
        let botY = bounds.min.y + bounds.extents.y * 0.05
        let topY = bounds.max.y - bounds.extents.y * 0.05

        // Mother beetle main tunnel: bottom center to top center
        let mainStart = SIMD3<Float>(cX, botY, cZ)
        let mainEnd   = SIMD3<Float>(cX, topY, cZ)
        let mainSpan  = topY - botY

        // Side arms: (fraction along main tunnel, end X offset, end Y offset from branch)
        // Estimated from the model's gallery pattern.
        let arms: [(frac: Float, dx: Float, dy: Float)] = [
            (0.25, -0.40,  -0.30),   // left, curves down
            (0.30,  0.45,  -0.25),   // right, curves down
            (0.38, -0.50,  -0.15),   // left
            (0.42,  0.55,  -0.10),   // right
            (0.50, -0.50,   0.05),   // left
            (0.55,  0.50,   0.10),   // right
            (0.63, -0.45,   0.20),   // left
            (0.68,  0.45,   0.25),   // right
            (0.76, -0.35,   0.30),   // left, shorter
            (0.82,  0.35,   0.30),   // right, shorter
        ]

        // Materials
        let motherMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1))
        let larvaMaterial  = UnlitMaterial(color: UIColor(red: 1.0, green: 0.95, blue: 0.8, alpha: 1))

        let motherMesh = MeshResource.generateSphere(radius: AppConfig.tunnelDotRadius)
        let larvaMesh  = MeshResource.generateSphere(radius: AppConfig.larvaDotRadius)

        let container = Entity()
        container.name = Self.tunnelAnimName

        // Mother dot
        let mother = ModelEntity(mesh: motherMesh, materials: [motherMaterial])
        mother.position = mainStart
        mother.scale = SIMD3<Float>(repeating: 0.001)
        mother.isEnabled = false
        mother.components.set(TunnelDotComponent(
            pathStart: mainStart,
            pathEnd: mainEnd,
            startDelay: 0,
            travelDuration: AppConfig.motherTravelTime,
            isMother: true
        ))
        container.addChild(mother)

        // Larva dots — one per arm
        let halfWidth = bounds.extents.x / 2
        for arm in arms {
            let branchY = botY + arm.frac * mainSpan
            let branchPoint = SIMD3<Float>(cX, branchY, cZ)
            let endPoint = SIMD3<Float>(
                cX + arm.dx * halfWidth,
                branchY + arm.dy * mainSpan * 0.5,
                cZ
            )
            // Larva starts when mother reaches the branch point, plus a small offset
            let delay = arm.frac * AppConfig.motherTravelTime + AppConfig.larvaStartOffset

            let larva = ModelEntity(mesh: larvaMesh, materials: [larvaMaterial])
            larva.position = branchPoint
            larva.scale = SIMD3<Float>(repeating: 0.001)
            larva.isEnabled = false
            larva.components.set(TunnelDotComponent(
                pathStart: branchPoint,
                pathEnd: endPoint,
                startDelay: delay,
                travelDuration: AppConfig.larvaTravelTime
            ))
            container.addChild(larva)
        }

        entity.addChild(container)
    }
}

