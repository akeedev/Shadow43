// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

/// Patterns and thick faces (D24).
@Suite("Surface looks")
struct SurfaceLookTests {
    @Test func everyFacePointHasPatternCoordinates() {
        for c in [Fixtures.tesseract, ObjectCatalog.complex(for: .kleinBottle, duoprism: DuoprismParameters(p: 4, q: 4))] {
            for explode in [0.0, 0.2] {
                let mesh = Tessellation.renderMesh(for: c, explode: explode, options: TessellationOptions())
                #expect(mesh.facePatternUV.count == mesh.facePoints.count)
            }
        }
    }

    @Test func polygonPatternKeepsDistances() {
        // Pattern coordinates are an isometric map of each flat polygon's plane, scaled by the unit.
        let mesh = Tessellation.renderMesh(for: Fixtures.twentyFourCell, explode: 0,
                                           options: TessellationOptions(faceSubdivision: 2))
        for range in mesh.polygonPointRanges.prefix(20) {
            let first = range.lowerBound
            for i in range {
                let d4 = simd_distance(SIMD4<Double>(mesh.facePoints.flat[i]), SIMD4<Double>(mesh.facePoints.flat[first]))
                let d2 = Double(simd_distance(mesh.facePatternUV[i], mesh.facePatternUV[first])) * Tessellation.patternUnit
                #expect(abs(d4 - d2) < 1e-4)
            }
        }
    }

    @Test func surfacePatternIsTheScaledParameter() {
        let mesh = Tessellation.renderMesh(for: ObjectCatalog.complex(for: .cliffordTorus, duoprism: DuoprismParameters(p: 4, q: 4)),
                                           explode: 0, options: TessellationOptions())
        for i in stride(from: 0, to: mesh.facePoints.count, by: 37) {
            let expected = mesh.facePoints.colorKey[i] * Tessellation.surfacePatternRepeats
            #expect(simd_distance(mesh.facePatternUV[i], expected) < 1e-6)
        }
    }

    @Test func planeBasisIsOrthonormalAndSpansThePolygon() {
        let corners: [SIMD4<Double>] = [[1, 0, 0, 1], [0, 1, 0, 1], [-1, 0, 0, 1], [0, -1, 0, 1]]
        let centre = SIMD4<Double>(0, 0, 0, 1)
        let (e1, e2) = Tessellation.planeBasis(corners, centre: centre)
        // The first axis runs along the first edge, so grid lines are parallel to it.
        #expect(simd_distance(e1, simd_normalize(corners[1] - corners[0])) < 1e-12)
        #expect(abs(simd_length(e1) - 1) < 1e-12 && abs(simd_length(e2) - 1) < 1e-12)
        #expect(abs(simd_dot(e1, e2)) < 1e-12)
        for c in corners {
            let d = c - centre
            let inPlane = simd_dot(d, e1) * e1 + simd_dot(d, e2) * e2
            #expect(simd_distance(inPlane, d) < 1e-12)
        }
    }

    @Test func patternModeWritesThePatternCoordinates() {
        let mesh = Tessellation.renderMesh(for: Fixtures.tesseract, explode: 0, options: TessellationOptions())
        let builder = FrameBuilder(mesh: mesh)
        builder.update(FrameParameters(faceColors: .pattern, edgeColors: .uniform))
        let n = builder.backVertexOffset
        for i in 0..<n {
            #expect(builder.faceVertices[i].uv == mesh.facePatternUV[i])
            #expect(builder.faceVertices[n + i].uv == mesh.facePatternUV[i])
        }
        // Edges ignore the pattern mode.
        #expect(FrameColorMode.pattern.uv(key: [3, 4], w: 0.5) == SIMD2(0.5, 0.5))
    }

    @Test func thickFacesBecomeSlabs() {
        let mesh = Tessellation.renderMesh(for: Fixtures.tesseract, explode: 0, options: TessellationOptions())
        // Faces only, so the bounds are not those of the edge tubes.
        let thin = FrameBuilder(mesh: mesh)
        thin.update(FrameParameters(), edges: false)
        let thick = FrameBuilder(mesh: mesh)
        let h: Float = 0.05
        thick.update(FrameParameters(faceOffset: h), edges: false)
        let n = thick.backVertexOffset
        for i in 0..<n {
            let front = thick.faceVertices[i], back = thick.faceVertices[n + i]
            // Same normals as without thickness; the copies sit h above and below the thin face.
            #expect(simd_distance(front.normal, thin.faceVertices[i].normal) < 1e-6)
            #expect(simd_distance(front.position, thin.faceVertices[i].position + h * front.normal) < 1e-5)
            #expect(simd_distance(back.position, thin.faceVertices[i].position - h * front.normal) < 1e-5)
            #expect(simd_distance(back.normal, -front.normal) < 1e-6)
        }
        #expect(abs((thick.boundsMax.x - thin.boundsMax.x) - h) < 1e-6)
        #expect(abs((thin.boundsMin.x - thick.boundsMin.x) - h) < 1e-6)
    }

    @Test func coloringFollowsTheSourceAndThePattern() throws {
        // Every source has its own texture and uv rule (DESIGN 11.6).
        let expected: [ColorSource: (ColorTexture, FrameColorMode)] = [
            .uniform: (.uniform, .uniform), .byW: (.byW, .byW),
            .perCell: (.palette, .palette(count: ColorTexture.paletteCount)),
            .surfaceParameter: (.checkerboard, .surfaceParameter), .perFibre: (.hue, .curveKey),
        ]
        for source in ColorSource.allCases {
            let e = try #require(expected[source])
            #expect(Coloring(source) == Coloring(texture: e.0, mode: e.1), "\(source)")
            #expect(Coloring.faces(source: source, pattern: .none) == Coloring(source))
            #expect(Coloring.edges(source: source, edgeColor: .matchFaces) == Coloring(source))
            #expect(Coloring.edges(source: source, edgeColor: .light) == Coloring(texture: .light, mode: .uniform))
            // D24: a pattern replaces the colour on the faces only.
            #expect(Coloring.faces(source: source, pattern: .marble) == Coloring(texture: .marble, mode: .pattern))
        }
        #expect(ColorTexture.allCases.filter(\.isPattern) == [.grid, .marble, .wood])
        #expect(ColorTexture.allCases.filter(\.usesNearestFilter) == [.palette])
    }

    @Test func launchArgumentsSetPatternThicknessAndStyle() {
        let config = LaunchConfiguration.parse(["pattern": "marble", "faceThickness": "0.5", "style": "frosted"])
        #expect(config.state.display.pattern == .marble)
        #expect(config.state.display.faceThickness == DisplaySettings.faceThicknessRange.upperBound)
        #expect(config.state.display.faceStyle == .frostedGlass)
        #expect(LaunchConfiguration.parse(["pattern": "plaid"]).problems == ["pattern=plaid"])
        #expect(ViewState().display.pattern == SurfacePattern.none && ViewState().display.faceThickness == 0)
    }
}
