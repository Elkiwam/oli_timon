import ARKit
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
    private var rootEntity: Entity?
    private var tooltipEntity: Entity?
    private var arkitSession: ARKitSession?

    private static let flowName = "NutrientFlow"
    private static let sweepName = "SweepDisc"

    private struct ActiveDrag {
        let layer: Layer
        let pointerStartY: Float
        let layerStartY: Float
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
        // Position is set by object tracking when the physical log is detected.
        self.rootEntity = root

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

        // Scale down and center all layer entities at root origin,
        // overlapping with the physical log (or ghost placeholder).
        for (layer, entity) in layerEntities {
            // Halve each model so they're slightly larger than the physical log (~0.24m).
            entity.scale *= 0.5
            // Move to origin first, then measure where the mesh visually appears.
            entity.position = .zero
            let bounds = entity.visualBounds(relativeTo: root)
            // Shift so the visual center sits at root origin.
            entity.position = -bounds.center
            print("[Layout] \(layer.title): extents=\(bounds.extents) → position=\(entity.position)")
        }

        for (layer, entity) in layerEntities {
            // Compute per-layer panel height: distance from entity center to its visual top.
            let bounds = entity.visualBounds(relativeTo: root)
            let halfHeight = bounds.extents.y / 2
            configure(layer, entity: entity, root: root, panelHalfHeight: halfHeight)
        }

        // Drag zone: a large invisible collision box at root origin (the log position).
        // Ensures drags anywhere near the log redirect to the next draggable layer.
        let dragZone = Entity()
        dragZone.name = "LogDragZone"
        dragZone.components.set(CollisionComponent(shapes: [.generateBox(size: [0.3, 0.4, 0.3])]))
        dragZone.components.set(InputTargetComponent())
        root.addChild(dragZone)

        // Tooltip: shown after log detection, hidden once all layers are revealed.
        let tooltip = Entity()
        tooltip.name = "Tooltip"
        tooltip.components.set(ViewAttachmentComponent(rootView: TooltipView(appModel: appModel)))
        tooltip.components.set(BillboardComponent())
        tooltip.position = [0, 0.55, 0]
        tooltip.isEnabled = false
        root.addChild(tooltip)
        self.tooltipEntity = tooltip

        root.addChild(makeBackdrop())
        root.addChild(makeControlPanel(onExit: onExit))

        // Start ARKit object tracking to detect the physical log.
        Task { await startObjectTracking() }

        return root
    }

    private func configure(_ layer: Layer, entity: Entity, root: Entity, panelHalfHeight: Float) {
        let rootBounds = entity.visualBounds(relativeTo: root)
        let localBounds = entity.visualBounds(relativeTo: entity)
        let axisIndex = Self.longestAxis(of: localBounds.extents)

        var state = LayerComponent(
            layer: layer,
            restPosition: entity.position,
            explodedPosition: entity.position + layer.revealedOffset,
            basePosition: entity.position,
            targetPosition: entity.position,
            baseScale: entity.scale,
            baseOrientation: entity.orientation,
            longAxis: entity.orientation.act(Self.basis(axisIndex)),
            panelCenter: rootBounds.center - entity.position,
            panelBaseY: panelHalfHeight
        )
        state.revealedPosition = entity.position + layer.revealedOffset
        state.revealPhase = .hidden
        state.targetOpacity = 0
        state.currentOpacity = 0
        state.appliedOpacity = 0

        // Start the entity fully invisible right now (not waiting for the system's first frame).
        entity.components.set(OpacityComponent(opacity: 0))

        // Info panel (SwiftUI attachment), hidden until the layer is dragged or tapped.
        let panel = Entity()
        panel.name = "InfoPanel_\(layer.title)"
        panel.components.set(ViewAttachmentComponent(rootView: LayerInfoView(layer: layer, appModel: appModel)))
        panel.components.set(BillboardComponent())
        panel.position = [rootBounds.center.x, rootBounds.center.y + panelHalfHeight + AppConfig.panelHeightAboveLog, rootBounds.center.z]
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
        descPanel.position = [rootBounds.center.x, rootBounds.center.y - panelHalfHeight - 0.45, rootBounds.center.z]
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

        // Guard: drag only enabled after detection
        guard appModel.isDragEnabled else {
            print("[Drag] Blocked: drag not enabled (logDetected=\(appModel.logDetected))")
            return
        }

        // Layer drag: VERTICAL (Y-axis)
        let y = Float(point.y)
        guard let drag = activeDrag else {
            print("[Drag] New drag on entity: '\(value.entity.name)' at y=\(y)")
            beginDrag(on: value.entity, pointerY: y)
            return
        }
        guard let entity = layerEntities[drag.layer],
              var state = entity.components[LayerComponent.self] else { return }

        let delta = (y - drag.pointerStartY) * AppConfig.verticalDragGain
        // Only allow upward movement (positive delta)
        let clampedDelta = max(0, delta)
        state.riseOffsetY = clampedDelta
        state.basePosition.y = drag.layerStartY + clampedDelta

        // Fade in proportional to rise distance
        let fadeProgress = min(clampedDelta / AppConfig.riseFadeInDistance, 1.0)
        state.targetOpacity = fadeProgress
        state.currentOpacity = fadeProgress

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

        guard let entity = layerEntities[drag.layer],
              var state = entity.components[LayerComponent.self] else { return }

        state.isDragging = false
        let riseDistance = state.riseOffsetY

        if riseDistance >= AppConfig.revealThreshold {
            // Past threshold: auto-animate to revealed side position
            state.revealPhase = .autoAnimating
            state.isSeparated = true
            state.targetPosition = state.revealedPosition
            state.targetOpacity = 1
            appModel.separatedLayers.insert(drag.layer)
        } else {
            // Below threshold: fade back and return to rest
            state.revealPhase = .hidden
            state.isSeparated = false
            state.targetPosition = state.restPosition
            state.targetOpacity = 0
            state.riseOffsetY = 0
            appModel.separatedLayers.remove(drag.layer)
        }

        entity.components.set(state)

        // Hide tooltip once all layers are revealed
        if appModel.allLayersRevealed {
            tooltipEntity?.isEnabled = false
        }

        refreshPanels()
    }

    private func beginDrag(on entity: Entity, pointerY: Float) {
        // If the user targeted the drag zone or backdrop (not a layer entity),
        // redirect to the next draggable layer automatically.
        var resolvedEntity = entity
        if layerOwner(of: entity) == nil {
            if let nextLayer = appModel.nextDraggableLayer,
               let layerEntity = layerEntities[nextLayer] {
                print("[Drag] Redirecting from '\(entity.name)' to next draggable: \(nextLayer.title)")
                resolvedEntity = layerEntity
            } else {
                print("[Drag] beginDrag: no layer owner and no next draggable layer")
                return
            }
        }

        guard let (layer, layerEntity) = layerOwner(of: resolvedEntity),
              var state = layerEntity.components[LayerComponent.self] else {
            print("[Drag] beginDrag: no layer owner found for entity '\(resolvedEntity.name)'")
            return
        }

        // Enforce the forced drag sequence: only the next layer in order can be dragged.
        guard layer == appModel.nextDraggableLayer else {
            print("[Drag] beginDrag: \(layer.title) is not the next draggable (expected \(appModel.nextDraggableLayer?.title ?? "nil"))")
            return
        }
        // Only allow drag if layer is still hidden (not yet revealed).
        guard state.revealPhase == .hidden else {
            print("[Drag] beginDrag: \(layer.title) phase is \(state.revealPhase), expected .hidden")
            return
        }

        // Reveal inner wood title on first touch (drag or tap).
        if layer == .innerLog && !appModel.innerLogRevealed {
            appModel.innerLogRevealed = true
        }

        state.isDragging = true
        state.revealPhase = .rising
        layerEntity.components.set(state)

        activeDrag = ActiveDrag(layer: layer, pointerStartY: pointerY, layerStartY: state.basePosition.y)
        appModel.draggingLayer = layer
        print("[Drag] Started dragging \(layer.title) from y=\(state.basePosition.y)")
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
            // Don't touch opacity of layers that haven't been revealed yet.
            guard state.revealPhase == .revealed || state.revealPhase == .autoAnimating else { continue }
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
            state.revealPhase = .hidden
            state.riseOffsetY = 0
            state.targetPosition = state.restPosition
            state.targetOpacity = 0
            entity.components.set(state)
        }
        appModel.separatedLayers.removeAll()
        appModel.innerLogRevealed = false

        // Re-show tooltip for another round
        tooltipEntity?.isEnabled = true

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

        // Compute gravity-aligned floor in world space and place heap on it
        let cornersLocal: [SIMD3<Float>] = [
            [bounds.min.x, bounds.min.y, bounds.min.z], [bounds.max.x, bounds.min.y, bounds.min.z],
            [bounds.min.x, bounds.max.y, bounds.min.z], [bounds.max.x, bounds.max.y, bounds.min.z],
            [bounds.min.x, bounds.min.y, bounds.max.z], [bounds.max.x, bounds.min.y, bounds.max.z],
            [bounds.min.x, bounds.max.y, bounds.max.z], [bounds.max.x, bounds.max.y, bounds.max.z]
        ]
        let worldMinY = cornersLocal
            .map { entity.convert(position: $0, to: nil).y }
            .min() ?? 0

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

            // Compute gravity-aligned floor in world space and place heap on it
            let holeWorld = entity.convert(position: holePos, to: nil)
            var heapWorld = holeWorld
            heapWorld.y = worldMinY
            let heapLocal = entity.convert(position: heapWorld, from: nil)

            let heap = ModelEntity(mesh: heapMesh, materials: [dustMaterial])
            heap.position = heapLocal
            heap.scale = SIMD3<Float>(0.001, 0.001, 0.001)
            heap.isEnabled = false
            heap.components.set(SawdustComponent(
                holeIndex: i,
                originPosition: holePos,
                floorY: heapLocal.y,
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
        // Build tunnel paths aligned with gravity (world -Y), independent of model rotation
        // Compute top and bottom points in local, convert to world to get true vertical ordering
        let margin: Float = bounds.extents.y * 0.05
        let localTop = SIMD3<Float>(bounds.center.x, bounds.max.y - margin, bounds.center.z)
        let localBot = SIMD3<Float>(bounds.center.x, bounds.min.y + margin, bounds.center.z)

        let worldTop = entity.convert(position: localTop, to: nil)
        let worldBot = entity.convert(position: localBot, to: nil)

        // Ensure start is higher than end in world space
        let mainStartWorld = worldTop.y >= worldBot.y ? worldTop : worldBot
        let mainEndWorld   = worldTop.y >= worldBot.y ? worldBot : worldTop
        let mainSpanWorldY = max(0, mainStartWorld.y - mainEndWorld.y)

        // Choose a world-horizontal axis for arms (world X)
        let armHorizAxis = SIMD3<Float>(1, 0, 0)
        let halfWidthWorld: Float = (bounds.extents.x / 2) * max(entity.scale(relativeTo: nil).x, 0.0001)

        // Convert world points back to local for the components and initial positions
        let mainStart = entity.convert(position: mainStartWorld, from: nil)
        let mainEnd   = entity.convert(position: mainEndWorld, from: nil)

        // Materials
        let motherMaterial = UnlitMaterial(color: UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1))
        let larvaMaterial  = UnlitMaterial(color: UIColor(red: 1.0, green: 0.95, blue: 0.8, alpha: 1))

        let motherMesh = MeshResource.generateSphere(radius: AppConfig.tunnelDotRadius)
        let larvaMesh  = MeshResource.generateSphere(radius: AppConfig.larvaDotRadius)

        let container = Entity()
        container.name = Self.tunnelAnimName

        // Mother dot travels straight down along world -Y (converted to local for storage)
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

        // Arms: (fraction along mother path, horizontal offset along world X, vertical offset along world Y)
        let arms: [(frac: Float, dx: Float, dy: Float)] = [
            (0.25, -0.40,  -0.30),
            (0.30,  0.45,  -0.25),
            (0.38, -0.50,  -0.15),
            (0.42,  0.55,  -0.10),
            (0.50, -0.50,   0.05),
            (0.55,  0.50,   0.10),
            (0.63, -0.45,   0.20),
            (0.68,  0.45,   0.25),
            (0.76, -0.35,   0.30),
            (0.82,  0.35,   0.30),
        ]

        for arm in arms {
            // Branch point at a fraction down the mother path in world space
            var branchWorld = mainStartWorld
            branchWorld.y = mainStartWorld.y - arm.frac * mainSpanWorldY

            // End point offset horizontally (world X) and vertically (world Y)
            var endWorld = branchWorld
            endWorld += armHorizAxis * (arm.dx * halfWidthWorld)
            endWorld.y += arm.dy * (mainSpanWorldY * 0.5)

            // Convert back to local
            let branchLocal = entity.convert(position: branchWorld, from: nil)
            let endLocal = entity.convert(position: endWorld, from: nil)

            let delay = arm.frac * AppConfig.motherTravelTime + AppConfig.larvaStartOffset

            let larva = ModelEntity(mesh: larvaMesh, materials: [larvaMaterial])
            larva.position = branchLocal
            larva.scale = SIMD3<Float>(repeating: 0.001)
            larva.isEnabled = false
            larva.components.set(TunnelDotComponent(
                pathStart: branchLocal,
                pathEnd: endLocal,
                startDelay: delay,
                travelDuration: AppConfig.larvaTravelTime
            ))
            container.addChild(larva)
        }
        entity.addChild(container)
    }

    // MARK: - Object Tracking

    private func startObjectTracking() async {
        // In the simulator, object tracking is not available.
        // Fall back to a fixed position with a debug placeholder.
        #if targetEnvironment(simulator)
        print("[ObjectTracking] Running in simulator — using fixed position with debug placeholder.")
        simulatorFallback()
        return
        #else
        guard ObjectTrackingProvider.isSupported else {
            print("[ObjectTracking] ObjectTrackingProvider not supported on this device.")
            simulatorFallback()
            return
        }

        guard let url = realityKitContentBundle.url(
            forResource: AppConfig.referenceObjectName,
            withExtension: AppConfig.referenceObjectExtension
        ) else {
            print("[ObjectTracking] Reference object file not found in bundle.")
            simulatorFallback()
            return
        }

        do {
            let referenceObject = try await ReferenceObject(from: url)
            let session = ARKitSession()
            let objectTracking = ObjectTrackingProvider(referenceObjects: [referenceObject])
            self.arkitSession = session

            try await session.run([objectTracking])

            for await update in objectTracking.anchorUpdates {
                switch update.event {
                case .added, .updated:
                    guard update.anchor.isTracked else { continue }
                    let worldTransform = update.anchor.originFromAnchorTransform
                    applyDetectedTransform(worldTransform)
                    // Stop tracking after first detection (lock in place)
                    session.stop()
                    return
                case .removed:
                    continue
                }
            }
        } catch {
            print("[ObjectTracking] Failed to start: \(error)")
            simulatorFallback()
        }
        #endif
    }

    /// Called when the physical log is recognized. Sets root transform and enables interaction.
    private func applyDetectedTransform(_ worldTransform: simd_float4x4) {
        guard let root = rootEntity else { return }
        root.transform = Transform(matrix: worldTransform)
        appModel.logDetected = true
        tooltipEntity?.isEnabled = true
        print("[ObjectTracking] Log detected and locked in place.")
    }

    /// Simulator / unsupported fallback: place at a fixed position, show a semitransparent
    /// scan of the log so we can see where the physical log would be, and enable drag interaction.
    private func simulatorFallback() {
        guard let root = rootEntity else { return }
        root.position = AppConfig.logPosition
        appModel.logDetected = true
        tooltipEntity?.isEnabled = true

        // Debug: print layer entity positions so we can verify collision shapes
        for (layer, entity) in layerEntities {
            let worldPos = entity.position(relativeTo: nil)
            print("[Simulator] \(layer.title) local=\(entity.position) world=\(worldPos)")
            if let collision = entity.components[CollisionComponent.self] {
                print("[Simulator]   collision shapes: \(collision.shapes.count)")
            }
        }

        // Load the actual 3D scan of the log as a semitransparent placeholder.
        Task {
            do {
                let logModel = try await Entity(named: "Log_Model_mui_1", in: realityKitContentBundle)
                logModel.name = "DebugPlaceholderLog"

                // Make all meshes semitransparent
                func applyGhostMaterial(to entity: Entity) {
                    if var model = entity.components[ModelComponent.self] {
                        model.materials = model.materials.map { _ in
                            SimpleMaterial(color: UIColor(white: 0.7, alpha: 0.3), isMetallic: false)
                        }
                        entity.components.set(model)
                    }
                    for child in entity.children {
                        applyGhostMaterial(to: child)
                    }
                }
                applyGhostMaterial(to: logModel)

                root.addChild(logModel)
                print("[Simulator] Placed log scan placeholder at \(AppConfig.logPosition).")
            } catch {
                // Fallback to a simple cylinder if the scan can't be loaded
                let cylinder = ModelEntity(
                    mesh: .generateCylinder(height: 0.35, radius: 0.08),
                    materials: [SimpleMaterial(color: UIColor(white: 0.6, alpha: 0.25), isMetallic: false)]
                )
                cylinder.name = "DebugPlaceholderLog"
                cylinder.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
                root.addChild(cylinder)
                print("[Simulator] Log scan not found, using cylinder placeholder. Error: \(error)")
            }
        }
    }
}

