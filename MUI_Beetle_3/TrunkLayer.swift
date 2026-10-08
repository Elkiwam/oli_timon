#if false
// NOTE: Disabled duplicate stub. Another definition of TrunkLayer exists elsewhere; this stub was originally added to unblock references.
// TrunkLayer.swift
// Defines the layers of a tree trunk used throughout the app.

import Foundation

/// Represents the layers of a tree trunk from outside to inside.
/// This minimal definition unblocks references like `TrunkLayer.allCases.count`
/// and provides a human-readable `title` used in the UI.
public enum TrunkLayer: String, CaseIterable, Identifiable {
    case bark
    case phloem
    case cambium
    case sapwood
    case heartwood

    public var id: Self { self }

    /// User-facing title for each layer.
    public var title: String {
        switch self {
        case .bark: return "Bark"
        case .phloem: return "Phloem"
        case .cambium: return "Cambium"
        case .sapwood: return "Sapwood"
        case .heartwood: return "Heartwood"
        }
    }
}
#endif
