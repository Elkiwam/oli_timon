# Bark Beetle – visionOS app

Educational app for Apple Vision Pro (visionOS 26, Xcode 26, SwiftUI + RealityKit).
A welcome window leads into an immersive space with a log made of five layers. Pinch and drag the layers apart, tap one to bring it to life.

## Files

| File | Purpose |
|---|---|
| `BarkBeetleApp.swift` | App entry. Registers the components and systems, declares the welcome window and the immersive space. |
| `WelcomeView.swift` | Greeting text and the **Start** button. |
| `ImmersiveView.swift` | `RealityView` with the drag and tap gestures. |
| `LayerController.swift` | Loads the Reality Composer Pro scene, adds collision, hover glow and info panels, handles drag, tap, fading and recombine. |
| `Systems.swift` | `LayerMotionSystem` (easing, fade, scale, turn, panel follow) and `ProceduralEffectSystem` (sugar droplets, light sweep). |
| `Components.swift` | Per-layer runtime state and the effect components. |
| `Layer.swift` | The five layers: entity name, info text, pulled-apart offset, tap effect. |
| `OverlayViews.swift` | SwiftUI info panel and the control panel (Recombine, Exit). |
| `AppModel.swift` | Observable UI state (selected layer, dragged layer, separated layers). |
| `AppConfig.swift` | Names, distances, gains and timings in one place. |

## Set up in Xcode

1. **File > New > Project > visionOS > App.** Set *Initial Scene* to Window, *Immersive Space Renderer* to RealityKit, *Immersive Space* to Mixed.
2. Delete the template's `ContentView.swift`, `ToggleImmersiveSpaceButton.swift`, and the generated `AppModel.swift`, `ImmersiveView.swift` and `App` file. Add the files from this folder instead.
3. Open `Packages/RealityKitContent` in Reality Composer Pro. Put the five models in one scene around a shared origin, so they form the log at rest.
4. Replace the placeholder names:
   - `AppConfig.sceneName` – the scene (`.usda`) that holds the models.
   - `Layer.entityName` in `Layer.swift` – one entity name per layer (`Bark_Placeholder`, `Beetle_Placeholder`, `FeedingTunnel_Placeholder`, `Cambium_Placeholder`, `InnerLog_Placeholder`).
5. Build and run on the Apple Vision Pro simulator or a device. No extra Info.plist keys are needed.

## Things to know

- **Direction of the pull.** Layers separate along the X axis. Orient the log so its long axis is not along X (for example standing upright, or pointing toward the user). Otherwise the layers overlap when pulled apart.
- **Drag.** Each layer follows the hand and snaps into its slot when released past halfway, otherwise it returns. Slots are set by `Layer.explodedOffsetX`; feel is set by `AppConfig.dragGain`.
- **Hover glow.** A system `HoverEffectComponent` makes the layer glow when the user looks at it. The app never receives gaze data, which is why the info panel appears during a drag and after a tap, not on look.
- **Collision.** Each layer gets a simple box collider, which keeps the beetle easy to pinch. The outermost layer is hit first, so peeling starts at the bark.
- **Tap effects.** Bark pulses, beetle scales up, feeding tunnels get a sweeping light, the cambium streams sugar droplets, the inner wood makes one slow turn. All are procedural, so no baked animations are needed.
- **Deselect.** Tap the selected layer again, tap empty space (an invisible wall behind the log catches the tap), or press **Recombine layers**.
- **Exit.** The **Exit** button leaves the immersive space and shows the welcome window again.
