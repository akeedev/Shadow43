// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Parametric surfaces and curve families in ℝ⁴ (DESIGN 10.6).
public enum Surfaces {
    /// A parametric surface f(u, v) on a grid of nU × nV cells, including the closing row and
    /// column (seam points are duplicated, not glued). UV is passed along normalised to [0, 1];
    /// every `edgeStride`-th grid line becomes an edge polyline.
    public static func grid(nU: Int, nV: Int, uRange: ClosedRange<Double>, vRange: ClosedRange<Double>,
                            edgeStride: Int, f: (Double, Double) -> SIMD4<Double>) -> Complex4D {
        var vertices: [SIMD4<Double>] = []
        var uv: [SIMD2<Double>] = []
        let cols = nV + 1
        for i in 0...nU {
            for j in 0...nV {
                let su = Double(i) / Double(nU)
                let sv = Double(j) / Double(nV)
                let u = uRange.lowerBound + su * (uRange.upperBound - uRange.lowerBound)
                let v = vRange.lowerBound + sv * (vRange.upperBound - vRange.lowerBound)
                vertices.append(f(u, v))
                uv.append([su, sv])
            }
        }
        let index = { (i: Int, j: Int) in i * cols + j }
        var faces: [Face] = []
        for i in 0..<nU {
            for j in 0..<nV {
                faces.append(Face(vertices: [index(i, j), index(i + 1, j), index(i + 1, j + 1), index(i, j + 1)]))
            }
        }
        var edges: [[Int]] = []
        let stride = max(1, edgeStride)
        for i in Swift.stride(from: 0, through: nU, by: stride) {
            edges.append((0...nV).map { index(i, $0) })
        }
        for j in Swift.stride(from: 0, through: nV, by: stride) {
            edges.append((0...nU).map { index($0, j) })
        }
        return Complex4D(vertices: vertices, edges: edges, faces: faces, uv: uv, kind: .surface)
    }

    /// Scales points so that the largest distance from the origin is 1.
    static func scaledToUnitRadius(_ c: Complex4D) -> Complex4D {
        var c = c
        let r = c.vertices.map { simd_length($0) }.max() ?? 1
        if r > 0 { c.vertices = c.vertices.map { $0 / r } }
        return c
    }

    /// The Klein bottle in ℝ⁴ without self-intersection:
    /// `((R + r cos v) cos u, (R + r cos v) sin u, r sin v cos(u/2), r sin v sin(u/2))`,
    /// R = 1, r = 0.5, normalised. It satisfies f(u + 2π, v) = f(u, −v).
    public static func kleinBottleFunction(_ u: Double, _ v: Double, R: Double = 1, r: Double = 0.5) -> SIMD4<Double> {
        SIMD4((R + r * cos(v)) * cos(u), (R + r * cos(v)) * sin(u), r * sin(v) * cos(u / 2), r * sin(v) * sin(u / 2))
    }

    public static func kleinBottle(nU: Int = 72, nV: Int = 36, edgeStride: Int = 6) -> Complex4D {
        scaledToUnitRadius(grid(nU: nU, nV: nV, uRange: 0...(2 * .pi), vRange: 0...(2 * .pi),
                                edgeStride: edgeStride) { kleinBottleFunction($0, $1) })
    }

    /// The Clifford torus `(cos u, sin u, cos v, sin v) / √2`, a flat torus on S³.
    public static func cliffordTorus(n: Int = 64, edgeStride: Int = 8) -> Complex4D {
        grid(nU: n, nV: n, uRange: 0...(2 * .pi), vRange: 0...(2 * .pi), edgeStride: edgeStride) { u, v in
            SIMD4(cos(u), sin(u), cos(v), sin(v)) / sqrt(2)
        }
    }

    /// The Hopf fibre over the point (θ, φ) of S² (θ is the polar angle):
    /// `t ↦ (cos(θ/2) cos t, cos(θ/2) sin t, sin(θ/2) cos(t + φ), sin(θ/2) sin(t + φ))`.
    public static func hopfFibre(theta: Double, phi: Double, t: Double) -> SIMD4<Double> {
        let c = cos(theta / 2), s = sin(theta / 2)
        return SIMD4(c * cos(t), c * sin(t), s * cos(t + phi), s * sin(t + phi))
    }

    /// Fibres over `perCircle` base points on each of the given latitude circles; nested tori of
    /// linked circles. Each fibre is a closed polyline; the colour key is the base point.
    public static func hopfFibration(latitudes: [Double] = [0.3 * .pi, 0.5 * .pi, 0.7 * .pi],
                                     perCircle: Int = 16, samples: Int = 96) -> Complex4D {
        var vertices: [SIMD4<Double>] = []
        var keys: [Double] = []
        var edges: [[Int]] = []
        let total = latitudes.count * perCircle
        for (li, theta) in latitudes.enumerated() {
            for j in 0..<perCircle {
                let phi = 2 * Double.pi * Double(j) / Double(perCircle)
                let key = (Double(li * perCircle + j) + 0.5) / Double(total)
                var line: [Int] = []
                for k in 0..<samples {
                    let t = 2 * Double.pi * Double(k) / Double(samples)
                    line.append(vertices.count)
                    vertices.append(hopfFibre(theta: theta, phi: phi, t: t))
                    keys.append(key)
                }
                line.append(line[0])
                edges.append(line)
            }
        }
        return Complex4D(vertices: vertices, edges: edges, faces: [], curveKey: keys, kind: .curves)
    }
}

/// Builds the complex for an `ObjectID`.
public enum ObjectCatalog {
    public static func complex(for id: ObjectID, duoprism: DuoprismParameters) -> Complex4D {
        switch id {
        case .fiveCell: Polytopes.fiveCell()
        case .tesseract: Polytopes.tesseract()
        case .sixteenCell: Polytopes.sixteenCell()
        case .twentyFourCell: Polytopes.twentyFourCell()
        case .oneTwentyCell: Polytopes.oneTwentyCell()
        case .sixHundredCell: Polytopes.sixHundredCell()
        case .duoprism: Polytopes.duoprism(p: duoprism.p, q: duoprism.q)
        case .kleinBottle: Surfaces.kleinBottle()
        case .cliffordTorus: Surfaces.cliffordTorus()
        case .hopfFibration: Surfaces.hopfFibration()
        }
    }
}
