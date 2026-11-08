// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// The object's four coordinate axes as they appear in the shadow (D20): the 4D segment from −eᵢ
/// to +eᵢ of each axis, rotated with the object and projected like its points.
///
/// The perspective map `xyz / (1 − κw)` sends lines to lines, so every projected axis lies on the
/// 3D line through the origin in direction `(R eᵢ).xyz`, and only its two ends need projecting.
/// The ends are unit vectors, which spherize leaves unchanged, so they meet the object in every
/// projection. An axis that points along w, the direction that is projected away, collapses to a
/// point at the centre.
public enum AxisCross {
    /// One projected axis, in object units.
    public struct Axis: Equatable, Sendable {
        /// 0, 1, 2, 3 for x, y, z, w.
        public var index: Int
        /// Image of −eᵢ.
        public var negativeEnd: SIMD3<Double>
        /// Image of +eᵢ; the label goes here.
        public var positiveEnd: SIMD3<Double>

        public init(index: Int, negativeEnd: SIMD3<Double>, positiveEnd: SIMD3<Double>) {
            self.index = index
            self.negativeEnd = negativeEnd
            self.positiveEnd = positiveEnd
        }
    }

    /// The four projected axes. An end that would lie at or behind the eye (`1 − κw < ε`) is moved
    /// back along the axis to `1 − κw = ε`; ends are also clamped to `maxRadius`.
    public static func axes(rotation: simd_double4x4, kappa: Double,
                            epsilon: Double = Projection4D.defaultEpsilon,
                            maxRadius: Double) -> [Axis] {
        (0..<4).map { i in
            let r = rotation[i]  // R eᵢ is the i-th column.
            return Axis(index: i,
                        negativeEnd: end(-r, kappa: kappa, epsilon: epsilon, maxRadius: maxRadius),
                        positiveEnd: end(r, kappa: kappa, epsilon: epsilon, maxRadius: maxRadius))
        }
    }

    /// Projected end of the segment from the origin to `v` (a unit vector after rotation).
    private static func end(_ v: SIMD4<Double>, kappa: Double, epsilon: Double,
                            maxRadius: Double) -> SIMD3<Double> {
        let direction = SIMD3(v.x, v.y, v.z)
        // Along the segment s·v (s in 0…1) the divisor is 1 − κ s w; stop where it reaches ε.
        let kw = kappa * v.w
        var s = 1.0
        if 1 - kw < epsilon, kw > 0 { s = (1 - epsilon) / kw }
        let p = s * direction / (1 - s * kw)
        let length = simd_length(p)
        return length > maxRadius ? p * (maxRadius / length) : p
    }
}
