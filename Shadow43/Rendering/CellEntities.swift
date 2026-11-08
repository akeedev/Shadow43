// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import RealityKit
import simd

/// Transparency method 3 (spike S1, DESIGN 6.5): one entity pair per cell, only with explode > 0.
/// RealityKit sorts the cells as separate entities; within a convex cell the back faces are drawn
/// before the front faces (one `ModelSortGroup` per cell plus face culling).
///
/// Each cell entity is placed at its cell's centroid (its vertices are stored relative to it), so
/// that RealityKit's distance sort sees where the cell actually is.
@MainActor
final class CellEntities {
    let container = Entity()
    private var groupPoints: [Range<Int>] = []
    private var groupTriangles: [Range<Int>] = []
    private var meshes: [DynamicMesh] = []
    private var backEntities: [ModelEntity] = []
    private var frontEntities: [ModelEntity] = []
    private var needsEntities = false
    private var backMaterial: (any RealityKit.Material)?
    private var frontMaterial: (any RealityKit.Material)?
    private var scratch: [MeshVertex] = []

    init() {
        container.name = "CellEntities"
    }

    /// Records the cell layout of a new render mesh; entities are created on first use.
    func rebuild(groups: [Range<Int>], triangles: [Range<Int>]) {
        groupPoints = groups
        groupTriangles = triangles
        needsEntities = true
        for child in Array(container.children) { child.removeFromParent() }
        meshes = []
        backEntities = []
        frontEntities = []
    }

    func setMaterials(backFaces: any RealityKit.Material, frontFaces: any RealityKit.Material) {
        backMaterial = backFaces
        frontMaterial = frontFaces
        ensureEntities()
        applyMaterials()
    }

    private func ensureEntities() {
        guard needsEntities else { return }
        needsEntities = false
        for g in groupPoints.indices {
            guard let mesh = try? DynamicMesh(vertexCapacity: groupPoints[g].count,
                                              indexCapacity: groupTriangles[g].count * 3) else { continue }
            let group = ModelSortGroup(depthPass: nil)
            let back = ModelEntity()
            back.name = "Cell\(g)-back"
            back.components.set(ModelSortGroupComponent(group: group, order: 0))
            let front = ModelEntity()
            front.name = "Cell\(g)-front"
            front.components.set(ModelSortGroupComponent(group: group, order: 1))
            back.components.set(DynamicLightShadowComponent(castsShadow: true))
            front.components.set(DynamicLightShadowComponent(castsShadow: true))
            container.addChild(back)
            container.addChild(front)
            meshes.append(mesh)
            backEntities.append(back)
            frontEntities.append(front)
        }
        applyMaterials()
    }

    private func applyMaterials() {
        guard let backMaterial, let frontMaterial else { return }
        for g in meshes.indices {
            backEntities[g].model = ModelComponent(mesh: meshes[g].resource, materials: [backMaterial])
            frontEntities[g].model = ModelComponent(mesh: meshes[g].resource, materials: [frontMaterial])
        }
    }

    /// Writes every cell's vertices (relative to the cell centroid) and its outward-wound indices.
    func upload(_ b: FrameBuilder, viewDirection: SIMD3<Float>) {
        ensureEntities()
        let ranges = b.groupIndexRanges
        guard ranges.count == meshes.count else { return }
        for g in meshes.indices {
            let points = groupPoints[g]
            var centroid = SIMD3<Float>.zero
            var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
            for i in points {
                let p = b.faceVertices[i].position
                centroid += p
                lo = simd_min(lo, p)
                hi = simd_max(hi, p)
            }
            centroid /= Float(max(1, points.count))
            scratch.removeAll(keepingCapacity: true)
            for i in points {
                var v = b.faceVertices[i]
                v.position -= centroid
                scratch.append(v)
            }
            let bounds = ranges[g].isEmpty ? BoundingBox() : BoundingBox(min: lo - centroid, max: hi - centroid)
            // Indices are relative to the group's first point; `scratch` starts at that point.
            meshes[g].update(vertices: scratch, vertexRange: 0..<points.count,
                             indices: b.faceIndices.rebased(from: points.lowerBound, range: ranges[g]),
                             indexRange: 0..<ranges[g].count, bounds: bounds)
            backEntities[g].position = centroid
            frontEntities[g].position = centroid
        }
    }
}

private extension Array where Element == UInt32 {
    /// A copy of `self[range]` with `offset` subtracted from every index.
    func rebased(from offset: Int, range: Range<Int>) -> [UInt32] {
        let o = UInt32(offset)
        return self[range].map { $0 - o }
    }
}
