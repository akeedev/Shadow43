// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import RealityKit
import simd

/// Transparency method 3 (spike S1, DESIGN 6.5): one entity pair per cell, only with explode > 0.
/// RealityKit sorts the cells as separate entities; within a convex cell the inner sides are drawn
/// before the outer sides (one `ModelSortGroup` per cell).
///
/// The cell's faces are wound outwards. The back entity holds the back copies (inner sides, normals
/// inwards), the front entity the front copies (outer sides, normals outwards); both use back-face
/// culling, so each draws exactly the half of the cell that faces the camera (D16).
///
/// Each cell entity is placed at its cell's centroid (its vertices are stored relative to it), so
/// that RealityKit's distance sort sees where the cell actually is.
@MainActor
final class CellEntities {
    let container = Entity()
    private var groupPoints: [Range<Int>] = []
    private var groupTriangles: [Range<Int>] = []
    private var frontMeshes: [DynamicMesh] = []
    private var backMeshes: [DynamicMesh] = []
    private var backEntities: [ModelEntity] = []
    private var frontEntities: [ModelEntity] = []
    private var needsEntities = false
    private var material: (any RealityKit.Material)?
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
        frontMeshes = []
        backMeshes = []
        backEntities = []
        frontEntities = []
    }

    func setMaterial(_ material: any RealityKit.Material) {
        self.material = material
        ensureEntities()
        applyMaterials()
    }

    private func ensureEntities() {
        guard needsEntities else { return }
        needsEntities = false
        for g in groupPoints.indices {
            let vertices = groupPoints[g].count
            let indices = groupTriangles[g].count * 3
            guard let frontMesh = try? DynamicMesh(vertexCapacity: vertices, indexCapacity: indices),
                  let backMesh = try? DynamicMesh(vertexCapacity: vertices, indexCapacity: indices) else { continue }
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
            frontMeshes.append(frontMesh)
            backMeshes.append(backMesh)
            backEntities.append(back)
            frontEntities.append(front)
        }
        applyMaterials()
    }

    private func applyMaterials() {
        guard let material else { return }
        for g in frontMeshes.indices {
            backEntities[g].model = ModelComponent(mesh: backMeshes[g].resource, materials: [material])
            frontEntities[g].model = ModelComponent(mesh: frontMeshes[g].resource, materials: [material])
        }
    }

    /// Writes every cell's front and back copies (vertices relative to the cell centroid) and
    /// their indices.
    func upload(_ b: FrameBuilder) {
        ensureEntities()
        let fronts = b.groupIndexRanges
        let backs = b.groupBackIndexRanges
        guard fronts.count == frontMeshes.count, backs.count == backMeshes.count else { return }
        for g in frontMeshes.indices {
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
            let bounds = fronts[g].isEmpty ? BoundingBox() : BoundingBox(min: lo - centroid, max: hi - centroid)
            write(frontMeshes[g], b, firstVertex: points.lowerBound, count: points.count,
                  indices: fronts[g], centroid: centroid, bounds: bounds)
            write(backMeshes[g], b, firstVertex: b.backVertexOffset + points.lowerBound, count: points.count,
                  indices: backs[g], centroid: centroid, bounds: bounds)
            backEntities[g].position = centroid
            frontEntities[g].position = centroid
        }
    }

    /// Copies `count` vertices starting at `firstVertex`, moved by −centroid, and the indices of
    /// `indices` rebased to them.
    private func write(_ mesh: DynamicMesh, _ b: FrameBuilder, firstVertex: Int, count: Int, indices: Range<Int>,
                       centroid: SIMD3<Float>, bounds: BoundingBox) {
        scratch.removeAll(keepingCapacity: true)
        for i in firstVertex..<(firstVertex + count) {
            var v = b.faceVertices[i]
            v.position -= centroid
            scratch.append(v)
        }
        mesh.update(vertices: scratch, vertexRange: 0..<count, indices: b.faceIndices, indexRange: indices,
                    indexBase: UInt32(firstVertex), bounds: bounds)
    }
}
