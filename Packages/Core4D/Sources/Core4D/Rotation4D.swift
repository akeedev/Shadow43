// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// One of the six coordinate planes of ℝ⁴ in which a rotation can take place.
/// XY, XZ and YZ turn the shadow rigidly; XW, YW and ZW deform it (DESIGN 4).
public enum RotationPlane: String, CaseIterable, Codable, Sendable {
    case xy, xz, yz, xw, yw, zw

    /// The two coordinate axes (0 = x … 3 = w). Positive angles turn the first towards the second.
    public var axes: (Int, Int) {
        switch self {
        case .xy: (0, 1)
        case .xz: (0, 2)
        case .yz: (1, 2)
        case .xw: (0, 3)
        case .yw: (1, 3)
        case .zw: (2, 3)
        }
    }

    /// True for the three planes that involve W and therefore deform the shadow.
    public var involvesW: Bool { axes.1 == 3 }
}

/// Angular velocity Ω: one rate in radians per second for each rotation plane.
public struct AngularVelocity4D: Codable, Equatable, Sendable {
    public var xy: Double
    public var xz: Double
    public var yz: Double
    public var xw: Double
    public var yw: Double
    public var zw: Double

    public init(xy: Double = 0, xz: Double = 0, yz: Double = 0,
                xw: Double = 0, yw: Double = 0, zw: Double = 0) {
        self.xy = xy; self.xz = xz; self.yz = yz
        self.xw = xw; self.yw = yw; self.zw = zw
    }

    public static let zero = AngularVelocity4D()

    public subscript(plane: RotationPlane) -> Double {
        get {
            switch plane {
            case .xy: xy
            case .xz: xz
            case .yz: yz
            case .xw: xw
            case .yw: yw
            case .zw: zw
            }
        }
        set {
            switch plane {
            case .xy: xy = newValue
            case .xz: xz = newValue
            case .yz: yz = newValue
            case .xw: xw = newValue
            case .yw: yw = newValue
            case .zw: zw = newValue
            }
        }
    }

    public var isZero: Bool { RotationPlane.allCases.allSatisfy { self[$0] == 0 } }

    /// The largest absolute rate over all planes.
    public var maxMagnitude: Double { RotationPlane.allCases.map { abs(self[$0]) }.max() ?? 0 }

    public func scaled(by factor: Double) -> AngularVelocity4D {
        var result = self
        for plane in RotationPlane.allCases { result[plane] = self[plane] * factor }
        return result
    }

    /// Every plane's rate limited to `range` on its own.
    public func clamped(to range: ClosedRange<Double>) -> AngularVelocity4D {
        var result = self
        for plane in RotationPlane.allCases { result[plane] = self[plane].clamped(to: range) }
        return result
    }
}

/// A 4×4 rotation matrix R, the orientation of the object (DESIGN 4). Codable as 16 numbers
/// in column-major order.
public struct Orientation4D: Equatable, Sendable, Codable {
    public var matrix: simd_double4x4

    public init(matrix: simd_double4x4) { self.matrix = matrix }

    public static let identity = Orientation4D(matrix: matrix_identity_double4x4)

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var columns = [SIMD4<Double>](repeating: .zero, count: 4)
        for c in 0..<4 {
            for r in 0..<4 { columns[c][r] = try container.decode(Double.self) }
        }
        matrix = simd_double4x4(columns: (columns[0], columns[1], columns[2], columns[3]))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for c in 0..<4 {
            for r in 0..<4 { try container.encode(matrix[c][r]) }
        }
    }
}

/// Rotation math in ℝ⁴ (DESIGN 10.2). All rotations are applied in the world frame, i.e.
/// multiplied from the left.
public enum Rotation4D {
    /// Unit vector along axis `i` (0 = x … 3 = w).
    public static func axis(_ i: Int) -> SIMD4<Double> {
        var v = SIMD4<Double>.zero
        v[i] = 1
        return v
    }

    /// Outer product a·bᵀ.
    static func outer(_ a: SIMD4<Double>, _ b: SIMD4<Double>) -> simd_double4x4 {
        simd_double4x4(columns: (a * b.x, a * b.y, a * b.z, a * b.w))
    }

    /// Rotation by `angle` in the plane spanned by the orthonormal vectors a and b; positive
    /// angles turn a towards b:
    /// `G(a, b, θ) = I + (cos θ − 1)(a aᵀ + b bᵀ) + sin θ (b aᵀ − a bᵀ)`.
    public static func plane(a: SIMD4<Double>, b: SIMD4<Double>, angle: Double) -> simd_double4x4 {
        let c = cos(angle) - 1
        let s = sin(angle)
        let sym = outer(a, a) + outer(b, b)
        let skew = outer(b, a) - outer(a, b)
        return matrix_identity_double4x4 + c * sym + s * skew
    }

    /// Rotation by `angle` in a coordinate plane.
    public static func plane(_ plane: RotationPlane, angle: Double) -> simd_double4x4 {
        let (i, j) = plane.axes
        return self.plane(a: axis(i), b: axis(j), angle: angle)
    }

    /// One time step: `Π G(e_i, e_j, ω_ij · Δt)` over the six planes.
    public static func step(_ omega: AngularVelocity4D, dt: Double) -> simd_double4x4 {
        var m = matrix_identity_double4x4
        applyStep(omega, dt: dt, to: &m)
        return m
    }

    /// `m ← step(Ω, Δt) · m`, applying each plane rotation to two rows of m.
    static func applyStep(_ omega: AngularVelocity4D, dt: Double, to m: inout simd_double4x4) {
        for p in RotationPlane.allCases {
            let rate = omega[p]
            guard rate != 0 else { continue }
            let (i, j) = p.axes
            let c = cos(rate * dt), s = sin(rate * dt)
            // (G·m) row i = c·row_i − s·row_j; row j = s·row_i + c·row_j.
            for col in 0..<4 {
                let a = m[col][i], b = m[col][j]
                m[col][i] = c * a - s * b
                m[col][j] = s * a + c * b
            }
        }
    }

    /// Gram–Schmidt on the columns, against rounding drift. Keeps the orientation (det > 0)
    /// for matrices that are close to a rotation.
    public static func orthonormalize(_ m: simd_double4x4) -> simd_double4x4 {
        func unit(_ v: SIMD4<Double>, _ fallback: Int) -> SIMD4<Double> {
            let len = simd_length(v)
            return len > 1e-12 ? v / len : axis(fallback)
        }
        let c0 = unit(m.columns.0, 0)
        var c1 = m.columns.1
        c1 -= simd_dot(c1, c0) * c0
        c1 = unit(c1, 1)
        var c2 = m.columns.2
        c2 -= simd_dot(c2, c0) * c0
        c2 -= simd_dot(c2, c1) * c1
        c2 = unit(c2, 2)
        var c3 = m.columns.3
        c3 -= simd_dot(c3, c0) * c0
        c3 -= simd_dot(c3, c1) * c1
        c3 -= simd_dot(c3, c2) * c2
        c3 = unit(c3, 3)
        return simd_double4x4(columns: (c0, c1, c2, c3))
    }

    /// `R ← orthonormalize(step(Ω, Δt) · R)` (DESIGN 11.1, step 1).
    public static func advance(_ r: simd_double4x4, omega: AngularVelocity4D, dt: Double) -> simd_double4x4 {
        var m = r
        applyStep(omega, dt: dt, to: &m)
        return orthonormalize(m)
    }

    /// `Ω ← Ω · exp(−friction · Δt)`; with friction, rates below `snap` become exactly zero so the
    /// pipeline can stop recomputing. Without friction Ω stays as it is.
    public static func damp(_ omega: AngularVelocity4D, friction: Double, dt: Double,
                            snap: Double = 1e-3) -> AngularVelocity4D {
        guard friction > 0 else { return omega }
        var result = omega.scaled(by: exp(-friction * dt))
        if result.maxMagnitude < snap { result = .zero }
        return result
    }

    /// Single-precision copy of a matrix, for the per-frame pipeline.
    public static func float(_ m: simd_double4x4) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                                SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
    }

    /// Embeds a 3×3 rotation as `diag(M, 1)`, i.e. a rotation that leaves W fixed.
    public static func embed3D(_ m: simd_double3x3) -> simd_double4x4 {
        simd_double4x4(columns: (
            SIMD4(m.columns.0, 0),
            SIMD4(m.columns.1, 0),
            SIMD4(m.columns.2, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }
}
