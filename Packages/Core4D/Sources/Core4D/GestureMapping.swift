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

/// Clamps a throw so that a careless flick does not spin the object wildly.
public func clampedThrow(_ omega: AngularVelocity4D, maxRate: Double = 4) -> AngularVelocity4D {
    let m = omega.maxMagnitude
    return m > maxRate ? omega.scaled(by: maxRate / m) : omega
}
