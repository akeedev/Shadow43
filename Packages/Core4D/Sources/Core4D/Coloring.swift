// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation

/// The small textures behind the colour sources and patterns (DESIGN 6.3, 11.6). The app draws
/// them; every colour source is one of these plus a texture coordinate.
public enum ColorTexture: Hashable, Sendable, CaseIterable {
    /// One colour (uniform faces).
    case uniform
    /// Plain light (edges).
    case light
    /// Blue (w = −1) ↔ red (w = +1), 256×1.
    case byW
    /// The cell palette, `paletteCount`×1.
    case palette
    /// Checkerboard in (u, v) for surfaces.
    case checkerboard
    /// Hue sweep for Hopf fibres.
    case hue
    /// Repeating image patterns on the faces (D24), drawn in code and tileable.
    case grid, marble, wood

    /// Number of palette entries; `FrameColorMode.palette(count:)` uses the same.
    public static let paletteCount = 12

    /// Patterns repeat across a face; colour lookups stay inside the texture.
    public var isPattern: Bool { self == .grid || self == .marble || self == .wood }

    /// Nearest filtering for the palette, so that neighbouring entries never blend.
    public var usesNearestFilter: Bool { self == .palette }
}

/// How faces or edges are coloured: a texture, and the rule that turns each point's colour key
/// into a coordinate in it.
public struct Coloring: Equatable, Sendable {
    public var texture: ColorTexture
    public var mode: FrameColorMode

    public init(texture: ColorTexture, mode: FrameColorMode) {
        self.texture = texture
        self.mode = mode
    }

    /// The colouring of a colour source.
    public init(_ source: ColorSource) {
        switch source {
        case .uniform: self.init(texture: .uniform, mode: .uniform)
        case .byW: self.init(texture: .byW, mode: .byW)
        case .perCell: self.init(texture: .palette, mode: .palette(count: ColorTexture.paletteCount))
        case .surfaceParameter: self.init(texture: .checkerboard, mode: .surfaceParameter)
        case .perFibre: self.init(texture: .hue, mode: .curveKey)
        }
    }

    /// The faces: a pattern replaces the colour source (D24).
    public static func faces(source: ColorSource, pattern: SurfacePattern) -> Coloring {
        switch pattern {
        case .none: Coloring(source)
        case .grid: Coloring(texture: .grid, mode: .pattern)
        case .marble: Coloring(texture: .marble, mode: .pattern)
        case .wood: Coloring(texture: .wood, mode: .pattern)
        }
    }

    /// The edges: the colour source, or plain light; patterns never apply to them.
    public static func edges(source: ColorSource, edgeColor: EdgeColorMode) -> Coloring {
        switch edgeColor {
        case .matchFaces: Coloring(source)
        case .light: Coloring(texture: .light, mode: .uniform)
        }
    }
}
