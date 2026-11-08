// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import RealityKit
import simd
import Spatial
import SwiftUI

/// Gestures, variant A (DESIGN 3.6, 6.4): standard visionOS gestures on the content's input
/// target. Every gesture has a control-panel equivalent (Motion section).
///
/// - Pinch + drag: 4D rotation, the drag direction tips towards W.
/// - Two hands twist: 3D rotation. Two hands apart/together: scale.
/// - Release with momentum: throw. Pinch and hold: catch. Double tap: reset orientation.
struct ShadowGestures: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var drag = DragState()
    @State private var lastTwist: simd_quatd?
    @State private var scaleAtStart: Double?

    /// Throws slower than this (m/s) leave the object caught.
    static let minimumThrowSpeed = 0.05

    func body(content: Content) -> some View {
        content
            .gesture(dragGesture)
            .simultaneousGesture(twistGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(doubleTapGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToAnyEntity()
            .onChanged { value in
                let p = SIMD3<Double>(value.convert(value.location3D, from: .local, to: value.entity))
                let now = ProcessInfo.processInfo.systemUptime
                if !drag.isActive {
                    // Catch: grabbing stops the rotation.
                    drag = DragState(isActive: true, last: p)
                    model.stop()
                    model.gestureLog.record(drag: "begin at \(format(p))")
                }
                drag.tracker.add(time: now, position: p)
                // Two-hand gestures own the object while they run.
                guard lastTwist == nil, scaleAtStart == nil else {
                    drag.last = p
                    return
                }
                let delta = p - drag.last
                drag.last = p
                if simd_length(delta) > 0 {
                    model.setOrientation(model.gestureMapping.rotation(forDrag: delta) * model.orientation)
                }
                model.gestureLog.record(drag: "Δ \(format(delta)) m, v \(format(drag.tracker.velocity)) m/s")
            }
            .onEnded { _ in
                let v = drag.tracker.velocity
                if simd_length(v) >= Self.minimumThrowSpeed, lastTwist == nil, scaleAtStart == nil {
                    model.motion.omega = clampedThrow(model.gestureMapping.angularVelocity(forDragVelocity: v))
                }
                model.gestureLog.record(drag: "end, throw v \(format(v)) m/s")
                drag = DragState()
            }
    }

    private var twistGesture: some Gesture {
        RotateGesture3D()
            .targetedToAnyEntity()
            .onChanged { value in
                let q = Self.realityKitQuaternion(value.rotation.quaternion)
                if let last = lastTwist {
                    let delta = q * last.inverse
                    model.setOrientation(GestureMapping.rotation(for: delta) * model.orientation)
                } else {
                    model.stop()
                }
                lastTwist = q
                model.gestureLog.record(rotate: "angle \(String(format: "%.1f", q.angle * 180 / .pi))°, axis \(format(q.axis))")
            }
            .onEnded { _ in lastTwist = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let start = scaleAtStart ?? model.scale
                scaleAtStart = start
                model.scale = (start * value.magnification).clamped(to: ViewState.scaleRange)
                model.gestureLog.record(magnify: String(format: "× %.2f → scale %.2f", value.magnification, model.scale))
            }
            .onEnded { _ in scaleAtStart = nil }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .targetedToAnyEntity()
            .onEnded { _ in
                model.resetOrientation()
                model.gestureLog.record(tap: "double tap → reset")
            }
    }

    /// SwiftUI's 3D gesture space has y pointing down; RealityKit has y up. Mirroring y maps a
    /// rotation (x, y, z, w) to (−x, y, −z, w) [verify on device].
    static func realityKitQuaternion(_ q: simd_quatd) -> simd_quatd {
        simd_quatd(ix: -q.imag.x, iy: q.imag.y, iz: -q.imag.z, r: q.real)
    }
}

/// State of a running one-hand drag.
struct DragState {
    var isActive = false
    var last = SIMD3<Double>.zero
    var tracker = VelocityTracker()
}

func format(_ v: SIMD3<Double>) -> String {
    String(format: "(%.3f, %.3f, %.3f)", v.x, v.y, v.z)
}

func format(_ v: SIMD3<Float>) -> String {
    format(SIMD3<Double>(v))
}

/// Raw gesture values for the gesture test scene (spike S3).
@MainActor @Observable
final class GestureLog {
    var drag = "–"
    var rotate = "–"
    var magnify = "–"
    var tap = "–"
    var manipulation = "–"
    /// Only recorded while the gesture test is visible, to avoid needless view updates.
    @ObservationIgnored var isRecording = false

    func record(drag: String) { if isRecording { self.drag = drag } }
    func record(rotate: String) { if isRecording { self.rotate = rotate } }
    func record(magnify: String) { if isRecording { self.magnify = magnify } }
    func record(tap: String) { if isRecording { self.tap = tap } }
    func record(manipulation: String) { if isRecording { self.manipulation = manipulation } }
}
