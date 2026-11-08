// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import os
import QuartzCore
import RealityKit
import simd

/// Owns the entities of one host's shadow content and runs the per-frame pipeline
/// (DESIGN 6.3) for them. The content entity is scaled but never rotated; all rotation lives in R.
@MainActor
final class ShadowRenderer {
    static let logger = Logger(subsystem: "Shadow43", category: "Rendering")

    let model: AppModel
    let host: SceneHost
    /// Positioned by the host; holds the floor and light (metres) and the scaled content.
    let root = Entity()
    /// Object units; scaled to fill the host box (`SizeFit`, D15) times `model.scale`.
    let content = Entity()
    let facesEntity = ModelEntity()
    let edgesEntity = ModelEntity()
    let floor: FloorShadow
    let cells: CellEntities
    /// Static collision sphere for gestures; the mesh changes every frame (DESIGN 6.5).
    let inputTarget = Entity()
    /// Variant C probe for the gesture test (S3).
    let probe: ModelEntity

    private let materials = MaterialFactory()
    private var structure: StructureKey?
    private var complex: (key: ComplexKey, value: Complex4D)?
    /// Fitted radius (object units) for the current object and projection (D15).
    private var fit: (key: FitKey, radius: Double)?
    private var builder: FrameBuilder?
    private var faceMesh: DynamicMesh?
    private var edgeMesh: DynamicMesh?
    private var layers: LayerKey?
    private var lastParameters: FrameParameters?
    private var lastLayersApplied: LayerKey?
    private var stats = StatsAccumulator()

    init(model: AppModel, host: SceneHost) {
        self.model = model
        self.host = host
        floor = FloorShadow(host: host)
        cells = CellEntities()
        probe = ManipulationProbe.make(at: host.bounds * SIMD3(0.4, -0.38, 0.4))
        root.name = "ShadowRoot"
        root.position = host.contentOffset
        content.name = "Content"
        facesEntity.name = "Faces"
        edgesEntity.name = "Edges"
        root.addChild(content)
        content.addChild(facesEntity)
        content.addChild(edgesEntity)
        content.addChild(cells.container)
        root.addChild(floor.root)
        inputTarget.name = "InputTarget"
        inputTarget.components.set(InputTargetComponent())
        let targetRadius = 0.375 * min(host.bounds.x, min(host.bounds.y, host.bounds.z))
        inputTarget.components.set(CollisionComponent(shapes: [.generateSphere(radius: targetRadius)], isStatic: true))
        root.addChild(inputTarget)
        probe.isEnabled = false
        root.addChild(probe)
        floor.attachCaster(facesEntity)
        floor.attachCaster(edgesEntity)
        floor.attachCaster(cells.container)
        root.components.set(ShadowComponent(renderer: self))
        Task { [weak self] in
            await self?.materials.prepare()
            self?.lastLayersApplied = nil
        }
    }

    /// Breaks the reference cycle root → component → renderer when the view goes away.
    func tearDown() {
        root.components.remove(ShadowComponent.self)
    }

    // MARK: Frame

    func update(deltaTime: TimeInterval) {
        let start = CACurrentMediaTime()
        model.tick(now: ProcessInfo.processInfo.systemUptime)
        let rebuilt = syncStructure()
        let layers = currentLayers()
        if layers != lastLayersApplied || rebuilt {
            applyLayers(layers)
            lastLayersApplied = layers
        }
        content.scale = SIMD3(repeating: metresPerUnit())
        floor.update(enabled: model.display.floorShadow, method: model.developer.floorShadowMethod)
        if probe.isEnabled != model.developer.showsGestureTest { probe.isEnabled = model.developer.showsGestureTest }

        let p = frameParameters(layers)
        var buildTime = 0.0
        if let builder, rebuilt || p != lastParameters {
            let buildStart = CACurrentMediaTime()
            builder.update(p, faces: layers.facesVisible, edges: layers.edgesVisible)
            buildTime = CACurrentMediaTime() - buildStart
            upload(builder, layers: layers)
            lastParameters = p
        }
        stats.add(frame: deltaTime, cpu: CACurrentMediaTime() - start, build: buildTime,
                  triangles: builder?.visibleTriangleCount ?? 0,
                  vertices: (builder?.faceVertexCount ?? 0) + (builder?.edgeVertexCount ?? 0))
        if let s = stats.flushIfDue(), s != model.stats { model.stats = s }
    }

    // MARK: Size (D15)

    /// The radius holding 90 % of the projected vertices, cached per object and projection.
    /// While a projection slider moves it is recomputed every frame (about 16k points).
    private func fittedRadius() -> Double {
        guard let complex else { return 1 }
        let key = FitKey(complex: complex.key, projection: model.projection)
        if let fit, fit.key == key { return fit.radius }
        let r = SizeFit.radius(of: complex.value, projection: model.projection)
        fit = (key, r)
        return r
    }

    /// Metres per object unit: the fitted radius fills 75 % of the box, times the size factor.
    private func metresPerUnit() -> Float {
        Float(SizeFit.metresPerUnit(fittedRadius: fittedRadius(), boxSide: Double(host.smallestSide),
                                    sizeFactor: model.scale))
    }

    // MARK: Structure (object, explode, subdivision)

    /// Rebuilds the render mesh and the `LowLevelMesh` buffers when the object, explode or
    /// subdivision changes. Returns whether anything was rebuilt.
    private func syncStructure() -> Bool {
        let ck = ComplexKey(object: model.object, duoprism: model.object == .duoprism ? model.duoprism : nil)
        if complex?.key != ck {
            complex = (ck, ObjectCatalog.complex(for: ck.object, duoprism: model.duoprism))
        }
        guard let c = complex?.value else { return false }
        var options = TessellationOptions.recommended(for: c, spherize: model.projection.spherize)
        if model.developer.forcesFineSubdivision {
            options = TessellationOptions(edgeSegments: 8, faceSubdivision: 3)
        }
        let key = StructureKey(complex: ck, explode: model.effectiveExplode, options: options)
        guard key != structure else { return false }
        structure = key
        let mesh = Tessellation.renderMesh(for: c, explode: key.explode, options: options)
        let b = FrameBuilder(mesh: mesh)
        builder = b
        do {
            if faceMesh == nil || faceMesh!.vertexCapacity < b.faceVertexCapacity || faceMesh!.indexCapacity < b.faceIndexCapacity {
                faceMesh = try DynamicMesh(vertexCapacity: b.faceVertexCapacity, indexCapacity: b.faceIndexCapacity)
            }
            if edgeMesh == nil || edgeMesh!.vertexCapacity < b.edgeVertexCapacity || edgeMesh!.indexCapacity < b.edgeIndexCapacity {
                edgeMesh = try DynamicMesh(vertexCapacity: b.edgeVertexCapacity, indexCapacity: b.edgeIndexCapacity)
            }
        } catch {
            ShadowRenderer.logger.error("Could not create LowLevelMesh (faces \(b.faceVertexCapacity) vertices, edges \(b.edgeVertexCapacity) vertices): \(error.localizedDescription, privacy: .public)")
        }
        cells.rebuild(groups: mesh.groupPointRanges, triangles: mesh.groupTriangleRanges)
        lastParameters = nil
        return true
    }

    // MARK: Layers and materials

    private func currentLayers() -> LayerKey {
        let d = model.display
        let kind = model.object.kind
        let source = model.effectiveColorSource
        let hasFaces = kind != .curves
        let facesVisible = hasFaces && d.faceOpacity > 0.001
        let translucent = d.faceOpacity < 0.999
        var method = model.developer.transparency
        if method == .perCellEntities && model.effectiveExplode == 0 { method = .sorted }
        let usesCells = facesVisible && translucent && method == .perCellEntities
        return LayerKey(
            facesVisible: facesVisible,
            edgesVisible: d.edgesVisible || !hasFaces,
            style: d.faceStyle,
            opacity: Float(d.faceOpacity),
            translucent: translucent,
            method: method,
            usesCellEntities: usesCells,
            faceTexture: Self.texture(for: source),
            faceMode: Self.mode(for: source),
            edgeTexture: d.edgeColor == .light ? .light : Self.texture(for: source),
            edgeMode: d.edgeColor == .light ? .uniform : Self.mode(for: source)
        )
    }

    private func applyLayers(_ l: LayerKey) {
        let blend: MaterialKey.Blend = !l.translucent ? .opaque : (l.method == .additive && materials.isReady ? .additive : .alpha)
        // Double-sided via a front and a back copy of every triangle, each with its own normals,
        // plus back-face culling (D12, D16).
        let faceMaterial = materials.material(MaterialKey(style: l.style, texture: l.faceTexture, opacity: l.opacity,
                                                          blend: blend, culling: .back))
        let edgeMaterial = materials.material(MaterialKey(style: l.style, texture: l.edgeTexture, opacity: 1,
                                                          blend: .opaque, culling: .back))
        if let faceMesh { facesEntity.model = ModelComponent(mesh: faceMesh.resource, materials: [faceMaterial]) }
        if let edgeMesh { edgesEntity.model = ModelComponent(mesh: edgeMesh.resource, materials: [edgeMaterial]) }
        facesEntity.isEnabled = l.facesVisible && !l.usesCellEntities
        edgesEntity.isEnabled = l.edgesVisible
        if l.usesCellEntities {
            // Back copies (inner sides) and front copies (outer sides) are separate entities with
            // the same material; the sort group draws the back copies first.
            cells.setMaterial(materials.material(MaterialKey(style: l.style, texture: l.faceTexture, opacity: l.opacity,
                                                             blend: .alpha, culling: .back)))
        }
        cells.container.isEnabled = l.usesCellEntities
        lastParameters = nil
    }

    private func frameParameters(_ l: LayerKey) -> FrameParameters {
        let box = max(host.bounds.x, max(host.bounds.y, host.bounds.z))
        let viewDirection: SIMD3<Float> = host.tracksVolumeViewpoint ? model.viewSide.direction : [0, 0, 1]
        return FrameParameters(
            rotation: Rotation4D.float(model.orientation),
            kappa: Float(model.projection.kappa),
            spherize: Float(model.projection.spherize),
            faceColors: l.faceMode,
            edgeColors: l.edgeMode,
            // Relative to the fitted radius, so tubes keep their size in metres (D15).
            edgeRadius: Float(model.display.edgeThickness * fittedRadius()),
            sortFaces: l.facesVisible && l.translucent && l.method == .sorted,
            orientCellFaces: l.usesCellEntities,
            viewDirection: viewDirection,
            epsilon: Float(Projection4D.defaultEpsilon),
            maxRadius: 4 * box / metresPerUnit()
        )
    }

    private func upload(_ b: FrameBuilder, layers: LayerKey) {
        let bounds = BoundingBox(min: b.boundsMin, max: b.boundsMax)
        if layers.facesVisible, !layers.usesCellEntities, let faceMesh {
            faceMesh.update(vertices: b.faceVertices, vertexCount: b.faceVertexCount, indices: b.faceIndices,
                            indexRange: 0..<b.faceIndexCount, bounds: bounds)
        }
        if layers.edgesVisible, let edgeMesh {
            edgeMesh.update(vertices: b.edgeVertices, vertexCount: b.edgeVertexCount, indices: b.edgeIndices,
                            indexRange: 0..<b.edgeIndexCount, bounds: bounds)
        }
        if layers.usesCellEntities {
            cells.upload(b)
        }
    }

    // MARK: Colour sources

    static func texture(for source: ColorSource) -> ColorTexture {
        switch source {
        case .uniform: .uniform
        case .byW: .byW
        case .perCell: .palette
        case .surfaceParameter: .checkerboard
        case .perFibre: .hue
        }
    }

    static func mode(for source: ColorSource) -> FrameColorMode {
        switch source {
        case .uniform: .uniform
        case .byW: .byW
        case .perCell: .palette(count: ColorTexture.paletteCount)
        case .surfaceParameter: .surfaceParameter
        case .perFibre: .curveKey
        }
    }
}

/// Which object complex is shown.
struct ComplexKey: Equatable {
    var object: ObjectID
    var duoprism: DuoprismParameters?
}

/// Everything the fitted size depends on (D15).
struct FitKey: Equatable {
    var complex: ComplexKey
    var projection: ProjectionSettings
}

/// Everything the render mesh depends on.
struct StructureKey: Equatable {
    var complex: ComplexKey
    var explode: Double
    var options: TessellationOptions
}

/// Everything the materials and entity visibility depend on.
struct LayerKey: Equatable {
    var facesVisible: Bool
    var edgesVisible: Bool
    var style: FaceStyle
    var opacity: Float
    var translucent: Bool
    var method: TransparencyMethod
    var usesCellEntities: Bool
    var faceTexture: ColorTexture
    var faceMode: FrameColorMode
    var edgeTexture: ColorTexture
    var edgeMode: FrameColorMode
}

/// Averages frame and CPU times for the performance overlay (spike S2).
struct StatsAccumulator {
    private var frames = 0
    private var frameTime = 0.0
    private var cpuTime = 0.0
    private var buildTime = 0.0
    private var lastFlush = CACurrentMediaTime()
    private var triangles = 0
    private var vertices = 0

    mutating func add(frame: TimeInterval, cpu: TimeInterval, build: TimeInterval, triangles: Int, vertices: Int) {
        frames += 1
        frameTime += frame
        cpuTime += cpu
        buildTime += build
        self.triangles = triangles
        self.vertices = vertices
    }

    /// Returns averaged stats twice a second.
    mutating func flushIfDue() -> RenderStats? {
        let now = CACurrentMediaTime()
        guard now - lastFlush >= 0.5, frames > 0 else { return nil }
        let n = Double(frames)
        let ms = { (t: Double) in (t / n * 10000).rounded() / 10 }
        let s = RenderStats(frameTimeMs: ms(frameTime), cpuTimeMs: ms(cpuTime), buildTimeMs: ms(buildTime),
                            triangles: triangles, vertices: vertices)
        frames = 0
        frameTime = 0
        cpuTime = 0
        buildTime = 0
        lastFlush = now
        return s
    }
}
