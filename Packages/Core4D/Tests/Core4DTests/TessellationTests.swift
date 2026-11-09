// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

@Suite("Tessellation and frame pipeline")
struct TessellationTests {
    @Test(arguments: [1, 2, 3, 4])
    func polygonSubdivisionCounts(_ m: Int) {
        let c = Fixtures.tesseract
        let mesh = Tessellation.renderMesh(for: c, explode: 0,
                                           options: TessellationOptions(edgeSegments: 8, faceSubdivision: m))
        // A square: 4 fan triangles with m² triangles each; 1 + 4·m(m+1)/2 points.
        #expect(mesh.triangleCount == c.faces.count * 4 * m * m)
        #expect(mesh.facePoints.count == c.faces.count * (1 + 4 * m * (m + 1) / 2))
        #expect(mesh.polylines.count == c.edges.count)
        #expect(mesh.edgePoints.count == c.edges.count * 9)
        #expect(mesh.triangles.allSatisfy { Int($0) < mesh.facePoints.count })
    }

    @Test func subdividedPointsStayInTheirPolygonAndTrianglesAreConsistent() {
        let c = Fixtures.fiveCell
        let mesh = Tessellation.renderMesh(for: c, explode: 0, options: TessellationOptions(faceSubdivision: 3))
        for (k, range) in mesh.polygonPointRanges.enumerated() {
            let corners = c.faces[k].vertices.map { SIMD4<Float>(c.vertices[$0]) }
            for i in range {
                // Each point is an affine combination of the corners: check it lies in their span.
                let p = mesh.facePoints.flat[i] - corners[0]
                let e1 = simd_normalize(corners[1] - corners[0])
                var e2 = corners[2] - corners[0]
                e2 = simd_normalize(e2 - simd_dot(e2, e1) * e1)
                let residual = p - simd_dot(p, e1) * e1 - simd_dot(p, e2) * e2
                #expect(simd_length(residual) < 1e-5)
            }
            // All triangles of a polygon have the same orientation in its plane.
            let tri = mesh.polygonTriangleRanges[k]
            let normals = tri.map { t -> Float in
                let a = mesh.facePoints.flat[Int(mesh.triangles[3 * t])]
                let b = mesh.facePoints.flat[Int(mesh.triangles[3 * t + 1])]
                let cc = mesh.facePoints.flat[Int(mesh.triangles[3 * t + 2])]
                let e1 = corners[1] - corners[0], e2 = corners[2] - corners[0]
                // Signed area in the (e1, e2) frame.
                let u = SIMD2(simd_dot(b - a, e1), simd_dot(b - a, e2))
                let v = SIMD2(simd_dot(cc - a, e1), simd_dot(cc - a, e2))
                return u.x * v.y - u.y * v.x
            }
            #expect(normals.allSatisfy { $0 > 0 } || normals.allSatisfy { $0 < 0 })
        }
    }

    @Test func explodeShrinksEveryCellTowardsItsCentre() {
        let c = Fixtures.tesseract
        let e = 0.2
        let mesh = Tessellation.renderMesh(for: c, explode: e, options: TessellationOptions(edgeSegments: 1, faceSubdivision: 1))
        #expect(mesh.groupPointRanges.count == c.cells.count)
        #expect(mesh.polylines.count == c.cells.count * 12)
        for (g, range) in mesh.groupPointRanges.enumerated() {
            let centre = SIMD4<Float>(c.cells[g].center)
            for i in range {
                let p = mesh.facePoints.flat[i]
                #expect(mesh.facePoints.colorKey[i].x == Float(g))
                // Cube cells: corners at distance 1 from the centre ⇒ shrunk to ≤ 1 − e.
                #expect(simd_distance(p, centre) <= Float(1 - e) + 1e-5)
            }
        }
    }

    @Test func sphereIsTheNormalisedFlatPoint() {
        let mesh = Tessellation.renderMesh(for: Fixtures.twentyFourCell, explode: 0, options: TessellationOptions())
        for i in stride(from: 0, to: mesh.facePoints.count, by: 7) {
            #expect(abs(simd_length(mesh.facePoints.sphere[i]) - 1) < 1e-5)
            let cosAngle = simd_dot(simd_normalize(mesh.facePoints.flat[i]), mesh.facePoints.sphere[i])
            #expect(cosAngle > 0.99999)
        }
    }

    @Test func orthographicIdentityFrameReturnsXYZ() {
        let c = Fixtures.tesseract
        let mesh = Tessellation.renderMesh(for: c, explode: 0, options: TessellationOptions(edgeSegments: 1, faceSubdivision: 1))
        let builder = FrameBuilder(mesh: mesh)
        builder.update(FrameParameters(kappa: 0, spherize: 0, faceColors: .byW))
        for i in 0..<mesh.facePoints.count {
            let f = mesh.facePoints.flat[i]
            #expect(simd_distance(builder.faceVertices[i].position, SIMD3(f.x, f.y, f.z)) < 1e-6)
            #expect(abs(builder.faceVertices[i].uv.x - min(max((f.w + 1) / 2, 0.002), 0.998)) < 1e-6)
            #expect(abs(simd_length(builder.faceVertices[i].normal) - 1) < 1e-4)
        }
        // Every triangle twice: front copy and back copy.
        #expect(builder.faceIndexCount == 2 * mesh.triangles.count)
        #expect(builder.edgeIndexCount == builder.edgeIndexCapacity)
        #expect(builder.edgeVertexCount == builder.edgeVertexCapacity)
        #expect(builder.boundsMax.x > 0.49 && builder.boundsMin.x < -0.49)
    }

    @Test func pointsNearTheEyeAreCulled() {
        // Stereographic projection of the tesseract with R = identity: no point reaches the pole.
        let c = Fixtures.tesseract
        let mesh = Tessellation.renderMesh(for: c, explode: 0, options: TessellationOptions())
        let builder = FrameBuilder(mesh: mesh)
        builder.update(FrameParameters(kappa: 1, spherize: 1))
        #expect(builder.faceIndexCount == 2 * mesh.triangles.count)
        // Rotate a vertex direction onto the north pole: triangles around it are culled.
        let v = simd_normalize(SIMD4<Double>(c.vertices[0]))
        let r = rotationTaking(v, to: [0, 0, 0, 1])
        var p = FrameParameters(kappa: 1, spherize: 1)
        p.rotation = Rotation4D.float(r)
        builder.update(p)
        #expect(builder.faceIndexCount < 2 * mesh.triangles.count)
        #expect(builder.faceIndexCount > 0)
        #expect(builder.edgeIndexCount < builder.edgeIndexCapacity)
        for i in 0..<builder.faceIndexCount {
            let q = builder.faceVertices[Int(builder.faceIndices[i])].position
            #expect(simd_length(q) <= p.maxRadius)
        }
    }

    @Test func sortedTrianglesGoBackToFront() {
        let mesh = Tessellation.renderMesh(for: Fixtures.twentyFourCell, explode: 0, options: TessellationOptions(faceSubdivision: 1))
        let builder = FrameBuilder(mesh: mesh)
        var p = FrameParameters(kappa: 0.6)
        p.rotation = Rotation4D.float(Rotation4D.plane(.xw, angle: 0.4) * Rotation4D.plane(.yz, angle: 0.3))
        p.sortFaces = true
        builder.update(p)
        var last = -Float.infinity
        for t in 0..<(builder.faceIndexCount / 3) {
            let z = (0..<3).map { builder.faceVertices[Int(builder.faceIndices[3 * t + $0])].position.z }.reduce(0, +)
            #expect(z >= last - 1e-5)
            last = z
        }
    }

    @Test func cellWindingPointsOutwards() {
        let c = Fixtures.tesseract
        let mesh = Tessellation.renderMesh(for: c, explode: 0.2, options: TessellationOptions(edgeSegments: 1, faceSubdivision: 1))
        let builder = FrameBuilder(mesh: mesh)
        var p = FrameParameters(kappa: 0.6, orientCellFaces: true)
        p.rotation = Rotation4D.float(Rotation4D.plane(.xw, angle: 0.5))
        builder.update(p)
        #expect(builder.groupIndexRanges.count == c.cells.count)
        #expect(builder.groupBackIndexRanges.count == c.cells.count)
        for (g, range) in builder.groupIndexRanges.enumerated() {
            let centreFlat = mesh.groupCenters.flat[g]
            let r = p.rotation * centreFlat
            let centre = SIMD3(r.x, r.y, r.z) / (1 - p.kappa * r.w)
            // Front copies wind outwards and their normals point outwards; back copies inwards.
            for (indices, sign) in [(range, Float(1)), (builder.groupBackIndexRanges[g], Float(-1))] {
                #expect(indices.count == range.count)
                for t in stride(from: indices.lowerBound, to: indices.upperBound, by: 3) {
                    let va = builder.faceVertices[Int(builder.faceIndices[t])]
                    let a = va.position
                    let b = builder.faceVertices[Int(builder.faceIndices[t + 1])].position
                    let cc = builder.faceVertices[Int(builder.faceIndices[t + 2])].position
                    let outwards = (a + b + cc) / 3 - centre
                    #expect(sign * simd_dot(simd_cross(b - a, cc - a), outwards) > 0)
                    #expect(sign * simd_dot(va.normal, outwards) > 0)
                }
            }
        }
    }

    /// The core of D16: seen from any direction, exactly one copy of each triangle faces the
    /// viewer, and that copy's normals point towards the viewer.
    @Test(arguments: [SIMD3<Float>(0, 0, 1), [0, 0, -1], [1, 0, 0], [-1, 0, 0], [0, 1, 0],
                      [0.3, -0.5, -0.8]])
    func theVisibleCopyIsLitFromTheViewersSide(_ view: SIMD3<Float>) {
        let mesh = Tessellation.renderMesh(for: Fixtures.twentyFourCell, explode: 0,
                                           options: TessellationOptions(edgeSegments: 1, faceSubdivision: 1))
        let builder = FrameBuilder(mesh: mesh)
        var p = FrameParameters(kappa: 0.6)
        p.rotation = Rotation4D.float(Rotation4D.plane(.xw, angle: 0.4) * Rotation4D.plane(.yz, angle: 0.3))
        builder.update(p)
        let d = simd_normalize(view)
        let idx = builder.faceIndices
        for t in stride(from: 0, to: builder.faceIndexCount, by: 6) {
            var facing: [Int] = []
            for copy in [t, t + 3] {
                let va = builder.faceVertices[Int(idx[copy])]
                let b = builder.faceVertices[Int(idx[copy + 1])].position
                let c = builder.faceVertices[Int(idx[copy + 2])].position
                let n = simd_cross(b - va.position, c - va.position)
                let len = simd_length(n)
                guard len > 1e-6, abs(simd_dot(n / len, d)) > 1e-3 else { continue }
                if simd_dot(n, d) > 0 {
                    facing.append(copy)
                    // Flat polygons (s = 0): the vertex normals are the polygon normal.
                    for k in 0..<3 { #expect(simd_dot(builder.faceVertices[Int(idx[copy + k])].normal, d) > 0) }
                }
            }
            #expect(facing.count <= 1)
        }
    }

    @Test func surfaceNormalsStayFiniteAcrossTheKleinBottleSeam() {
        let c = Surfaces.kleinBottle(nU: 24, nV: 12, edgeStride: 6)
        let mesh = Tessellation.renderMesh(for: c, explode: 0, options: TessellationOptions())
        let builder = FrameBuilder(mesh: mesh)
        var p = FrameParameters(kappa: 0.5)
        p.rotation = Rotation4D.float(Rotation4D.plane(.xw, angle: 0.7))
        builder.update(p)
        for v in builder.faceVertices {
            #expect(v.normal.x.isFinite && v.normal.y.isFinite && v.normal.z.isFinite)
            #expect(abs(simd_length(v.normal) - 1) < 1e-3)
        }
    }

    @Test func tubesHaveSixSidedRingsAndUnitNormals() {
        let mesh = Tessellation.renderMesh(for: Fixtures.fiveCell, explode: 0, options: TessellationOptions(edgeSegments: 4))
        let builder = FrameBuilder(mesh: mesh)
        var p = FrameParameters(kappa: 0.5, spherize: 1)
        p.edgeRadius = 0.02
        builder.update(p, faces: false, edges: true)
        #expect(builder.faceIndexCount == 0)
        #expect(builder.edgeVertexCount == mesh.polylines.count * 5 * 6)
        for i in 0..<builder.edgeVertexCount {
            #expect(abs(simd_length(builder.edgeVertices[i].normal) - 1) < 1e-4)
        }
        #expect(builder.edgeIndices[0..<builder.edgeIndexCount].allSatisfy { Int($0) < builder.edgeVertexCount })
    }

    @Test func backCopiesHaveReversedWindingAndNegatedNormals() {
        let mesh = Tessellation.renderMesh(for: Fixtures.fiveCell, explode: 0, options: TessellationOptions(faceSubdivision: 1))
        let builder = FrameBuilder(mesh: mesh)
        builder.update(FrameParameters(kappa: 0.3))
        let n = UInt32(builder.backVertexOffset)
        #expect(builder.backVertexOffset == mesh.facePoints.count)
        #expect(builder.faceVertexCount == 2 * mesh.facePoints.count)
        #expect(builder.faceIndexCount == 2 * mesh.triangles.count)
        let i = builder.faceIndices
        for t in stride(from: 0, to: builder.faceIndexCount, by: 6) {
            #expect(i[t + 3] == i[t] + n && i[t + 4] == i[t + 2] + n && i[t + 5] == i[t + 1] + n)
        }
        for k in 0..<builder.backVertexOffset {
            let front = builder.faceVertices[k], back = builder.faceVertices[k + builder.backVertexOffset]
            #expect(front.position == back.position && front.uv == back.uv)
            #expect(front.normal == -back.normal)
        }
    }

    @Test func paletteAndCurveColourModes() {
        #expect(FrameColorMode.palette(count: 4).uv(key: [5, 0], w: 0).x == 0.375)
        #expect(FrameColorMode.uniform.uv(key: [5, 0], w: 0) == SIMD2(0.5, 0.5))
        #expect(FrameColorMode.surfaceParameter.uv(key: [0.25, 0.75], w: 0) == SIMD2(0.25, 0.75))
        #expect(FrameColorMode.curveKey.uv(key: [0.3, 0], w: 0).x == 0.3)
    }

    @Test func recommendedSubdivisionDependsOnSpherizeAndSize() {
        let flat = TessellationOptions.recommended(for: Fixtures.oneTwentyCell, spherize: 0)
        #expect(flat == TessellationOptions(edgeSegments: 1, faceSubdivision: 1))
        // Under 200 edges, under 1000, and more (DESIGN 10.4).
        #expect(TessellationOptions.recommended(for: Fixtures.twentyFourCell, spherize: 0.5)
            == TessellationOptions(edgeSegments: 8, faceSubdivision: 3))
        #expect(TessellationOptions.recommended(for: Fixtures.sixHundredCell, spherize: 1)
            == TessellationOptions(edgeSegments: 6, faceSubdivision: 2))
        #expect(TessellationOptions.recommended(for: Fixtures.oneTwentyCell, spherize: 1)
            == TessellationOptions(edgeSegments: 5, faceSubdivision: 2))
    }

    @Test func cellCentresIgnoreDroppedPoints() throws {
        // Per-cell entities sit at the centre of their cell's visible points.
        let c = Fixtures.tesseract
        let mesh = Tessellation.renderMesh(for: c, explode: 0.2, options: TessellationOptions(edgeSegments: 1, faceSubdivision: 2))
        let builder = FrameBuilder(mesh: mesh)
        builder.update(FrameParameters(kappa: 0, faceOffset: 0.01))
        for (g, cell) in c.cells.enumerated() {
            let found = try #require(builder.groupCentre(g))
            #expect(simd_distance(found.centre, SIMD3<Float>(Float(cell.center.x), Float(cell.center.y), Float(cell.center.z))) < 1e-5)
            #expect(found.min.x <= found.centre.x && found.centre.x <= found.max.x)
        }
        // With every point dropped there is no centre.
        builder.update(FrameParameters(maxRadius: 0.01))
        #expect(builder.groupCentre(0) == nil)
    }

    /// A rotation that maps the unit vector a onto the unit vector b (in the plane they span).
    func rotationTaking(_ a: SIMD4<Double>, to b: SIMD4<Double>) -> simd_double4x4 {
        var perp = b - simd_dot(b, a) * a
        perp = simd_normalize(perp)
        let angle = acos(min(1, max(-1, simd_dot(a, b))))
        return Rotation4D.plane(a: a, b: perp, angle: angle)
    }
}
