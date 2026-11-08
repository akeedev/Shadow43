// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import Observation
import simd

/// The app's observable copy of `ViewState`, shared by every scene (DESIGN 6.2).
///
/// Each stage is its own stored property so that SwiftUI views only update when the stage they
/// show changes. The orientation R changes every frame and is therefore not observed.
@MainActor @Observable
final class AppModel {
    var object: ObjectID
    var duoprism: DuoprismParameters
    var projection: ProjectionSettings
    var display: DisplaySettings
    var motion: MotionSettings
    var scale: Double
    var developer: DeveloperSettings

    /// Orientation R. Written by the render system every frame; not observed.
    @ObservationIgnored var orientation: simd_double4x4
    /// Incremented whenever R changes outside the frame loop (reset, gestures, snapshot).
    @ObservationIgnored private(set) var orientationRevision = 0

    /// Control-panel tab shown.
    var panelTab: PanelTab = .object
    /// Whether the immersive space is open.
    var isRoomOpen = false
    /// Launch-argument problems, shown in the Developer section.
    var launchProblems: [String] = []
    /// Latest performance numbers from the render system (performance overlay, S2).
    var stats = RenderStats()
    /// Gesture → rotation mapping (k and sign, DESIGN 6.4).
    var gestureMapping = GestureMapping()
    /// Raw gesture values for the gesture test (S3).
    let gestureLog = GestureLog()

    init(state: ViewState = ViewState()) {
        object = state.object
        duoprism = state.duoprism
        projection = state.projection
        display = state.display
        motion = state.motion
        scale = state.scale
        developer = state.developer
        orientation = state.orientation.matrix
    }

    /// The full state as one value (for snapshots and presets).
    var viewState: ViewState {
        get {
            ViewState(object: object, duoprism: duoprism, projection: projection, display: display,
                      motion: motion, orientation: Orientation4D(matrix: orientation), scale: scale,
                      developer: developer)
        }
        set {
            object = newValue.object
            duoprism = newValue.duoprism
            projection = newValue.projection
            display = newValue.display
            motion = newValue.motion
            scale = newValue.scale
            developer = newValue.developer
            setOrientation(newValue.orientation.matrix)
        }
    }

    /// Sets R from outside the frame loop.
    func setOrientation(_ r: simd_double4x4) {
        orientation = r
        orientationRevision += 1
    }

    /// Reset: R back to the identity.
    func resetOrientation() { setOrientation(matrix_identity_double4x4) }

    /// Stop: Ω = 0.
    func stop() { motion.omega = .zero }

    @ObservationIgnored private var lastTick: TimeInterval?

    /// Advances the motion once per frame (DESIGN 6.3, step 1). Every host's renderer calls it;
    /// calls less than 2 ms apart belong to the same frame and are ignored, so two open scenes
    /// do not rotate twice as fast. Returns whether R changed.
    @discardableResult
    func tick(now: TimeInterval) -> Bool {
        guard let last = lastTick else {
            lastTick = now
            return false
        }
        let dt = now - last
        guard dt >= 0.002 else { return false }
        lastTick = now
        guard !developer.freezesTime, !motion.omega.isZero else { return false }
        let step = min(dt, 0.1)
        orientation = Rotation4D.advance(orientation, omega: motion.omega, dt: step)
        if motion.friction > 0 {
            motion.omega = Rotation4D.damp(motion.omega, friction: motion.friction, dt: step)
        }
        return true
    }

    /// Applies launch arguments (snapshot mode, DESIGN 6.9).
    func apply(_ config: LaunchConfiguration) {
        var state = config.state
        if let t = config.time { state = LaunchConfiguration.integrate(state, time: t) }
        viewState = state
        if let tab = config.panel.flatMap(PanelTab.init(rawValue:)) { panelTab = tab }
        launchProblems = config.problems
    }

    /// The colour source and explode that are actually used for the current object.
    var effectiveColorSource: ColorSource { display.effectiveColorSource(for: object.kind) }
    var effectiveExplode: Double { display.effectiveExplode(for: object.kind) }
}

/// Tabs of the control panel (DESIGN 3.6). The raw value is the `-panel` launch argument.
enum PanelTab: String, CaseIterable, Identifiable {
    case object, projection, display, motion, developer
    var id: String { rawValue }
}

/// Numbers shown by the performance overlay (spike S2).
struct RenderStats: Equatable {
    var frameTimeMs: Double = 0
    /// Whole per-frame update on the CPU.
    var cpuTimeMs: Double = 0
    /// Of which the FrameBuilder pipeline (rotate, project, normals, tubes); the rest is upload.
    var buildTimeMs: Double = 0
    var triangles: Int = 0
    var vertices: Int = 0
}
