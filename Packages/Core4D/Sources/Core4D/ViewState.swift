// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// The objects the app can show (DESIGN 3). The raw value is the launch-argument name.
public enum ObjectID: String, Codable, CaseIterable, Sendable {
    case fiveCell = "5-cell"
    case tesseract
    case sixteenCell = "16-cell"
    case twentyFourCell = "24-cell"
    case oneTwentyCell = "120-cell"
    case sixHundredCell = "600-cell"
    case duoprism
    case kleinBottle = "klein-bottle"
    case cliffordTorus = "clifford-torus"
    case hopfFibration = "hopf"

    public var kind: ObjectKind {
        switch self {
        case .fiveCell, .tesseract, .sixteenCell, .twentyFourCell, .oneTwentyCell,
             .sixHundredCell, .duoprism:
            .polytope
        case .kleinBottle, .cliffordTorus: .surface
        case .hopfFibration: .curves
        }
    }
}

/// The three kinds of objects, each with one generic generator.
public enum ObjectKind: String, Codable, Sendable {
    case polytope, surface, curves
}

/// Projection stage: perspective strength κ and spherize s (DESIGN 5).
public struct ProjectionSettings: Codable, Equatable, Sendable {
    /// κ, the reciprocal of the eye distance along W. 0 = orthographic.
    public var kappa: Double
    /// s, blend between the flat object (0) and its image on S³ (1).
    public var spherize: Double

    public init(kappa: Double, spherize: Double) {
        self.kappa = kappa
        self.spherize = spherize
    }

    /// Range of κ and of s.
    public static let range: ClosedRange<Double> = 0...1
}

/// Colour source for faces and (optionally) edges (DESIGN 6.3).
public enum ColorSource: String, Codable, CaseIterable, Sendable {
    case uniform
    case byW = "by-w"
    case perCell = "per-cell"
    case surfaceParameter = "surface"
    case perFibre = "per-fibre"

    /// Whether this source makes sense for an object kind.
    public func isAvailable(for kind: ObjectKind) -> Bool {
        switch self {
        case .uniform, .byW: true
        case .perCell: kind == .polytope
        case .surfaceParameter: kind == .surface
        case .perFibre: kind == .curves
        }
    }
}

/// Face material: lit by the room (matte, glossy, metal, ceramic, frosted glass) or unlit
/// (glowing). Metal, ceramic and frosted glass are the experimental looks of D24.
public enum FaceStyle: String, Codable, CaseIterable, Sendable {
    case matte, glossy, glowing, metal, ceramic
    case frostedGlass = "frosted"
}

/// Image pattern on the faces (D24). It replaces the colour source on the faces; edges keep it.
public enum SurfacePattern: String, Codable, CaseIterable, Sendable {
    case none, grid, marble, wood
}

/// Edge colour: the same colour source as the faces, or plain light.
public enum EdgeColorMode: String, Codable, CaseIterable, Sendable {
    case matchFaces = "faces"
    case light
}

/// The display layers (DESIGN 6.1).
public struct DisplaySettings: Codable, Equatable, Sendable {
    public var edgesVisible: Bool
    /// Tube radius as a fixed length: value × 0.375 m in the volume, twice that in the room, so
    /// tubes keep their size in metres when zoomed or resized (D28).
    public var edgeThickness: Double
    public var edgeColor: EdgeColorMode
    /// Face opacity 0…1.
    public var faceOpacity: Double
    public var colorSource: ColorSource
    public var faceStyle: FaceStyle
    /// Explode fraction 0…0.4: each cell shrinks towards its centre.
    public var explode: Double
    /// Shadow of the shadow on the floor disc (DESIGN 6.4).
    public var floorShadow: Bool
    /// The object's four 4D axes, rotated and projected with it (D20).
    public var axesVisible: Bool
    /// Image pattern on the faces (D24).
    public var pattern: SurfacePattern
    /// Thickness of the faces, a fixed length like `edgeThickness`; 0 = thin films (D24, D28).
    public var faceThickness: Double

    public init(edgesVisible: Bool, edgeThickness: Double, edgeColor: EdgeColorMode,
                faceOpacity: Double, colorSource: ColorSource, faceStyle: FaceStyle,
                explode: Double, floorShadow: Bool, axesVisible: Bool = false,
                pattern: SurfacePattern = .none, faceThickness: Double = 0) {
        self.edgesVisible = edgesVisible
        self.edgeThickness = edgeThickness
        self.edgeColor = edgeColor
        self.faceOpacity = faceOpacity
        self.colorSource = colorSource
        self.faceStyle = faceStyle
        self.explode = explode
        self.floorShadow = floorShadow
        self.axesVisible = axesVisible
        self.pattern = pattern
        self.faceThickness = faceThickness
    }

    /// Range of the face thickness control.
    public static let faceThicknessRange: ClosedRange<Double> = 0...0.08
    /// Range of the face opacity.
    public static let opacityRange: ClosedRange<Double> = 0...1

    /// Range of the explode control.
    public static let explodeRange: ClosedRange<Double> = 0...0.4
    /// Minimum explode applied automatically by the per-cell colour source.
    public static let perCellMinimumExplode = 0.05
    /// Range of the edge thickness control.
    public static let thicknessRange: ClosedRange<Double> = 0.002...0.04

    /// The explode fraction actually used for an object kind. Per-cell colour forces a
    /// minimum of 5 %, because every face belongs to two cells (DESIGN 6.3, D10).
    public func effectiveExplode(for kind: ObjectKind) -> Double {
        guard kind == .polytope else { return 0 }
        if colorSource == .perCell { return max(explode, Self.perCellMinimumExplode) }
        return explode
    }

    /// The colour source actually used: falls back to `.uniform` if the chosen source does not
    /// apply to the object kind.
    public func effectiveColorSource(for kind: ObjectKind) -> ColorSource {
        colorSource.isAvailable(for: kind) ? colorSource : .uniform
    }
}

/// Motion stage: angular velocity Ω and friction (DESIGN 4). The orientation R is kept
/// separately in `ViewState.orientation`.
public struct MotionSettings: Codable, Equatable, Sendable {
    public var omega: AngularVelocity4D
    /// Damping rate per second; 0 = off (the default), so the object keeps rotating.
    public var friction: Double

    public init(omega: AngularVelocity4D = .zero, friction: Double = 0) {
        self.omega = omega
        self.friction = friction
    }

    public static let frictionRange: ClosedRange<Double> = 0...2
    /// Range of each plane's speed in radians per second, for the sliders, throws, launch
    /// arguments and saved settings alike (D41).
    public static let speedRange: ClosedRange<Double> = -4...4
}

/// Transparency method for faces with opacity below 100 % (spike S1, DESIGN 11.5).
public enum TransparencyMethod: String, Codable, CaseIterable, Sendable {
    /// `.add` blending without depth writes: order independent, glowing look.
    case additive
    /// Alpha blending; triangles sorted back to front every frame, towards the side of the volume
    /// the viewer is on (`ViewSide`).
    case sorted
    /// One entity pair per cell (only with explode > 0); RealityKit sorts the entities.
    case perCellEntities = "cells"
}

extension TransparencyMethod {
    /// Per-cell entities cost a pair of entities and meshes per cell, updated every frame: the
    /// exploded 120-cell ran at 40 Hz and the 600-cell at 5 Hz in the simulator, and the device
    /// stopped (D31). Above this many cells, sorted is used instead.
    public static let maxCellsForPerCellEntities = 48

    /// The method actually used, the one rule for every fallback (D47); each falls back to sorted:
    /// - per-cell entities need explode > 0 and at most `maxCellsForPerCellEntities` cells (D31);
    /// - additive blending adds light patterns up to white (D24), and its `.add` programs are
    ///   created asynchronously, so until they are ready it cannot be drawn.
    public func effective(cellCount: Int, explode: Double, hasPattern: Bool = false,
                          additiveReady: Bool = true) -> TransparencyMethod {
        switch self {
        case .sorted:
            return .sorted
        case .perCellEntities:
            return explode > 0 && cellCount <= Self.maxCellsForPerCellEntities ? self : .sorted
        case .additive:
            return !hasPattern && additiveReady ? self : .sorted
        }
    }
}

/// How the floor shadow is made (spike S4, DESIGN 11.7).
public enum FloorShadowMethod: String, Codable, CaseIterable, Sendable {
    /// `DirectionalLightComponent` with a shadow onto the floor disc.
    case directionalLight = "light"
    /// `GroundingShadowComponent` (the fallback).
    case grounding
}

/// Settings of the Developer tab (DESIGN 8.3).
public struct DeveloperSettings: Codable, Equatable, Sendable {
    public var floorShadowMethod: FloorShadowMethod = .directionalLight
    public var transparency: TransparencyMethod
    public var showsPerformanceOverlay: Bool
    public var showsGestureTest: Bool
    /// Snapshot mode: time does not advance.
    public var freezesTime: Bool
    /// Stress test for spike S2: always use the finest subdivision (n = 8, m = 3).
    public var forcesFineSubdivision: Bool

    public init(transparency: TransparencyMethod = .additive, showsPerformanceOverlay: Bool = false,
                showsGestureTest: Bool = false, freezesTime: Bool = false, forcesFineSubdivision: Bool = false) {
        self.transparency = transparency
        self.showsPerformanceOverlay = showsPerformanceOverlay
        self.showsGestureTest = showsGestureTest
        self.freezesTime = freezesTime
        self.forcesFineSubdivision = forcesFineSubdivision
    }

    /// The part kept between launches (D43): the two methods, which choose a look. The
    /// diagnostics (overlay, gesture test, frozen time, fine subdivision) start off every time.
    public var withoutDiagnostics: DeveloperSettings {
        var d = DeveloperSettings(transparency: transparency)
        d.floorShadowMethod = floorShadowMethod
        return d
    }
}

/// Parameters of the duoprism p×q.
public struct DuoprismParameters: Codable, Equatable, Sendable {
    public var p: Int
    public var q: Int

    public init(p: Int, q: Int) {
        self.p = p
        self.q = q
    }

    public static let range: ClosedRange<Int> = 3...24
}

/// Which side of the volume the viewer is on (D17). A volumetric window gets no head pose, only
/// this (`onVolumeViewpointChange`); it sets the sort direction of the "sorted" transparency method.
public enum ViewSide: String, Codable, CaseIterable, Sendable {
    case front, right, back, left

    /// Unit vector from the content towards the viewer, in box coordinates (y up, +z towards the
    /// front). That "right" means the viewer stands at +x is an assumption [verify on device].
    public var direction: SIMD3<Float> {
        switch self {
        case .front: [0, 0, 1]
        case .right: [1, 0, 0]
        case .back: [0, 0, -1]
        case .left: [-1, 0, 0]
        }
    }
}

extension Orientation4D {
    /// Start and reset orientation (D18): a pure 3D tilt, 35° in XZ and then 25° in YZ. W stays
    /// the projection axis, so in perspective the tesseract shows its cube inside a cube, and every
    /// object is seen obliquely instead of edge-on.
    public static let start = Orientation4D(matrix: Rotation4D.plane(.yz, angle: 25 * .pi / 180)
                                                * Rotation4D.plane(.xz, angle: 35 * .pi / 180))
}

/// The single source of truth for what is shown (DESIGN 9.2). Presets are named partial
/// assignments of it; it is `Codable` for launch arguments, snapshots and saving later.
public struct ViewState: Codable, Equatable, Sendable {
    public var object: ObjectID
    public var duoprism: DuoprismParameters
    public var projection: ProjectionSettings
    public var display: DisplaySettings
    public var motion: MotionSettings
    public var orientation: Orientation4D
    /// The user's size factor on top of the automatic size (`SizeFit`, D15).
    public var scale: Double
    public var developer: DeveloperSettings

    public init(object: ObjectID = .tesseract,
                duoprism: DuoprismParameters = DuoprismParameters(p: 3, q: 4),
                projection: ProjectionSettings = ProjectionPreset.perspective.settings,
                display: DisplaySettings = .defaults,
                motion: MotionSettings = MotionSettings(omega: MotionPreset.simple.omega),
                orientation: Orientation4D = .start,
                scale: Double = 1,
                developer: DeveloperSettings = DeveloperSettings()) {
        self.object = object
        self.duoprism = duoprism
        self.projection = projection
        self.display = display
        self.motion = motion
        self.orientation = orientation
        self.scale = scale
        self.developer = developer
    }

    public static let scaleRange: ClosedRange<Double> = 0.25...4

    /// The state with every number limited to its range: one range per field (D41), the same for
    /// the controls, the gestures, launch arguments and saved settings.
    public func clamped() -> ViewState {
        var s = self
        s.duoprism.p = duoprism.p.clamped(to: DuoprismParameters.range)
        s.duoprism.q = duoprism.q.clamped(to: DuoprismParameters.range)
        s.projection.kappa = projection.kappa.clamped(to: ProjectionSettings.range)
        s.projection.spherize = projection.spherize.clamped(to: ProjectionSettings.range)
        s.display.edgeThickness = display.edgeThickness.clamped(to: DisplaySettings.thicknessRange)
        s.display.faceOpacity = display.faceOpacity.clamped(to: DisplaySettings.opacityRange)
        s.display.explode = display.explode.clamped(to: DisplaySettings.explodeRange)
        s.display.faceThickness = display.faceThickness.clamped(to: DisplaySettings.faceThicknessRange)
        s.motion.omega = motion.omega.clamped(to: MotionSettings.speedRange)
        s.motion.friction = motion.friction.clamped(to: MotionSettings.frictionRange)
        s.scale = scale.clamped(to: Self.scaleRange)
        return s
    }
}

extension DisplaySettings {
    /// The start-up display: the Glass preset with colour by W.
    public static let defaults: DisplaySettings = {
        var d = DisplaySettings(edgesVisible: true, edgeThickness: 0.012, edgeColor: .matchFaces,
                                faceOpacity: 0.25, colorSource: .byW, faceStyle: .glowing,
                                explode: 0, floorShadow: true)
        DisplayPreset.glass.apply(to: &d)
        return d
    }()
}
