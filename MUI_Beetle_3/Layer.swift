import Foundation

/// What happens when a layer is tapped (besides fading the other layers).
enum LayerEffect {
    case boreHole       // bark: bore holes appear, sawdust falls and heaps form
    case enlarge        // beetle: scaled up while selected
    case sweep          // feeding tunnel: a light sweeps along the galleries
    case nutrientFlow   // cambium: sugar droplets stream along the layer
    case turn           // inner log: one slow turn around its long axis
}

/// The five layers, in the order they are peeled apart (outside to inside).
enum Layer: Int, CaseIterable, Identifiable, Hashable {
    case bark
    case beetle
    case feedingTunnel
    case bast
    case innerLog

    var id: Int { rawValue }

    /// Name of the entity inside the Reality Composer Pro scene.
    /// PLACEHOLDERS: replace each string with the entity name used in your scene.
    var entityName: String {
        switch self {
        case .bark:          "bark"
        case .beetle:        "beetle"
        case .feedingTunnel: "feeding_tunnel_1"
        case .bast:       "bast"
        case .innerLog:      "woodcenter"
        }
    }

    // MARK: Content

    var title: String {
        switch self {
        case .bark:          "Bark"
        case .beetle:        "Bark beetle"
        case .feedingTunnel: "Feeding tunnels"
        case .bast:       "Bast"
        case .innerLog:      "Inner wood"
        }
    }

    var summary: String {
        switch self {
        case .bark:
            "The outer bark is the tree's armor. Its dry, corky tissue shields the living layers beneath from heat, fungi and insects. A healthy spruce also fights back with sticky resin that can push a beetle out of its entrance hole."
        case .beetle:
            "The European spruce bark beetle is only 4 to 5.5 millimetres long. A male bores through the bark and releases a scent that calls hundreds of beetles to the same tree. They also carry blue-stain fungi that spread in the wood and help weaken the tree."
        case .feedingTunnel:
            "Under the bark, a female gnaws a main tunnel along the grain and lays eggs in small niches at its sides. The hatching larvae eat their own side tunnels, which fan out. The pattern looks like print, which is why the beetle is called the book printer in German."
        case .bast:
            "The cambium is a thin layer of living cells just under the bark. It builds new wood inward and new bark tissue outward. The tissue carries sugar from the needles down to the roots, and tunnels that cut through it interrupt this flow."
        case .innerLog:
            "The sapwood carries water and minerals from the roots up to the crown. Fungi brought in by the beetles can clog the water-conducting cells, so the crown dries out. The needles turn brown and the tree can die within weeks to months of a mass attack."
        }
    }

    /// Invitation shown in the info panel while the layer is not selected.
    var tapHint: String {
        switch self {
        case .bark:          "Tap the bark to make it pulse, like a tree under attack."
        case .beetle:        "Tap the beetle to enlarge it and look closer."
        case .feedingTunnel: "Tap the tunnels to send a light along them."
        case .bast:         "Tap the bast to watch sugars flow through it."
        case .innerLog:      "Tap the wood to turn it slowly."
        }
    }

    // MARK: Layout

    /// Final offset from rest position when revealed, forming a left-to-right layout above the log.
    /// X = horizontal spread, Y = height above log, Z = 0.
    /// Models are halved: bark ~0.38m, bast ~0.31m, wood ~0.28m, tunnel ~0.19m, beetle ~0.02m.
    var revealedOffset: SIMD3<Float> {
        switch self {
        case .bark:          SIMD3<Float>(-0.80, 0.65, 0)
        case .beetle:        SIMD3<Float>(-0.40, 0.65, 0)
        case .feedingTunnel: SIMD3<Float>( 0.00, 0.65, 0)
        case .bast:          SIMD3<Float>( 0.40, 0.65, 0)
        case .innerLog:      SIMD3<Float>( 0.80, 0.65, 0)
        }
    }

    // MARK: Tap behaviour

    var effect: LayerEffect {
        switch self {
        case .bark:          .boreHole
        case .beetle:        .enlarge
        case .feedingTunnel: .sweep
        case .bast:       .nutrientFlow
        case .innerLog:      .turn
        }
    }

    /// Length of the transient animation, in seconds.
    var effectDuration: Double {
        switch self {
        case .bark:          0
        case .beetle:        0
        case .feedingTunnel: 4.0
        case .bast:       6.0
        case .innerLog:      6.0
        }
    }

    /// Scale while the layer is selected.
    var selectedScale: Float {
        self == .beetle ? 5.5 : 1.5
    }
}
