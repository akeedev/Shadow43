// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Maps gestures to rotations (DESIGN 8.1, 10.7, variant A). Pure functions so they can be tested.
public struct GestureMapping: Codable, Equatable, Sendable {
    /// k: radians of 4D rotation per metre of drag.
    public var radiansPerMetre: Double
    /// +1 or −1: whether dragging right turns X towards +W or −W.
    public var sign: Double

    /// Default k: 10 rad per metre of drag, a full turn per 0.63 m (D26). The first value, 2π per
    /// 0.3 m, was far too sensitive on the device; the user settled on 10.
    public static let defaultRadiansPerMetre = 10.0
    /// Range of the Developer slider, with the default in its middle.
    public static let radiansPerMetreRange: ClosedRange<Double> = 2...18

    public init(radiansPerMetre: Double = GestureMapping.defaultRadiansPerMetre, sign: Double = 1) {
        self.radiansPerMetre = radiansPerMetre
        self.sign = sign
    }

    /// k limited to its range and the sign to ±1.
    public func clamped() -> GestureMapping {
        GestureMapping(radiansPerMetre: radiansPerMetre.clamped(to: Self.radiansPerMetreRange),
                       sign: sign < 0 ? -1 : 1)
    }

    /// One-hand drag by Δ (scene coordinates, metres): the drag direction tips towards W,
    /// `R ← G(Δ̂, e_w, k·|Δ|) · R`. Right/left → XW, up/down → YW, forward/back → ZW.
    public func rotation(forDrag delta: SIMD3<Double>) -> simd_double4x4 {
        let length = simd_length(delta)
        guard length > 0 else { return matrix_identity_double4x4 }
        let direction = delta / length
        return Rotation4D.plane(a: SIMD4(direction, 0), b: Rotation4D.axis(3),
                                angle: sign * radiansPerMetre * length)
    }

    /// Throw: Ω_xw, Ω_yw, Ω_zw from the hand velocity (m/s); the other planes are zero.
    public func angularVelocity(forDragVelocity v: SIMD3<Double>) -> AngularVelocity4D {
        let k = sign * radiansPerMetre
        return AngularVelocity4D(xw: k * v.x, yw: k * v.y, zw: k * v.z)
    }

    /// Two-hand twist: a 3D rotation that leaves W fixed, `R ← diag(M(q), 1) · R`.
    public static func rotation(for quaternion: simd_quatd) -> simd_double4x4 {
        Rotation4D.embed3D(simd_double3x3(quaternion))
    }

    /// The twist is applied in increments: the change from the gesture's previous rotation `last`
    /// to its current one `q`, both in the content's axes (D50).
    public static func twistIncrement(from last: simd_quatd, to q: simd_quatd) -> simd_double4x4 {
        rotation(for: q * last.inverse)
    }

    /// Two-hand pinch: the size factor at the start of the gesture times the magnification,
    /// within the size range. It does not catch.
    public static func magnifiedScale(start: Double, magnification: Double) -> Double {
        (start * magnification).clamped(to: ViewState.scaleRange)
    }
}

/// One pinch on the object, from touch to release (DESIGN 10.7). It turns the object while the
/// hand moves; it catches the object (Ω = 0) once the hand has moved or held a moment, so a quick
/// tap or double tap leaves the motion alone (D49); and on release it may throw.
public struct GrabSession: Sendable {
    /// A grab catches once the hand has moved this far (metres) …
    public static let catchDistance = 0.005
    /// … or held this long (seconds).
    public static let catchDelay: TimeInterval = 0.25
    /// Releases slower than this (m/s) do not throw.
    public static let minimumThrowSpeed = 0.05

    public let startTime: TimeInterval
    public let startPosition: SIMD3<Double>
    public private(set) var lastPosition: SIMD3<Double>
    /// Whether this grab has caught the object.
    public private(set) var hasCaught = false
    private var tracker = VelocityTracker()

    public init(time: TimeInterval, position: SIMD3<Double>) {
        startTime = time
        startPosition = position
        lastPosition = position
        tracker.add(time: time, position: position)
    }

    /// The hand is at `position`. Returns the drag step to apply to R, zero while a two-hand
    /// gesture owns the object.
    public mutating func move(to position: SIMD3<Double>, at time: TimeInterval,
                              twoHandGesture: Bool) -> SIMD3<Double> {
        tracker.add(time: time, position: position)
        let step = position - lastPosition
        lastPosition = position
        return twoHandGesture ? .zero : step
    }

    /// True exactly once: when the hand has moved `catchDistance` from where it started, or the
    /// grab has lasted `catchDelay`.
    public mutating func catchesNow(at time: TimeInterval) -> Bool {
        guard !hasCaught else { return false }
        let moved = simd_distance(lastPosition, startPosition) >= Self.catchDistance
        guard moved || time - startTime >= Self.catchDelay else { return false }
        hasCaught = true
        return true
    }

    /// Hand velocity over the last 0.1 s (m/s).
    public var velocity: SIMD3<Double> { tracker.velocity }

    /// The angular velocity of a throw on release, or nil: a grab that never caught (a tap), a
    /// hand slower than `minimumThrowSpeed`, or a two-hand gesture still running. Limited to the
    /// speed range by scaling, so the direction of the throw stays.
    public func throwVelocity(mapping: GestureMapping, twoHandGesture: Bool) -> AngularVelocity4D? {
        let v = velocity
        guard hasCaught, !twoHandGesture, simd_length(v) >= Self.minimumThrowSpeed else { return nil }
        return clampedThrow(mapping.angularVelocity(forDragVelocity: v))
    }
}

/// Estimates the velocity of a drag from its recent samples (DESIGN 10.7: last 0.1 s).
public struct VelocityTracker: Sendable {
    public var window: TimeInterval
    private var samples: [(time: TimeInterval, position: SIMD3<Double>)] = []

    public init(window: TimeInterval = 0.1) {
        self.window = window
    }

    public mutating func reset() { samples.removeAll() }

    public mutating func add(time: TimeInterval, position: SIMD3<Double>) {
        samples.append((time, position))
        // Keep one sample older than the window as the reference point.
        while samples.count > 2, let second = samples.dropFirst().first, time - second.time >= window {
            samples.removeFirst()
        }
    }

    /// Average velocity over (about) the last `window` seconds; zero without enough samples.
    public var velocity: SIMD3<Double> {
        guard let last = samples.last, let first = samples.first, last.time > first.time else { return .zero }
        return (last.position - first.position) / (last.time - first.time)
    }
}

/// Scales a throw down so that no plane exceeds the speed range (D41) and a careless flick does
/// not spin the object wildly.
public func clampedThrow(_ omega: AngularVelocity4D,
                         maxRate: Double = MotionSettings.speedRange.upperBound) -> AngularVelocity4D {
    let m = omega.maxMagnitude
    return m > maxRate ? omega.scaled(by: maxRate / m) : omega
}
