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
    /// The bounds follow the window's size (D19); everything else stays fixed.
    private(set) var host: SceneHost
    /// Positioned by the host; carries the `ShadowComponent`, so it stays enabled.
    let root = Entity()
    /// Room only: holds the root and, beside it, the floor disc that moves it (D38). The room view
    /// adds this instead of the root.
    let roomBase = Entity()
    /// Everything visible and touchable: the floor and light (metres) and the scaled content.
    /// The window disables it while the room is open (D30).
    let stage = Entity()
    /// Object units; scaled to fill the host box (`SizeFit`, D15) times `model.scale`.
    let content = Entity()
    let facesEntity = ModelEntity()
    let edgesEntity = ModelEntity()
    let floor: FloorShadow
    let cells: CellEntities
    /// The object's 4D axes in metres (D20).
    let axes = AxisEntities()
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
        probe = ManipulationProbe.make(at: Self.probePosition(host))
        root.name = "ShadowRoot"
        root.position = host.contentOffset
        content.name = "Content"
        facesEntity.name = "Faces"
        edgesEntity.name = "Edges"
        stage.name = "Stage"
        root.addChild(stage)
        stage.addChild(content)
        content.addChild(facesEntity)
        content.addChild(edgesEntity)
        content.addChild(cells.container)
        stage.addChild(floor.root)
        stage.addChild(axes.root)
        inputTarget.name = "InputTarget"
        inputTarget.components.set(InputTargetComponent())
        inputTarget.components.set(ShadowInputComponent())
        updateInputTarget(lift: .zero)
        stage.addChild(inputTarget)
        if host.kind == .room { makeMovable() }
        probe.isEnabled = false
        stage.addChild(probe)
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

    /// The host's box changed, e.g. the window was resized (D19): the size fit, floor, light and
    /// input target follow.
    func setHost(_ newHost: SceneHost) {
        guard newHost.bounds != host.bounds || newHost.contentOffset != host.contentOffset else { return }
        host.bounds = newHost.bounds
        host.contentOffset = newHost.contentOffset
        root.position = host.contentOffset
        floor.layout(for: host)
        probe.position = Self.probePosition(host)
        updateInputTarget(lift: inputTarget.position)
        lastParameters = nil
    }

    /// Radius of the input target's collision sphere, to regenerate it only when it changes.
    private var inputTargetRadius: Float = 0

    /// Where the gestures can grab the object (D32). In the window: a sphere filling the volume,
    /// centred and never lifted. It used to be lifted with an enlarged object (D21) and then left
    /// the volume, where touches are not delivered, so the object stopped reacting. In the room
    /// it follows the object's size and lift.
    private func updateInputTarget(lift: SIMD3<Float>) {
        let radius: Float, position: SIMD3<Float>
        switch host.kind {
        case .window:
            radius = 0.5 * host.smallestSide
            position = .zero
        case .room:
            radius = 0.375 * host.smallestSide * Float(model.scale)
            position = lift
        }
        if inputTarget.position != position { inputTarget.position = position }
        guard radius != inputTargetRadius else { return }
        inputTargetRadius = radius
        inputTarget.components.set(CollisionComponent(shapes: [.generateSphere(radius: radius)], isStatic: true))
    }

    private static let upright = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    /// Room only (D33, D38): grabbing the floor disc moves the whole object through the room. The
    /// system's manipulation moves the disc, translation only, and the root follows it every frame
    /// (`followDisc`). The disc is the root's sibling, not its parent: a manipulation on an
    /// ancestor also took the grabs meant for the object, so it could no longer be turned. The
    /// base is level (D36), so the disc stays parallel to the floor.
    private func makeMovable() {
        roomBase.name = "RoomBase"
        roomBase.addChild(root)
        let disc = floor.makeHandle()
        disc.position = root.position + floor.discOffset
        roomBase.addChild(disc)
    }

    /// Room only: the root goes where the disc was moved, and both stay upright (D36, D38).
    private func followDisc() {
        let disc = floor.disc
        if disc.orientation != Self.upright { disc.orientation = Self.upright }
        if root.orientation != Self.upright { root.orientation = Self.upright }
        let target = disc.position - floor.discOffset
        if root.position != target { root.position = target }
    }

    private static func probePosition(_ host: SceneHost) -> SIMD3<Float> {
        host.bounds * SIMD3(0.4, -0.38, 0.4)
    }

    // MARK: Frame

    func update(deltaTime: TimeInterval) {
        let start = CACurrentMediaTime()
        model.tick(now: ProcessInfo.processInfo.systemUptime)
        // While the room is open the window stays empty, so the object is not seen twice (D30).
        let shown = !(host.kind == .window && model.isRoomOpen)
        if stage.isEnabled != shown { stage.isEnabled = shown }
        guard shown else { return }
        if host.kind == .room { followDisc() }
        let rebuilt = syncStructure()
        let layers = currentLayers()
        if layers != lastLayersApplied || rebuilt {
            applyLayers(layers)
            lastLayersApplied = layers
        }
        let scale = metresPerUnit()
        content.scale = SIMD3(repeating: scale)
        // Enlarged objects rise instead of sinking into the floor disc (D21).
        let lift = SIMD3<Float>(0, Float(SizeFit.lift(boxSide: Double(host.smallestSide), sizeFactor: model.scale)), 0)
        if content.position != lift {
            content.position = lift
            axes.root.position = lift
        }
        updateInputTarget(lift: lift)
        floor.update(enabled: model.display.floorShadow, method: model.developer.floorShadowMethod)
        updateAxes(metresPerUnit: scale)
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

    // MARK: Axes (D20)

    private func updateAxes(metresPerUnit: Float) {
        let visible = model.display.axesVisible
        if axes.root.isEnabled != visible { axes.root.isEnabled = visible }
        guard visible else { return }
        let box = Double(max(host.bounds.x, max(host.bounds.y, host.bounds.z)))
        axes.update(AxisCross.axes(rotation: model.orientation, kappa: model.projection.kappa,
                                   maxRadius: 4 * box / Double(metresPerUnit)),
                    metresPerUnit: metresPerUnit)
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
        // Per-cell entities only with explode and few cells (D31).
        var method = model.developer.transparency.effective(cellCount: complex?.value.cells.count ?? 0,
                                                            explode: model.effectiveExplode)
        // Additive blending adds the light pattern layers up to white; sorted keeps them (D24).
        if method == .additive && d.pattern != .none { method = .sorted }
        let usesCells = facesVisible && translucent && method == .perCellEntities
        // A pattern replaces the colour source on the faces; edges keep it (D24).
        let pattern = Self.texture(for: d.pattern)
        return LayerKey(
            facesVisible: facesVisible,
            edgesVisible: d.edgesVisible || !hasFaces,
            style: d.faceStyle,
            opacity: Float(d.faceOpacity),
            translucent: translucent,
            method: method,
            usesCellEntities: usesCells,
            faceTexture: pattern ?? Self.texture(for: source),
            faceMode: pattern != nil ? .pattern : Self.mode(for: source),
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
        // Edge and face thickness keep their size in metres when the object is zoomed (D28).
        let mpu = Double(metresPerUnit())
        let reference = Double(host.thicknessReferenceSide)
        let edgeRadius = SizeFit.fixedLength(model.display.edgeThickness, referenceSide: reference, metresPerUnit: mpu)
        let faceThickness = SizeFit.fixedLength(model.display.faceThickness, referenceSide: reference, metresPerUnit: mpu)
        return FrameParameters(
            rotation: Rotation4D.float(model.orientation),
            kappa: Float(model.projection.kappa),
            spherize: Float(model.projection.spherize),
            faceColors: l.faceMode,
            edgeColors: l.edgeMode,
            edgeRadius: Float(edgeRadius),
            sortFaces: l.facesVisible && l.translucent && l.method == .sorted,
            orientCellFaces: l.usesCellEntities,
            viewDirection: viewDirection,
            epsilon: Float(Projection4D.defaultEpsilon),
            maxRadius: 4 * box / metresPerUnit(),
            // Thick faces (D24): half the thickness on each side.
            faceOffset: Float(0.5 * faceThickness)
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

    /// The face texture of a pattern, or nil for none (D24).
    static func texture(for pattern: SurfacePattern) -> ColorTexture? {
        switch pattern {
        case .none: nil
        case .grid: .grid
        case .marble: .marble
        case .wood: .wood
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
