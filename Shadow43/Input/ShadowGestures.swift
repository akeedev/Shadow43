// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import RealityKit
import simd
import Spatial
import SwiftUI

/// Gestures, variant A (DESIGN 8.1, 10.7): standard visionOS gestures on the content's input
/// target. Every gesture has a control-panel equivalent (Motion section). The logic is in Core4D
/// (`GrabSession`, `GestureMapping`), where it is tested.
///
/// - Pinch + drag: 4D rotation, the drag direction tips towards W.
/// - Two hands twist: 3D rotation. Two hands apart/together: scale.
/// - Pinch and hold, or move: catch. Release with momentum: throw. Double tap: reset orientation.
struct ShadowGestures: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var grab: GrabSession?
    @State private var lastTwist: simd_quatd?
    @State private var scaleAtStart: Double?

    func body(content: Content) -> some View {
        content
            .gesture(dragGesture)
            .simultaneousGesture(twistGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(doubleTapGesture)
    }

    /// Only the object's input target (`ShadowInputComponent`), not e.g. the room's floor disc.
    private static let target = QueryPredicate<Entity>.has(ShadowInputComponent.self)

    /// Whether a two-hand gesture owns the object; drags are then ignored.
    private var twoHandGesture: Bool { lastTwist != nil || scaleAtStart != nil }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(where: Self.target)
            .onChanged { value in
                let p = SIMD3<Double>(value.convert(value.location3D, from: .local, to: value.entity))
                let now = ProcessInfo.processInfo.systemUptime
                if grab == nil {
                    grab = GrabSession(time: now, position: p)
                    model.gestureLog.record(drag: "begin at \(format(p))")
                    catchWhenHeld(startedAt: now)
                }
                guard var session = grab else { return }
                let step = session.move(to: p, at: now, twoHandGesture: twoHandGesture)
                // A grab catches once it has moved or held a moment; a quick tap does not (D49).
                if session.catchesNow(at: now) { model.stop() }
                grab = session
                if simd_length(step) > 0 {
                    model.setOrientation(model.gestureMapping.rotation(forDrag: step) * model.orientation)
                }
                model.gestureLog.record(drag: "Δ \(format(step)) m, v \(format(session.velocity)) m/s")
            }
            .onEnded { _ in
                if let omega = grab?.throwVelocity(mapping: model.gestureMapping, twoHandGesture: twoHandGesture) {
                    model.motion.omega = omega
                }
                model.gestureLog.record(drag: "end, throw v \(format(grab?.velocity ?? .zero)) m/s")
                grab = nil
            }
    }

    /// A hand that holds still sends no more changes, so the hold is checked once more when the
    /// catch delay has passed.
    private func catchWhenHeld(startedAt start: TimeInterval) {
        Task {
            try? await Task.sleep(for: .seconds(GrabSession.catchDelay))
            guard var session = grab, session.startTime == start else { return }
            if session.catchesNow(at: ProcessInfo.processInfo.systemUptime) { model.stop() }
            grab = session
        }
    }

    private var twistGesture: some Gesture {
        RotateGesture3D()
            .targetedToEntity(where: Self.target)
            .onChanged { value in
                // In the input target's axes, which are the content's: the SDK converts from
                // SwiftUI's y-down space and includes the room's heading (D50) [verify on device].
                let q = simd_quatd(vector: SIMD4<Double>(value.convert(value.rotation, from: .local, to: value.entity).vector))
                if let last = lastTwist {
                    model.setOrientation(GestureMapping.twistIncrement(from: last, to: q) * model.orientation)
                } else {
                    // Catch: a twist stops the rotation.
                    model.stop()
                }
                lastTwist = q
                model.gestureLog.record(rotate: "angle \(String(format: "%.1f", q.angle * 180 / .pi))°, axis \(format(q.axis))")
            }
            .onEnded { _ in lastTwist = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .targetedToEntity(where: Self.target)
            .onChanged { value in
                let start = scaleAtStart ?? model.scale
                scaleAtStart = start
                model.scale = GestureMapping.magnifiedScale(start: start, magnification: value.magnification)
                model.gestureLog.record(magnify: String(format: "× %.2f → scale %.2f", value.magnification, model.scale))
            }
            .onEnded { _ in scaleAtStart = nil }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .targetedToEntity(where: Self.target)
            .onEnded { _ in
                model.resetOrientation()
                model.gestureLog.record(tap: "double tap → reset")
            }
    }
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
