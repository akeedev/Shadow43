// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// The Spherize and Project stages (DESIGN 5, 10.3).
public enum Projection4D {
    /// Points with `1 − κw` below this are at or behind the eye and are dropped.
    public static let defaultEpsilon = 0.02

    /// `p = xyz / (1 − κw)`, or nil when `1 − κw < ε`.
    /// κ = 0 is orthographic; κ = 1 on S³ is the stereographic projection from (0, 0, 0, 1).
    public static func project(_ p: SIMD4<Double>, kappa: Double,
                               epsilon: Double = defaultEpsilon) -> SIMD3<Double>? {
        let d = 1 - kappa * p.w
        guard d >= epsilon else { return nil }
        return SIMD3(p.x, p.y, p.z) / d
    }

    /// Blend between the flat point and its image on S³: `lerp(v, v/|v|, s)`.
    public static func spherize(_ v: SIMD4<Double>, s: Double) -> SIMD4<Double> {
        let len = simd_length(v)
        guard len > 0 else { return v }
        return v + s * (v / len - v)
    }

    /// The whole per-point pipeline: `R · lerp(flat, sphere, s)`, then project.
    public static func pipeline(_ v: SIMD4<Double>, rotation: simd_double4x4, kappa: Double,
                                spherize s: Double) -> SIMD3<Double>? {
        project(rotation * spherize(v, s: s), kappa: kappa)
    }
}
