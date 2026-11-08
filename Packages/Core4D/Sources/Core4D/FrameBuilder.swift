// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// One vertex of the render meshes: 48 bytes, laid out like the `LowLevelMesh` attributes
/// (position at 0, normal at 16, uv at 32).
public struct MeshVertex: Sendable {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var uv: SIMD2<Float>

    public init(position: SIMD3<Float> = .zero, normal: SIMD3<Float> = .zero, uv: SIMD2<Float> = .zero) {
        self.position = position
        self.normal = normal
        self.uv = uv
    }
}

/// How the colour key becomes a texture coordinate (DESIGN 3.4, 6.5).
public enum FrameColorMode: Equatable, Sendable {
    /// One colour: the centre of the texture.
    case uniform
    /// u = (w + 1) / 2, every frame.
    case byW
    /// u = palette entry of the cell index (key.x) in a palette of `count` colours.
    case palette(count: Int)
    /// (u, v) = surface parameter (key), for a checkerboard texture.
    case surfaceParameter
    /// u = curve key (key.x), for a gradient texture.
    case curveKey
    /// The fixed pattern coordinates of the face points (`RenderMesh4D.facePatternUV`), for a
    /// repeating image pattern (D24). Faces only; edges treat it as uniform.
    case pattern

    @inline(__always)
    func uv(key: SIMD2<Float>, w: Float) -> SIMD2<Float> {
        switch self {
        case .uniform, .pattern: SIMD2(0.5, 0.5)
        case .byW: SIMD2(min(max((w + 1) * 0.5, 0.002), 0.998), 0.5)
        case .palette(let n):
            SIMD2((Float(Int(key.x) % max(1, n)) + 0.5) / Float(max(1, n)), 0.5)
        case .surfaceParameter: key
        case .curveKey: SIMD2(min(max(key.x, 0.002), 0.998), 0.5)
        }
    }
}

/// Everything the per-frame pipeline depends on (DESIGN 6.3).
public struct FrameParameters: Equatable, Sendable {
    public var rotation: simd_float4x4
    public var kappa: Float
    public var spherize: Float
    public var faceColors: FrameColorMode
    public var edgeColors: FrameColorMode
    /// Tube radius in object units.
    public var edgeRadius: Float
    /// Sort triangles back to front along `viewDirection` (transparency method "sorted").
    public var sortFaces: Bool
    /// Wind every cell's polygons outwards (transparency method "per-cell entities").
    public var orientCellFaces: Bool
    /// Unit vector from the content towards the viewer, used only for sorting. The window knows
    /// only which side of the volume the viewer is on (D17).
    public var viewDirection: SIMD3<Float>
    /// Points with `1 − κw < epsilon` are culled.
    public var epsilon: Float
    /// Points farther than this from the origin (object units) are culled.
    public var maxRadius: Float
    /// Half the face thickness in object units (D24): front copies move this far along their
    /// normal, back copies as far the other way, so every face becomes a slab. 0 = thin films.
    public var faceOffset: Float

    public init(rotation: simd_float4x4 = matrix_identity_float4x4, kappa: Float = 0, spherize: Float = 0,
                faceColors: FrameColorMode = .uniform, edgeColors: FrameColorMode = .uniform,
                edgeRadius: Float = 0.01, sortFaces: Bool = false, orientCellFaces: Bool = false,
                viewDirection: SIMD3<Float> = [0, 0, 1], epsilon: Float = 0.02, maxRadius: Float = 20,
                faceOffset: Float = 0) {
        self.rotation = rotation
        self.kappa = kappa
        self.spherize = spherize
        self.faceColors = faceColors
        self.edgeColors = edgeColors
        self.edgeRadius = edgeRadius
        self.sortFaces = sortFaces
        self.orientCellFaces = orientCellFaces
        self.viewDirection = viewDirection
        self.epsilon = epsilon
        self.maxRadius = maxRadius
        self.faceOffset = faceOffset
    }
}

/// Per-frame pipeline on the CPU (DESIGN 6.3, steps 2–5): rotate, spherize, project, cull,
/// recompute normals, build tubes and texture coordinates. Buffers are allocated once at their
/// maximum size and reused; the `…Count` properties say how much of them is in use.
///
/// Faces are double-sided with their own normals on each side (D16). `faceVertices` holds every
/// face point twice: first with the normal that matches the triangle winding (front copies), then,
/// from `backVertexOffset` on, with the negated normal (back copies). Every visible triangle is
/// emitted once per copy, the back copy with reversed winding. With back-face culling the GPU keeps
/// exactly the copy that faces the camera, so the lit side always faces the viewer, from any
/// direction, without knowing where the viewer is.
public final class FrameBuilder {
    public let mesh: RenderMesh4D
    public let tubeSides: Int

    public private(set) var faceVertices: [MeshVertex]
    /// Index of the first back copy in `faceVertices` (the number of face points).
    public let backVertexOffset: Int
    public private(set) var faceIndices: [UInt32]
    public private(set) var faceIndexCount = 0
    /// Range of each cell group's front copies in `faceIndices` (only when not sorted).
    public private(set) var groupIndexRanges: [Range<Int>] = []
    /// Range of each cell group's back copies in `faceIndices` (only when not sorted).
    public private(set) var groupBackIndexRanges: [Range<Int>] = []

    public private(set) var edgeVertices: [MeshVertex]
    public private(set) var edgeVertexCount = 0
    public private(set) var edgeIndices: [UInt32]
    public private(set) var edgeIndexCount = 0

    /// Bounds of the visible geometry (object units).
    public private(set) var boundsMin = SIMD3<Float>(repeating: 0)
    public private(set) var boundsMax = SIMD3<Float>(repeating: 0)

    private var faceValid: [Bool]
    private var edgePositions: [SIMD3<Float>]
    private var edgeW: [Float]
    private var edgeValid: [Bool]
    private var triangleNormals: [SIMD3<Float>]
    /// Per-cell winding (reused every frame): polygons and triangles that are emitted reversed.
    private var polygonFlip: [Bool]
    private var triangleFlip: [Bool]
    private struct SortKey {
        var depth: Float
        var triangle: Int32
    }
    private var sortKeys: [SortKey] = []
    /// Reused every frame: indices of the triangles that survive culling.
    private var visibleScratch: [Int32] = []
    private let ringDirections: [SIMD2<Float>]

    /// All face vertices are written every frame (front and back copies).
    public var faceVertexCount: Int { faceVertices.count }
    public var faceVertexCapacity: Int { faceVertices.count }
    public var faceIndexCapacity: Int { faceIndices.count }
    public var edgeVertexCapacity: Int { edgeVertices.count }
    public var edgeIndexCapacity: Int { edgeIndices.count }
    /// Triangles sent to the GPU, counting both copies of every face triangle.
    public var visibleTriangleCount: Int { (faceIndexCount + edgeIndexCount) / 3 }

    public init(mesh: RenderMesh4D, tubeSides: Int = 6) {
        self.mesh = mesh
        self.tubeSides = max(3, tubeSides)
        backVertexOffset = mesh.facePoints.count
        faceVertices = Array(repeating: MeshVertex(), count: 2 * mesh.facePoints.count)
        faceIndices = Array(repeating: 0, count: 2 * mesh.triangles.count)
        faceValid = Array(repeating: false, count: mesh.facePoints.count)
        triangleNormals = Array(repeating: .zero, count: mesh.triangleCount)
        polygonFlip = Array(repeating: false, count: mesh.polygonTriangleRanges.count)
        triangleFlip = Array(repeating: false, count: mesh.triangleCount)
        let sides = self.tubeSides
        let vertexCapacity = mesh.polylines.reduce(0) { $0 + $1.count * sides }
        let indexCapacity = mesh.polylines.reduce(0) { $0 + max(0, 6 * sides * $1.count - 12) }
        edgeVertices = Array(repeating: MeshVertex(), count: vertexCapacity)
        edgeIndices = Array(repeating: 0, count: indexCapacity)
        edgePositions = Array(repeating: .zero, count: mesh.edgePoints.count)
        edgeW = Array(repeating: 0, count: mesh.edgePoints.count)
        edgeValid = Array(repeating: false, count: mesh.edgePoints.count)
        ringDirections = (0..<sides).map { k in
            let a = 2 * Float.pi * Float(k) / Float(sides)
            return SIMD2(cos(a), sin(a))
        }
    }

    /// Runs the pipeline for faces and/or edges.
    public func update(_ p: FrameParameters, faces: Bool = true, edges: Bool = true) {
        var lo = SIMD3<Float>(repeating: .infinity)
        var hi = SIMD3<Float>(repeating: -.infinity)
        if faces {
            buildFaces(p, lo: &lo, hi: &hi)
        } else {
            faceIndexCount = 0
            groupIndexRanges = []
            groupBackIndexRanges = []
        }
        if edges { buildEdges(p, lo: &lo, hi: &hi) } else { edgeVertexCount = 0; edgeIndexCount = 0 }
        if lo.x > hi.x { lo = .zero; hi = .zero }
        boundsMin = lo
        boundsMax = hi
    }

    // MARK: Projection

    /// Rotate, spherize and project one point. Returns the 3D position, w and validity.
    @inline(__always)
    static func project(flat: SIMD4<Float>, sphere: SIMD4<Float>, _ p: FrameParameters,
                        maxRadius2: Float) -> (SIMD3<Float>, Float, Bool) {
        let v = flat + p.spherize * (sphere - flat)
        let r = p.rotation * v
        let d = 1 - p.kappa * r.w
        guard d >= p.epsilon else { return (.zero, r.w, false) }
        let q = SIMD3(r.x, r.y, r.z) / d
        return (q, r.w, simd_length_squared(q) <= maxRadius2)
    }

    // MARK: Faces

    private func buildFaces(_ p: FrameParameters, lo: inout SIMD3<Float>, hi: inout SIMD3<Float>) {
        let points = mesh.facePoints
        let maxR2 = p.maxRadius * p.maxRadius
        let mode = p.faceColors
        let patternUV = mesh.facePatternUV
        let usesPattern = mode == .pattern && patternUV.count == points.count
        faceVertices.withUnsafeMutableBufferPointer { verts in
            faceValid.withUnsafeMutableBufferPointer { valid in
                for i in 0..<points.count {
                    let (q, w, ok) = Self.project(flat: points.flat[i], sphere: points.sphere[i], p, maxRadius2: maxR2)
                    valid[i] = ok
                    let uv = usesPattern ? patternUV[i] : mode.uv(key: points.colorKey[i], w: w)
                    verts[i] = MeshVertex(position: q, normal: .zero, uv: uv)
                    if ok {
                        lo = simd_min(lo, q)
                        hi = simd_max(hi, q)
                    }
                }
            }
        }

        // Triangle normals (area weighted), accumulated per vertex; collect visible triangles.
        let tris = mesh.triangles
        var visible = visibleScratch
        visibleScratch = []
        visible.removeAll(keepingCapacity: true)
        defer { visibleScratch = visible }
        let triangleCount = mesh.triangleCount
        faceVertices.withUnsafeMutableBufferPointer { verts in
            faceValid.withUnsafeBufferPointer { valid in
                triangleNormals.withUnsafeMutableBufferPointer { tn in
                    for t in 0..<triangleCount {
                        let a = Int(tris[3 * t]), b = Int(tris[3 * t + 1]), c = Int(tris[3 * t + 2])
                        guard valid[a], valid[b], valid[c] else {
                            tn[t] = .zero
                            continue
                        }
                        let n = simd_cross(verts[b].position - verts[a].position, verts[c].position - verts[a].position)
                        tn[t] = n
                        verts[a].normal += n
                        verts[b].normal += n
                        verts[c].normal += n
                        visible.append(Int32(t))
                    }
                }
            }
        }

        // Optional outward winding per cell (per-cell transparency), then unit normals and the
        // back copies.
        let flips = p.orientCellFaces && computeCellWinding(p)
        finishNormals(flipped: flips, offset: p.faceOffset)
        if p.faceOffset > 0, lo.x <= hi.x {
            lo -= SIMD3(repeating: p.faceOffset)
            hi += SIMD3(repeating: p.faceOffset)
        }

        // Index buffer: in mesh order (cell groups contiguous) or sorted back to front. Each
        // triangle is emitted as a front copy and as a back copy with reversed winding.
        var count = 0
        let back = UInt32(backVertexOffset)
        faceIndices.withUnsafeMutableBufferPointer { out in
            triangleFlip.withUnsafeBufferPointer { flip in
                func emitFront(_ t: Int) {
                    let a = tris[3 * t], b = tris[3 * t + 1], c = tris[3 * t + 2]
                    let reversed = flips && flip[t]
                    out[count] = a
                    out[count + 1] = reversed ? c : b
                    out[count + 2] = reversed ? b : c
                    count += 3
                }
                func emitBack(_ t: Int) {
                    let a = tris[3 * t] + back, b = tris[3 * t + 1] + back, c = tris[3 * t + 2] + back
                    let reversed = flips && flip[t]
                    out[count] = a
                    out[count + 1] = reversed ? b : c
                    out[count + 2] = reversed ? c : b
                    count += 3
                }
                if p.sortFaces {
                    sortKeys.removeAll(keepingCapacity: true)
                    faceVertices.withUnsafeBufferPointer { verts in
                        for t in visible {
                            let ti = Int(t)
                            let centroid = verts[Int(tris[3 * ti])].position + verts[Int(tris[3 * ti + 1])].position
                                + verts[Int(tris[3 * ti + 2])].position
                            sortKeys.append(SortKey(depth: simd_dot(centroid, p.viewDirection), triangle: t))
                        }
                    }
                    sortKeys.sort { $0.depth < $1.depth }
                    for k in sortKeys {
                        emitFront(Int(k.triangle))
                        emitBack(Int(k.triangle))
                    }
                    groupIndexRanges = []
                    groupBackIndexRanges = []
                } else if mesh.groupTriangleRanges.isEmpty {
                    for t in visible {
                        emitFront(Int(t))
                        emitBack(Int(t))
                    }
                    groupIndexRanges = []
                    groupBackIndexRanges = []
                } else {
                    // Per group: all front copies, then all back copies (per-cell entities).
                    var fronts: [Range<Int>] = []
                    var backs: [Range<Int>] = []
                    var v = 0
                    for g in mesh.groupTriangleRanges {
                        let first = v
                        while v < visible.count, Int(visible[v]) < g.upperBound { v += 1 }
                        let frontStart = count
                        for k in first..<v { emitFront(Int(visible[k])) }
                        fronts.append(frontStart..<count)
                        let backStart = count
                        for k in first..<v { emitBack(Int(visible[k])) }
                        backs.append(backStart..<count)
                    }
                    groupIndexRanges = fronts
                    groupBackIndexRanges = backs
                }
            }
        }
        faceIndexCount = count
    }

    /// Normalises the accumulated normals, so they follow the triangle winding; negates the
    /// normals of polygons that `computeCellWinding` reversed; and writes the back copies with
    /// negated normals. With an offset (thick faces, D24) each copy moves that far along its own
    /// normal.
    private func finishNormals(flipped: Bool, offset: Float) {
        let n = backVertexOffset
        let polygonsHavePoints = mesh.polygonPointRanges.count == mesh.polygonTriangleRanges.count
        faceVertices.withUnsafeMutableBufferPointer { verts in
            for i in 0..<n {
                let v = verts[i].normal
                let len = simd_length(v)
                verts[i].normal = len > 1e-20 ? v / len : SIMD3(0, 0, 1)
            }
            if flipped, polygonsHavePoints {
                polygonFlip.withUnsafeBufferPointer { pf in
                    for (k, range) in mesh.polygonPointRanges.enumerated() where pf[k] {
                        for i in range { verts[i].normal = -verts[i].normal }
                    }
                }
            }
            for i in 0..<n {
                var b = verts[i]
                b.normal = -b.normal
                if offset > 0 {
                    b.position += b.normal * offset
                    verts[i].position += verts[i].normal * offset
                }
                verts[n + i] = b
            }
        }
    }

    /// Per-cell transparency: marks every polygon whose normal points into its cell (towards the
    /// cell's projected centre), so that it is emitted reversed with a negated normal. Whole
    /// polygons flip together, so curved (spherized) polygons stay consistent. Returns whether
    /// anything was computed (only meshes with cell groups).
    private func computeCellWinding(_ p: FrameParameters) -> Bool {
        let groups = mesh.groupTriangleRanges
        guard !groups.isEmpty else { return false }
        let centres = mesh.groupCenters
        let tris = mesh.triangles
        let polygons = mesh.polygonTriangleRanges
        let maxR2 = p.maxRadius * p.maxRadius
        for k in polygonFlip.indices { polygonFlip[k] = false }
        for t in triangleFlip.indices { triangleFlip[t] = false }
        faceVertices.withUnsafeBufferPointer { verts in
            // Polygons are contiguous and lie within their group.
            var k = 0
            for (g, range) in groups.enumerated() {
                let (c, _, ok) = Self.project(flat: centres.flat[g], sphere: centres.sphere[g], p, maxRadius2: maxR2)
                while k < polygons.count, polygons[k].lowerBound < range.upperBound {
                    let polygon = polygons[k]
                    let index = k
                    k += 1
                    guard ok else { continue }
                    var normal = SIMD3<Float>.zero
                    var centroid = SIMD3<Float>.zero
                    var corners: Float = 0
                    for t in polygon where triangleNormals[t] != .zero {
                        normal += triangleNormals[t]
                        centroid += verts[Int(tris[3 * t])].position + verts[Int(tris[3 * t + 1])].position
                            + verts[Int(tris[3 * t + 2])].position
                        corners += 3
                    }
                    guard corners > 0, simd_dot(normal, centroid / corners - c) < 0 else { continue }
                    polygonFlip[index] = true
                    for t in polygon { triangleFlip[t] = true }
                }
            }
        }
        return true
    }

    // MARK: Edges

    /// Unsafe views of the per-frame edge buffers, taken once per frame so the hot loops avoid
    /// class-property access and bounds checks.
    private struct EdgeContext {
        var positions: UnsafeBufferPointer<SIMD3<Float>>
        var w: UnsafeBufferPointer<Float>
        var keys: UnsafeBufferPointer<SIMD2<Float>>
        var rings: UnsafeBufferPointer<SIMD2<Float>>
        var verts: UnsafeMutableBufferPointer<MeshVertex>
        var idx: UnsafeMutableBufferPointer<UInt32>
        var colors: FrameColorMode
        var radius: Float
        var sides: Int
    }

    private func buildEdges(_ p: FrameParameters, lo: inout SIMD3<Float>, hi: inout SIMD3<Float>) {
        let points = mesh.edgePoints
        let maxR2 = p.maxRadius * p.maxRadius
        let radius = p.edgeRadius
        edgePositions.withUnsafeMutableBufferPointer { pos in
            edgeW.withUnsafeMutableBufferPointer { ws in
                edgeValid.withUnsafeMutableBufferPointer { valid in
                    points.flat.withUnsafeBufferPointer { flat in
                        points.sphere.withUnsafeBufferPointer { sphere in
                            for i in 0..<flat.count {
                                let (q, w, ok) = Self.project(flat: flat[i], sphere: sphere[i], p, maxRadius2: maxR2)
                                pos[i] = q
                                ws[i] = w
                                valid[i] = ok
                                if ok {
                                    lo = simd_min(lo, q - radius)
                                    hi = simd_max(hi, q + radius)
                                }
                            }
                        }
                    }
                }
            }
        }
        var vCount = 0
        var iCount = 0
        var run: [Int] = []
        run.reserveCapacity(64)
        let sides = tubeSides
        edgePositions.withUnsafeBufferPointer { pos in
        edgeW.withUnsafeBufferPointer { ws in
        edgeValid.withUnsafeBufferPointer { valid in
        points.colorKey.withUnsafeBufferPointer { keys in
        ringDirections.withUnsafeBufferPointer { rings in
        edgeVertices.withUnsafeMutableBufferPointer { verts in
        edgeIndices.withUnsafeMutableBufferPointer { idx in
            let ctx = EdgeContext(positions: pos, w: ws, keys: keys, rings: rings, verts: verts, idx: idx,
                                  colors: p.edgeColors, radius: radius, sides: sides)
            for line in mesh.polylines {
                run.removeAll(keepingCapacity: true)
                for k in line {
                    let i = Int(k)
                    if valid[i] {
                        run.append(i)
                    } else {
                        Self.emitTube(run, ctx, &vCount, &iCount)
                        run.removeAll(keepingCapacity: true)
                    }
                }
                Self.emitTube(run, ctx, &vCount, &iCount)
            }
        }}}}}}}
        edgeVertexCount = vCount
        edgeIndexCount = iCount
    }

    /// A continuous tube along a run of points with frames by parallel transport, closed by flat
    /// caps at both ends.
    private static func emitTube(_ run: [Int], _ ctx: EdgeContext, _ vCount: inout Int, _ iCount: inout Int) {
        let n = run.count
        guard n >= 2 else { return }
        let sides = ctx.sides
        let radius = ctx.radius
        let verts = ctx.verts
        let idx = ctx.idx
        let base = vCount
        var normal = SIMD3<Float>.zero
        var lastTangent = SIMD3<Float>(0, 0, 1)
        for k in 0..<n {
            let pos = ctx.positions[run[k]]
            let prev = ctx.positions[run[max(0, k - 1)]]
            let next = ctx.positions[run[min(n - 1, k + 1)]]
            var t = next - prev
            let len = simd_length(t)
            t = len > 1e-9 ? t / len : lastTangent
            lastTangent = t
            if k == 0 {
                let helper: SIMD3<Float> = abs(t.x) < 0.9 ? [1, 0, 0] : [0, 1, 0]
                normal = simd_normalize(simd_cross(t, helper))
            } else {
                normal -= simd_dot(normal, t) * t
                let nl = simd_length(normal)
                if nl > 1e-9 {
                    normal /= nl
                } else {
                    let helper: SIMD3<Float> = abs(t.x) < 0.9 ? [1, 0, 0] : [0, 1, 0]
                    normal = simd_normalize(simd_cross(t, helper))
                }
            }
            let binormal = simd_cross(t, normal)
            let uv = ctx.colors.uv(key: ctx.keys[run[k]], w: ctx.w[run[k]])
            for s in 0..<sides {
                let d = ctx.rings[s]
                let dir = d.x * normal + d.y * binormal
                verts[vCount] = MeshVertex(position: pos + radius * dir, normal: dir, uv: uv)
                vCount += 1
            }
        }
        // Side quads.
        for k in 0..<(n - 1) {
            let r0 = base + k * sides
            let r1 = r0 + sides
            for s in 0..<sides {
                let s1 = (s + 1) % sides
                let a = UInt32(r0 + s), b = UInt32(r0 + s1), c = UInt32(r1 + s), d = UInt32(r1 + s1)
                idx[iCount] = a; idx[iCount + 1] = b; idx[iCount + 2] = d
                idx[iCount + 3] = a; idx[iCount + 4] = d; idx[iCount + 5] = c
                iCount += 6
            }
        }
        // Caps as fans over the end rings (the start cap reversed, facing backwards).
        let startRing = base
        let endRing = base + (n - 1) * sides
        for s in 1..<(sides - 1) {
            idx[iCount] = UInt32(startRing)
            idx[iCount + 1] = UInt32(startRing + s + 1)
            idx[iCount + 2] = UInt32(startRing + s)
            idx[iCount + 3] = UInt32(endRing)
            idx[iCount + 4] = UInt32(endRing + s)
            idx[iCount + 5] = UInt32(endRing + s + 1)
            iCount += 6
        }
    }
}
