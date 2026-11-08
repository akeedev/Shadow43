// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// A polygon of a complex, vertices in cyclic order.
public struct Face: Equatable, Sendable {
    public var vertices: [Int]
    /// The cells this face bounds: exactly two for polytopes, empty otherwise.
    public var cells: [Int]

    public init(vertices: [Int], cells: [Int] = []) {
        self.vertices = vertices
        self.cells = cells
    }
}

/// A closed 3D boundary body of a polytope.
public struct Cell: Equatable, Sendable {
    public var faces: [Int]
    public var center: SIMD4<Double>

    public init(faces: [Int], center: SIMD4<Double>) {
        self.faces = faces
        self.center = center
    }
}

/// The common data model for every object (DESIGN 3.1, 6.2): exact combinatorics, built once.
public struct Complex4D: Sendable {
    /// Points in ℝ⁴, centred, circumradius 1.
    public var vertices: [SIMD4<Double>]
    /// Polylines; two indices each for polytopes.
    public var edges: [[Int]]
    public var faces: [Face]
    /// Polytopes only, otherwise empty.
    public var cells: [Cell]
    /// Parametric surfaces only: (u, v) per vertex, each in [0, 1].
    public var uv: [SIMD2<Double>]?
    /// Curve families only: colour key (base point of the fibre) per vertex, in [0, 1].
    public var curveKey: [Double]?
    public var kind: ObjectKind

    public init(vertices: [SIMD4<Double>], edges: [[Int]], faces: [Face], cells: [Cell] = [],
                uv: [SIMD2<Double>]? = nil, curveKey: [Double]? = nil, kind: ObjectKind) {
        self.vertices = vertices
        self.edges = edges
        self.faces = faces
        self.cells = cells
        self.uv = uv
        self.curveKey = curveKey
        self.kind = kind
    }

    /// (vertices, edges, faces, cells).
    public var fVector: [Int] { [vertices.count, edges.count, faces.count, cells.count] }

    /// vertices − edges + faces − cells; 0 for every convex 4-polytope.
    public var eulerCharacteristic: Int { vertices.count - edges.count + faces.count - cells.count }

    /// The vertex indices of a cell, without duplicates.
    public func vertexIndices(ofCell c: Int) -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for f in cells[c].faces {
            for v in faces[f].vertices where seen.insert(v).inserted { result.append(v) }
        }
        return result
    }

    /// The undirected edges (sorted index pairs) of a cell, without duplicates.
    public func edgePairs(ofCell c: Int) -> [EdgeKey] {
        var seen = Set<EdgeKey>()
        var result: [EdgeKey] = []
        for f in cells[c].faces {
            let vs = faces[f].vertices
            for i in vs.indices {
                let key = EdgeKey(vs[i], vs[(i + 1) % vs.count])
                if seen.insert(key).inserted { result.append(key) }
            }
        }
        return result
    }
}

/// An undirected edge, stored with the smaller index first.
public struct EdgeKey: Hashable, Sendable {
    public let a: Int
    public let b: Int

    public init(_ i: Int, _ j: Int) {
        a = min(i, j)
        b = max(i, j)
    }
}

/// Centres a point set at the origin and scales it to circumradius 1.
public func normalizeToUnitCircumradius(_ points: [SIMD4<Double>]) -> [SIMD4<Double>] {
    guard !points.isEmpty else { return points }
    let centroid = points.reduce(SIMD4<Double>.zero, +) / Double(points.count)
    let centred = points.map { $0 - centroid }
    let radius = centred.map { simd_length($0) }.max() ?? 1
    return radius > 0 ? centred.map { $0 / radius } : centred
}
