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
    /// "?" mode: tapping a control explains it in the info window instead of using it (D22).
    var isHelpMode = false
    /// What the info window shows.
    var helpTopic: HelpTopic = .about
    /// Whether the info window is open; the volume and the controls open it (D25, D40).
    var showsHelp = false
    /// Set when the volume or the controls window closes: every other window, and the room, then
    /// close themselves, so the whole app closes (D34).
    var isClosing = false

    /// Shows a topic in the info window.
    func showHelp(_ topic: HelpTopic) {
        helpTopic = topic
        showsHelp = true
    }

    /// Closes the info window and leaves "?" mode.
    func closeHelp() {
        showsHelp = false
        isHelpMode = false
    }
    /// Whether the settings are saved between launches; false in snapshot mode (D29).
    @ObservationIgnored var persistsSettings = false
    /// The settings to keep between launches (D29).
    var savedSettings: SavedSettings { SavedSettings(state: viewState, gestureMapping: gestureMapping) }

    /// Whether the immersive space is open.
    var isRoomOpen = false
    /// Launch-argument problems, shown in the Developer section.
    var launchProblems: [String] = []
    /// Side of the volume the viewer is on, as reported by the system (D17).
    var systemViewSide: ViewSide = .front
    /// Fixed by the `-viewpoint` launch argument; then system updates are ignored.
    var viewSideOverride: ViewSide?
    /// The viewer side used for sorting.
    var viewSide: ViewSide { viewSideOverride ?? systemViewSide }
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

    /// Reset: R back to the start orientation (D18).
    func resetOrientation() { setOrientation(Orientation4D.start.matrix) }

    /// Stop: Ω = 0.
    func stop() { motion.omega = .zero }

    /// Choosing a material, pattern or thickness means the faces should be seen (D24): hidden
    /// faces (opacity near 0, e.g. Wireframe) become opaque, or half transparent for frosted glass.
    func showFaces() {
        let target = display.faceStyle == .frostedGlass ? 0.5 : 1
        if display.faceOpacity < 0.05 { display.faceOpacity = target }
        if display.faceStyle == .frostedGlass, display.faceOpacity > 0.9 { display.faceOpacity = target }
    }

    /// "Reset all": every setting back to its default, including the developer settings, the
    /// drag mapping and a viewer side fixed by launch argument. Tab and help mode stay.
    func resetAll() {
        viewState = ViewState()
        gestureMapping = GestureMapping()
        viewSideOverride = nil
    }

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
        viewSideOverride = config.viewSide
        launchProblems = config.problems
        if let raw = config.help {
            if let topic = HelpTopic(launchValue: raw) {
                showHelp(topic)
                isHelpMode = topic != .about
            } else {
                launchProblems.append("help=\(raw)")
            }
        }
    }

    /// The colour source and explode that are actually used for the current object.
    var effectiveColorSource: ColorSource { display.effectiveColorSource(for: object.kind) }
    var effectiveExplode: Double { display.effectiveExplode(for: object.kind) }
}

/// Tabs of the control panel (DESIGN 3.6). The raw value is the `-panel` launch argument.
enum PanelTab: String, CaseIterable, Identifiable {
    case object, projection, display, surface, motion, developer
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
