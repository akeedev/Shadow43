// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import CoreGraphics
import Foundation
import Metal
import RealityKit

/// The small textures behind the colour sources (DESIGN 3.4, 6.5): every colour source is a
/// texture coordinate plus one of these.
enum ColorTexture: Hashable {
    /// One colour (uniform faces).
    case uniform
    /// Plain light (edges).
    case light
    /// Blue (w = −1) ↔ red (w = +1), 256×1.
    case byW
    /// N×1 palette for cells.
    case palette
    /// Checkerboard in (u, v) for surfaces.
    case checkerboard
    /// Hue sweep for Hopf fibres.
    case hue
    /// Repeating image patterns on the faces (D24), drawn in code and tileable.
    case grid, marble, wood

    /// Number of palette entries; must match `FrameColorMode.palette(count:)`.
    static let paletteCount = 12

    static let paletteColors: [SIMD3<Double>] = [
        [0.30, 0.60, 1.00], [1.00, 0.55, 0.20], [0.35, 0.85, 0.45], [0.95, 0.35, 0.45],
        [0.70, 0.50, 1.00], [1.00, 0.85, 0.30], [0.25, 0.85, 0.85], [1.00, 0.50, 0.80],
        [0.60, 0.80, 0.30], [0.55, 0.65, 0.95], [0.95, 0.65, 0.55], [0.75, 0.75, 0.75],
    ]

    /// RGBA pixels (sRGB) and size.
    var pixels: (width: Int, height: Int, rgb: [SIMD3<Double>]) {
        switch self {
        case .uniform:
            return (4, 4, Array(repeating: [0.55, 0.85, 1.00], count: 16))
        case .light:
            return (4, 4, Array(repeating: [0.95, 0.95, 0.90], count: 16))
        case .byW:
            let blue: SIMD3<Double> = [0.15, 0.40, 1.00]
            let mid: SIMD3<Double> = [0.85, 0.80, 0.95]
            let red: SIMD3<Double> = [1.00, 0.22, 0.18]
            let row = (0..<256).map { i -> SIMD3<Double> in
                let t = Double(i) / 255
                return t < 0.5 ? blue + (mid - blue) * (t * 2) : mid + (red - mid) * ((t - 0.5) * 2)
            }
            return (256, 1, row)
        case .palette:
            return (Self.paletteCount, 1, Self.paletteColors)
        case .checkerboard:
            let (w, h, nu, nv) = (384, 192, 12, 6)
            let light: SIMD3<Double> = [1.00, 0.80, 0.35], dark: SIMD3<Double> = [0.20, 0.45, 0.90]
            var px: [SIMD3<Double>] = []
            for y in 0..<h {
                for x in 0..<w {
                    px.append((x * nu / w + y * nv / h) % 2 == 0 ? light : dark)
                }
            }
            return (w, h, px)
        case .hue:
            let row = (0..<256).map { i -> SIMD3<Double> in hsv(Double(i) / 256, 0.75, 1) }
            return (256, 1, row)
        case .grid:
            // One grid cell per repeat: a dark line along two sides of the tile.
            let n = 256, line = 10
            let paper: SIMD3<Double> = [0.93, 0.93, 0.96], ink: SIMD3<Double> = [0.16, 0.22, 0.40]
            return (n, n, Self.tile(n) { x, y in x < line || y < line ? ink : paper })
        case .marble:
            let n = 256
            let stone: SIMD3<Double> = [0.95, 0.94, 0.91], vein: SIMD3<Double> = [0.42, 0.44, 0.50]
            return (n, n, Self.tile(n) { x, y in
                // One wavy vein per tile; calm noise, so it reads as stone, not as squiggles.
                let (u, v) = (Double(x) / Double(n), Double(y) / Double(n))
                let s = 0.5 + 0.5 * sin(2 * .pi * (u + 0.3 * Self.turbulence(u, v)))
                return vein + (stone - vein) * pow(s, 0.25)
            })
        case .wood:
            let n = 256
            let light: SIMD3<Double> = [0.86, 0.66, 0.42], dark: SIMD3<Double> = [0.52, 0.32, 0.16]
            return (n, n, Self.tile(n) { x, y in
                let (u, v) = (Double(x) / Double(n), Double(y) / Double(n))
                let rings = 3 * v + 0.25 * Self.turbulence(u, v)
                let f = rings - floor(rings)
                return dark + (light - dark) * pow(1 - abs(2 * f - 1), 0.6)
            })
        }
    }

    /// Pixels of an n×n tile, row by row.
    private static func tile(_ n: Int, _ colour: (Int, Int) -> SIMD3<Double>) -> [SIMD3<Double>] {
        var px: [SIMD3<Double>] = []
        px.reserveCapacity(n * n)
        for y in 0..<n {
            for x in 0..<n { px.append(colour(x, y)) }
        }
        return px
    }

    /// Smooth noise in roughly −1…1 that repeats over the unit square: a fixed sum of waves with
    /// whole-number frequencies, so tiles join without seams.
    private static func turbulence(_ u: Double, _ v: Double) -> Double {
        let waves: [(Double, Double, Double, Double)] = [
            (1, 2, 0.50, 0.3), (3, 1, 0.30, 1.7), (2, 5, 0.18, 4.1), (5, 3, 0.12, 2.6), (7, 6, 0.07, 5.3),
        ]
        return waves.reduce(0) { sum, w in sum + w.2 * sin(2 * .pi * (w.0 * u + w.1 * v) + w.3) }
    }

    /// Patterns repeat across a face; colour lookups stay inside the texture.
    var isPattern: Bool { self == .grid || self == .marble || self == .wood }

    /// Nearest filtering for the palette, so that neighbouring entries never blend.
    var usesNearestFilter: Bool { self == .palette }

    func makeImage() -> CGImage? {
        let (w, h, rgb) = pixels
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for (i, c) in rgb.enumerated() {
            bytes[4 * i] = UInt8(max(0, min(255, (c.x * 255).rounded())))
            bytes[4 * i + 1] = UInt8(max(0, min(255, (c.y * 255).rounded())))
            bytes[4 * i + 2] = UInt8(max(0, min(255, (c.z * 255).rounded())))
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    @MainActor
    func makeTexture() -> MaterialParameters.Texture? {
        // Patterns are seen small and at grazing angles, so they get mipmaps.
        let mipmaps: TextureResource.MipmapsMode = isPattern ? .allocateAndGenerateAll : .none
        guard let image = makeImage(),
              let resource = try? TextureResource(image: image, withName: nil,
                                                  options: .init(semantic: .color, mipmapsMode: mipmaps))
        else { return nil }
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = usesNearestFilter ? .nearest : .linear
        descriptor.magFilter = usesNearestFilter ? .nearest : .linear
        descriptor.mipFilter = isPattern ? .linear : .notMipmapped
        descriptor.sAddressMode = isPattern ? .repeat : .clampToEdge
        descriptor.tAddressMode = isPattern ? .repeat : .clampToEdge
        return MaterialParameters.Texture(resource, sampler: .init(descriptor))
    }
}

/// HSV → RGB, all components in 0…1.
func hsv(_ h: Double, _ s: Double, _ v: Double) -> SIMD3<Double> {
    let i = Int(h * 6) % 6
    let f = h * 6 - floor(h * 6)
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    switch i {
    case 0: return [v, t, p]
    case 1: return [q, v, p]
    case 2: return [p, v, t]
    case 3: return [p, q, v]
    case 4: return [t, p, v]
    default: return [v, p, q]
    }
}
