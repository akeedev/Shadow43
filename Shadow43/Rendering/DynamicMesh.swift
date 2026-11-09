// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import Metal
import RealityKit

/// A `LowLevelMesh` with the `MeshVertex` layout (position, normal, uv0; 48-byte stride) that is
/// rewritten every frame (DESIGN 11.1, step 6).
@MainActor
final class DynamicMesh {
    let lowLevelMesh: LowLevelMesh
    let resource: MeshResource
    let vertexCapacity: Int
    let indexCapacity: Int

    init(vertexCapacity: Int, indexCapacity: Int) throws {
        precondition(MemoryLayout<MeshVertex>.stride == 48, "MeshVertex must have a 48-byte stride")
        self.vertexCapacity = max(1, vertexCapacity)
        self.indexCapacity = max(3, indexCapacity)
        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexAttributes = [
            LowLevelMesh.Attribute(semantic: .position, format: .float3,
                                   offset: MemoryLayout<MeshVertex>.offset(of: \.position)!),
            LowLevelMesh.Attribute(semantic: .normal, format: .float3,
                                   offset: MemoryLayout<MeshVertex>.offset(of: \.normal)!),
            LowLevelMesh.Attribute(semantic: .uv0, format: .float2,
                                   offset: MemoryLayout<MeshVertex>.offset(of: \.uv)!),
        ]
        descriptor.vertexLayouts = [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<MeshVertex>.stride)]
        descriptor.vertexCapacity = self.vertexCapacity
        descriptor.indexCapacity = self.indexCapacity
        descriptor.indexType = .uint32
        lowLevelMesh = try LowLevelMesh(descriptor: descriptor)
        resource = try MeshResource(from: lowLevelMesh)
    }

    /// Copies the first `vertexCount` vertices and `indexCount` indices into the mesh.
    func update(vertices: [MeshVertex], vertexCount: Int, indices: [UInt32], indexRange: Range<Int>,
                bounds: BoundingBox) {
        let vCount = min(vertexCount, vertexCapacity, vertices.count)
        let iCount = min(indexRange.count, indexCapacity)
        if vCount > 0 {
            lowLevelMesh.replaceUnsafeMutableBytes(bufferIndex: 0) { raw in
                vertices.withUnsafeBytes { src in
                    raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[0..<(vCount * MemoryLayout<MeshVertex>.stride)]))
                }
            }
        }
        if iCount > 0 {
            lowLevelMesh.replaceUnsafeMutableIndices { raw in
                indices.withUnsafeBytes { src in
                    let start = indexRange.lowerBound * 4
                    raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[start..<(start + iCount * 4)]))
                }
            }
        }
        setPart(indexCount: iCount, bounds: bounds)
    }

    /// Copies a vertex sub-range and the indices `indices[indexRange]` minus `indexBase`
    /// (per-cell entities: the indices refer to the builder's buffer, the vertices start at 0).
    func update(vertices: [MeshVertex], vertexRange: Range<Int>, indices: [UInt32], indexRange: Range<Int>,
                indexBase: UInt32, bounds: BoundingBox) {
        let vCount = min(vertexRange.count, vertexCapacity)
        let iCount = min(indexRange.count, indexCapacity)
        let base = indexBase
        if vCount > 0 {
            lowLevelMesh.replaceUnsafeMutableBytes(bufferIndex: 0) { raw in
                vertices.withUnsafeBytes { src in
                    let stride = MemoryLayout<MeshVertex>.stride
                    let start = vertexRange.lowerBound * stride
                    raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[start..<(start + vCount * stride)]))
                }
            }
        }
        if iCount > 0 {
            lowLevelMesh.replaceUnsafeMutableIndices { raw in
                let out = raw.bindMemory(to: UInt32.self)
                for k in 0..<iCount { out[k] = indices[indexRange.lowerBound + k] - base }
            }
        }
        setPart(indexCount: iCount, bounds: bounds)
    }

    private func setPart(indexCount: Int, bounds: BoundingBox) {
        if indexCount == 0 {
            lowLevelMesh.parts.removeAll()
        } else {
            lowLevelMesh.parts.replaceAll([
                LowLevelMesh.Part(indexOffset: 0, indexCount: indexCount, topology: .triangle,
                                  materialIndex: 0, bounds: bounds),
            ])
        }
    }
}
