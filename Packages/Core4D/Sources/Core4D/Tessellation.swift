// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Render-ready, static geometry in ℝ⁴ (DESIGN 6.2). Rebuilt only when the object, explode or
/// subdivision changes; everything per frame happens in `FrameBuilder`.
public struct RenderMesh4D: Sendable {
    /// Points with their flat and spherized positions and a static colour key.
    public struct PointSet: Sendable {
        /// Points after explode and subdivision.
        public var flat: [SIMD4<Float>] = []
        /// The same points normalised onto S³.
        public var sphere: [SIMD4<Float>] = []
        /// Static colour key: x = cell index, surface u or fibre key; y = surface v.
        public var colorKey: [SIMD2<Float>] = []

        public var count: Int { flat.count }

        mutating func append(_ p: SIMD4<Double>, key: SIMD2<Float>) {
            flat.append(SIMD4<Float>(p))
            let len = simd_length(p)
            sphere.append(SIMD4<Float>(len > 0 ? p / len : p))
            colorKey.append(key)
        }
    }

    public var facePoints = PointSet()
    /// Pattern coordinates of every face point (D24), fixed on the object: for polygons the
    /// point's position in the polygon's own plane, for surfaces the scaled surface parameters.
    /// One texture repeat is `Tessellation.patternUnit` object units.
    public var facePatternUV: [SIMD2<Float>] = []
    /// Three indices into `facePoints` per triangle. Within a polygon (or a surface) all triangles
    /// have the same orientation, so normals that follow the winding are consistent (D16).
    public var triangles: [UInt32] = []
    /// Point and triangle ranges of each polygon (contiguous by construction). Surfaces have one
    /// point range for the whole grid and one triangle range per quad.
    public var polygonPointRanges: [Range<Int>] = []
    public var polygonTriangleRanges: [Range<Int>] = []

    public var edgePoints = PointSet()
    /// Indices into `edgePoints`.
    public var polylines: [[UInt32]] = []

    /// Cell groups (explode > 0 only): point and triangle ranges of every cell, and its centre.
    public var groupPointRanges: [Range<Int>] = []
    public var groupTriangleRanges: [Range<Int>] = []
    public var groupCenters = PointSet()

    public var triangleCount: Int { triangles.count / 3 }

    public init() {}
}

/// Subdivision levels (DESIGN 6.4): edges into n segments, polygons as a fan around the
/// centroid with m² subdivision.
public struct TessellationOptions: Equatable, Sendable {
    public var edgeSegments: Int
    public var faceSubdivision: Int
    /// For parametric surfaces: every k-th grid line becomes an edge.
    public var surfaceEdgeStride: Int

    public init(edgeSegments: Int = 8, faceSubdivision: Int = 3, surfaceEdgeStride: Int = 4) {
        self.edgeSegments = edgeSegments
        self.faceSubdivision = faceSubdivision
        self.surfaceEdgeStride = surfaceEdgeStride
    }

    /// Smooth arcs are only needed when s > 0, because the projection maps lines to lines.
    /// Large polytopes get coarser levels.
    public static func recommended(for complex: Complex4D, spherize: Double) -> TessellationOptions {
        guard spherize > 0 else { return TessellationOptions(edgeSegments: 1, faceSubdivision: 1) }
        switch complex.edges.count {
        case ..<200: return TessellationOptions(edgeSegments: 8, faceSubdivision: 3)
        case ..<1000: return TessellationOptions(edgeSegments: 6, faceSubdivision: 2)
        default: return TessellationOptions(edgeSegments: 5, faceSubdivision: 2)
        }
    }
}

/// Turns a `Complex4D` into a `RenderMesh4D`.
public enum Tessellation {
    /// Object units per pattern repeat on polygons: four repeats along a tesseract edge.
    public static let patternUnit = 0.25
    /// Pattern repeats along each surface parameter (u and v run over 0…1).
    public static let surfacePatternRepeats: Float = 8

    /// - Parameters:
    ///   - explode: fraction e; each cell shrinks towards its centre, `v' = c + (1 − e)(v − c)`.
    ///     With e > 0 every cell gets its own faces and edges. Applied before spherizing.
    public static func renderMesh(for complex: Complex4D, explode: Double,
                                  options: TessellationOptions) -> RenderMesh4D {
        switch complex.kind {
        case .polytope: polytopeMesh(complex, explode: explode, options: options)
        case .surface: surfaceMesh(complex, options: options)
        case .curves: curveMesh(complex, options: options)
        }
    }

    // MARK: Polytopes

    static func polytopeMesh(_ c: Complex4D, explode: Double, options: TessellationOptions) -> RenderMesh4D {
        var mesh = RenderMesh4D()
        let n = max(1, options.edgeSegments)
        let m = max(1, options.faceSubdivision)
        if explode > 0, !c.cells.isEmpty {
            for (ci, cell) in c.cells.enumerated() {
                let shrink = { (v: SIMD4<Double>) in cell.center + (1 - explode) * (v - cell.center) }
                let key = SIMD2<Float>(Float(ci), 0)
                let pointStart = mesh.facePoints.count
                let triStart = mesh.triangleCount
                for f in cell.faces {
                    addPolygon(c.faces[f].vertices.map { shrink(c.vertices[$0]) }, key: key,
                               subdivision: m, to: &mesh)
                }
                mesh.groupPointRanges.append(pointStart..<mesh.facePoints.count)
                mesh.groupTriangleRanges.append(triStart..<mesh.triangleCount)
                mesh.groupCenters.append(cell.center, key: key)
                for e in c.edgePairs(ofCell: ci) {
                    addSegment(shrink(c.vertices[e.a]), shrink(c.vertices[e.b]), key: key,
                               segments: n, to: &mesh)
                }
            }
        } else {
            for f in c.faces {
                let key = SIMD2<Float>(Float(f.cells.first ?? 0), 0)
                addPolygon(f.vertices.map { c.vertices[$0] }, key: key, subdivision: m, to: &mesh)
            }
            for e in c.edges {
                for k in 0..<(e.count - 1) {
                    addSegment(c.vertices[e[k]], c.vertices[e[k + 1]], key: .zero, segments: n, to: &mesh)
                }
            }
        }
        return mesh
    }

    /// A polygon as a fan around its centroid; each fan triangle is subdivided into m² triangles.
    /// Points are shared within the polygon, so its normals are smooth.
    static func addPolygon(_ corners: [SIMD4<Double>], key: SIMD2<Float>, subdivision m: Int,
                           to mesh: inout RenderMesh4D) {
        let count = corners.count
        guard count >= 3 else { return }
        let centre = corners.reduce(SIMD4<Double>.zero, +) / Double(count)
        let base = mesh.facePoints.count
        let triStart = mesh.triangleCount
        let (e1, e2) = planeBasis(corners, centre: centre)
        func addPoint(_ p: SIMD4<Double>) {
            mesh.facePoints.append(p, key: key)
            let d = p - centre
            mesh.facePatternUV.append(SIMD2<Float>(SIMD2(simd_dot(d, e1), simd_dot(d, e2)) / patternUnit))
        }

        // Points: centre, then ring r = 1…m with r·count points each. Ring r, position q lies on
        // fan triangle i = q / r at offset k = q % r from corner i towards corner i+1.
        addPoint(centre)
        for r in 1...m {
            let t = Double(r) / Double(m)
            for q in 0..<(r * count) {
                let i = q / r
                let k = Double(q % r) / Double(r)
                let a = corners[i]
                let b = corners[(i + 1) % count]
                let onRing = a + k * (b - a)
                addPoint(centre + t * (onRing - centre))
            }
        }
        func index(ring r: Int, position q: Int) -> UInt32 {
            if r == 0 { return UInt32(base) }
            // Offset of ring r: 1 + count·(1 + 2 + … + (r − 1)).
            let offset = 1 + count * (r - 1) * r / 2
            return UInt32(base + offset + (q % (r * count)))
        }
        // Triangles of fan triangle i: grid (j, k) with j steps outwards and k steps along.
        for i in 0..<count {
            for r in 0..<m {
                for k in 0...r {
                    // Upward triangle: (r, k) – (r + 1, k) – (r + 1, k + 1).
                    let a = index(ring: r, position: i * r + k)
                    let b = index(ring: r + 1, position: i * (r + 1) + k)
                    let c = index(ring: r + 1, position: i * (r + 1) + k + 1)
                    mesh.triangles += [a, b, c]
                    if k < r {
                        // Downward triangle: (r, k) – (r + 1, k + 1) – (r, k + 1).
                        let d = index(ring: r, position: i * r + k + 1)
                        mesh.triangles += [a, c, d]
                    }
                }
            }
        }
        mesh.polygonPointRanges.append(base..<mesh.facePoints.count)
        mesh.polygonTriangleRanges.append(triStart..<mesh.triangleCount)
    }

    /// An orthonormal basis of a planar polygon's plane in ℝ⁴: the direction of the first edge (so a
    /// grid runs parallel to it), and the part of the direction to the corner farthest from that
    /// line that is orthogonal to it.
    static func planeBasis(_ corners: [SIMD4<Double>], centre: SIMD4<Double>)
        -> (SIMD4<Double>, SIMD4<Double>) {
        let first = corners[1] - corners[0]
        let e1 = simd_length(first) > 0 ? simd_normalize(first) : SIMD4(1, 0, 0, 0)
        var best = SIMD4<Double>.zero
        for c in corners.dropFirst() {
            let d = c - centre
            let orthogonal = d - simd_dot(d, e1) * e1
            if simd_length(orthogonal) > simd_length(best) { best = orthogonal }
        }
        let e2 = simd_length(best) > 1e-12 ? simd_normalize(best) : SIMD4(0, 1, 0, 0)
        return (e1, e2)
    }

    /// A straight segment in ℝ⁴ as a polyline of n pieces; on S³ it becomes a great-circle arc.
    static func addSegment(_ a: SIMD4<Double>, _ b: SIMD4<Double>, key: SIMD2<Float>, segments n: Int,
                           to mesh: inout RenderMesh4D) {
        var line: [UInt32] = []
        for k in 0...n {
            line.append(UInt32(mesh.edgePoints.count))
            mesh.edgePoints.append(a + (Double(k) / Double(n)) * (b - a), key: key)
        }
        mesh.polylines.append(line)
    }

    // MARK: Surfaces and curves

    /// Parametric surfaces: the complex is a grid whose faces are quads; points are shared so the
    /// surface is smooth. Seam points are duplicated, so the Klein bottle's orientation reversal
    /// shows as a lighting crease along its seam instead of cancelling normals. Edges are the
    /// complex's polylines.
    static func surfaceMesh(_ c: Complex4D, options: TessellationOptions) -> RenderMesh4D {
        var mesh = RenderMesh4D()
        let uv = c.uv ?? Array(repeating: .zero, count: c.vertices.count)
        for (i, v) in c.vertices.enumerated() {
            mesh.facePoints.append(v, key: SIMD2<Float>(uv[i]))
            mesh.facePatternUV.append(SIMD2<Float>(uv[i]) * surfacePatternRepeats)
        }
        for f in c.faces {
            let vs = f.vertices.map(UInt32.init)
            let start = mesh.triangleCount
            for k in 1..<(vs.count - 1) { mesh.triangles += [vs[0], vs[k], vs[k + 1]] }
            mesh.polygonTriangleRanges.append(start..<mesh.triangleCount)
        }
        mesh.polygonPointRanges = [0..<mesh.facePoints.count]
        addPolylines(c, keys: uv.map { SIMD2<Float>($0) }, to: &mesh)
        return mesh
    }

    /// Curve families: only polylines; the colour key is the curve key.
    static func curveMesh(_ c: Complex4D, options: TessellationOptions) -> RenderMesh4D {
        var mesh = RenderMesh4D()
        let keys = (c.curveKey ?? Array(repeating: 0, count: c.vertices.count)).map { SIMD2<Float>(Float($0), 0) }
        addPolylines(c, keys: keys, to: &mesh)
        return mesh
    }

    static func addPolylines(_ c: Complex4D, keys: [SIMD2<Float>], to mesh: inout RenderMesh4D) {
        for e in c.edges where e.count >= 2 {
            var line: [UInt32] = []
            for v in e {
                line.append(UInt32(mesh.edgePoints.count))
                mesh.edgePoints.append(c.vertices[v], key: keys[v])
            }
            mesh.polylines.append(line)
        }
    }
}
