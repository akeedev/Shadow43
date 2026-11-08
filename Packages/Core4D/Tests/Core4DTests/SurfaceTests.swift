// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

@Suite("Surfaces and curves")
struct SurfaceTests {
    @Test func cliffordTorusLiesOnS3() {
        let c = Surfaces.cliffordTorus(n: 24, edgeStride: 4)
        #expect(c.kind == .surface)
        for v in c.vertices { #expect(abs(simd_length(v) - 1) < 1e-12) }
        #expect(c.faces.count == 24 * 24)
        #expect(c.vertices.count == 25 * 25)
        #expect(c.uv?.count == c.vertices.count)
    }

    @Test func hopfFibresLieOnS3AndArePairwiseDisjoint() {
        let c = Surfaces.hopfFibration(perCircle: 8, samples: 48)
        #expect(c.kind == .curves)
        #expect(c.edges.count == 24)
        for v in c.vertices { #expect(abs(simd_length(v) - 1) < 1e-12) }
        // Sampled minimum distance between two different fibres is clearly positive.
        let fibres = c.edges.map { $0.map { c.vertices[$0] } }
        var minDistance = Double.infinity
        for i in fibres.indices {
            for j in fibres.indices where j > i {
                for p in fibres[i] {
                    for q in fibres[j] { minDistance = min(minDistance, simd_distance(p, q)) }
                }
            }
        }
        #expect(minDistance > 0.05)
    }

    @Test func hopfFibresAreGreatCircles() {
        // Each fibre is closed and lies in a 2D plane through the origin.
        let c = Surfaces.hopfFibration(perCircle: 4, samples: 32)
        for e in c.edges {
            #expect(e.first == e.last)
            let pts = e.map { c.vertices[$0] }
            #expect(PolytopeGenerator.affineDimension(pts + [.zero], tolerance: 1e-12) == 2)
        }
    }

    @Test func hopfFibreFormulaIsTheFibreOverItsBasePoint() {
        // The Hopf map (z1, z2) ↦ (2 z1 z̄2, |z1|² − |z2|²) is constant along a fibre.
        func hopf(_ p: SIMD4<Double>) -> SIMD3<Double> {
            let (a, b, c, d) = (p.x, p.y, p.z, p.w)
            return [2 * (a * c + b * d), 2 * (b * c - a * d), a * a + b * b - c * c - d * d]
        }
        let base = hopf(Surfaces.hopfFibre(theta: 1.1, phi: 0.7, t: 0))
        for k in 1..<10 {
            let image = hopf(Surfaces.hopfFibre(theta: 1.1, phi: 0.7, t: Double(k) * 0.6))
            #expect(simd_distance(image, base) < 1e-12)
        }
    }

    @Test(arguments: [0.0, 0.4, 1.3, 2.9, 5.0])
    func kleinBottleSatisfiesTheSeamCondition(_ v: Double) {
        for u in stride(from: 0.0, to: 6.0, by: 0.7) {
            let a = Surfaces.kleinBottleFunction(u + 2 * .pi, v)
            let b = Surfaces.kleinBottleFunction(u, -v)
            #expect(simd_distance(a, b) < 1e-12)
        }
    }

    @Test func kleinBottleIsNormalisedAndHasNoSelfIntersection() {
        let c = Surfaces.kleinBottle(nU: 36, nV: 18, edgeStride: 6)
        let r = c.vertices.map { simd_length($0) }.max()!
        #expect(abs(r - 1) < 1e-12)
        // Distinct parameters (away from the seam identifications) give distinct points.
        let f = { (u: Double, v: Double) in Surfaces.kleinBottleFunction(u, v) }
        var minDistance = Double.infinity
        let samples = stride(from: 0.05, to: 2 * Double.pi, by: 0.4).map { $0 }
        for u1 in samples {
            for v1 in samples {
                for u2 in samples {
                    for v2 in samples where (u1, v1) != (u2, v2) {
                        minDistance = min(minDistance, simd_distance(f(u1, v1), f(u2, v2)))
                    }
                }
            }
        }
        #expect(minDistance > 1e-3)
    }

    @Test func surfaceGridEdgesUseEveryKthLine() {
        let c = Surfaces.grid(nU: 8, nV: 4, uRange: 0...1, vRange: 0...1, edgeStride: 2) { u, v in [u, v, 0, 0] }
        // u-lines at i = 0, 2, 4, 6, 8 and v-lines at j = 0, 2, 4.
        #expect(c.edges.count == 5 + 3)
        #expect(c.edges[0].count == 5)
        #expect(c.edges[5].count == 9)
    }

    @Test func surfaceMeshSharesPointsAndUsesUV() {
        let c = Surfaces.cliffordTorus(n: 8, edgeStride: 4)
        let mesh = Tessellation.renderMesh(for: c, explode: 0.3, options: TessellationOptions())
        #expect(mesh.facePoints.count == c.vertices.count)
        #expect(mesh.triangleCount == 2 * c.faces.count)
        #expect(mesh.facePoints.colorKey[1] == SIMD2<Float>(c.uv![1]))
        #expect(mesh.groupPointRanges.isEmpty)
    }

    @Test func curveMeshCarriesTheFibreKey() {
        let c = Surfaces.hopfFibration(perCircle: 2, samples: 8)
        let mesh = Tessellation.renderMesh(for: c, explode: 0, options: TessellationOptions())
        #expect(mesh.triangleCount == 0)
        #expect(mesh.polylines.count == 6)
        let keys = Set(mesh.edgePoints.colorKey.map(\.x))
        #expect(keys.count == 6)
    }

    @Test(arguments: ObjectID.allCases)
    func catalogBuildsEveryObject(_ id: ObjectID) {
        let c = ObjectCatalog.complex(for: id, duoprism: DuoprismParameters(p: 3, q: 5))
        #expect(c.kind == id.kind)
        #expect(!c.vertices.isEmpty)
        #expect(!c.edges.isEmpty)
    }
}
