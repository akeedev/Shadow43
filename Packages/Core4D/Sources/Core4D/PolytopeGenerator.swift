// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Builds the full complex of a convex 4-polytope from its vertices and facet normals
/// (DESIGN 6.6).
public enum PolytopeGenerator {
    /// 1. Centre and scale the vertices to circumradius 1.
    /// 2. For each normal n, the cell's vertex set is `{ i : v_i·n ≥ max_j(v_j·n) − ε }`.
    /// 3. Two cells that share at least 3 affinely 2-dimensional vertices share a face; its
    ///    vertices are ordered by angle around the centroid in the face plane.
    /// 4. Edges are the sides of the face polygons, without duplicates.
    /// 5. A cell consists of its faces; its centre is the centroid of its vertices.
    public static func complex(vertices rawVertices: [SIMD4<Double>], normals: [SIMD4<Double>],
                               tolerance: Double = 1e-6) -> Complex4D {
        let vertices = normalizeToUnitCircumradius(rawVertices)

        // Step 2: vertex set per cell.
        var cellVertices: [[Int]] = []
        for n in normals {
            let dots = vertices.map { simd_dot($0, n) }
            let maxDot = dots.max() ?? 0
            let eps = tolerance * max(1, simd_length(n))
            cellVertices.append(dots.indices.filter { dots[$0] >= maxDot - eps })
        }

        // Step 3: faces from pairs of cells that share ≥ 3 vertices (via vertex → cell incidence).
        var cellsOfVertex = [[Int]](repeating: [], count: vertices.count)
        for (c, vs) in cellVertices.enumerated() {
            for v in vs { cellsOfVertex[v].append(c) }
        }
        var faces: [Face] = []
        var facesOfCell = [[Int]](repeating: [], count: cellVertices.count)
        var shared = [Int](repeating: 0, count: cellVertices.count)
        for a in cellVertices.indices {
            var touched: [Int] = []
            for v in cellVertices[a] {
                for b in cellsOfVertex[v] where b > a {
                    if shared[b] == 0 { touched.append(b) }
                    shared[b] += 1
                }
            }
            for b in touched.sorted() {
                defer { shared[b] = 0 }
                guard shared[b] >= 3 else { continue }
                let common = Set(cellVertices[a]).intersection(cellVertices[b]).sorted()
                guard affineDimension(common.map { vertices[$0] }, tolerance: tolerance) == 2 else {
                    continue
                }
                let ordered = orderCyclically(common, in: vertices)
                facesOfCell[a].append(faces.count)
                facesOfCell[b].append(faces.count)
                faces.append(Face(vertices: ordered, cells: [a, b]))
            }
        }

        // Step 4: edges.
        var edgeSet = Set<EdgeKey>()
        var edges: [[Int]] = []
        for f in faces {
            let vs = f.vertices
            for i in vs.indices {
                let key = EdgeKey(vs[i], vs[(i + 1) % vs.count])
                if edgeSet.insert(key).inserted { edges.append([key.a, key.b]) }
            }
        }

        // Step 5: cells.
        let cells = cellVertices.indices.map { c in
            let centre = cellVertices[c].reduce(SIMD4<Double>.zero) { $0 + vertices[$1] }
                / Double(max(1, cellVertices[c].count))
            return Cell(faces: facesOfCell[c], center: centre)
        }

        return Complex4D(vertices: vertices, edges: edges, faces: faces, cells: cells, kind: .polytope)
    }

    /// Dimension of the affine hull of a point set (0…4).
    static func affineDimension(_ points: [SIMD4<Double>], tolerance: Double) -> Int {
        guard let first = points.first else { return -1 }
        var basis: [SIMD4<Double>] = []
        for p in points.dropFirst() {
            var v = p - first
            for b in basis { v -= simd_dot(v, b) * b }
            let len = simd_length(v)
            if len > tolerance * 100 { basis.append(v / len) }
        }
        return basis.count
    }

    /// Orders the vertices of a planar polygon by angle around their centroid.
    static func orderCyclically(_ indices: [Int], in vertices: [SIMD4<Double>]) -> [Int] {
        let points = indices.map { vertices[$0] }
        let centroid = points.reduce(SIMD4<Double>.zero, +) / Double(points.count)
        // Orthonormal basis (e1, e2) of the face plane.
        let e1 = simd_normalize(points[0] - centroid)
        var e2 = SIMD4<Double>.zero
        for p in points.dropFirst() {
            var v = p - centroid
            v -= simd_dot(v, e1) * e1
            if simd_length(v) > 1e-9 {
                e2 = simd_normalize(v)
                break
            }
        }
        let angles = points.map { p -> Double in
            let d = p - centroid
            return atan2(simd_dot(d, e2), simd_dot(d, e1))
        }
        return indices.indices.sorted { angles[$0] < angles[$1] }.map { indices[$0] }
    }
}
