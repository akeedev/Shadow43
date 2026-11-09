// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// The volume's size (D19): a 1 m box by default, which the user can resize down to 0.5 m.
public enum VolumeSize {
    public static let defaultSize = SIMD3<Double>(1, 1, 1)
    public static let minimumSide = 0.5
}

/// Automatic object size (D15): every object is scaled so that the radius holding 90 % of its
/// projected vertices fills a fixed fraction of the host box. The radius is measured over a fixed
/// set of orientations rather than the current one, so the size does not pump while the object
/// rotates and the 4D "breathing" stays visible. It depends only on the object, κ and s.
public enum SizeFit {
    /// The fitted object's diameter as a fraction of the smallest side of the host box.
    public static let fillFraction = 0.75
    /// Share of the projected vertices that lies inside the fitted radius.
    public static let defaultPercentile = 0.9
    /// At most this many vertices are measured per orientation; larger objects are subsampled.
    public static let maxPoints = 512

    /// 32 pseudo-random orientations (products of all six plane rotations), deterministic so that
    /// snapshots are reproducible.
    public static let sampleOrientations: [simd_double4x4] = {
        var state: UInt64 = 0x5348_4144_4F57_3433
        func nextAngle() -> Double {
            // SplitMix64, mapped to [−π, π).
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return (Double(z >> 11) / Double(1 << 53) * 2 - 1) * .pi
        }
        return (0..<32).map { _ in
            var r = matrix_identity_double4x4
            for plane in RotationPlane.allCases {
                r = Rotation4D.plane(plane, angle: nextAngle()) * r
            }
            return r
        }
    }()

    /// The `percentile` distance from the origin of the projected `points`, pooled over all
    /// `orientations`. Points culled near the eye count as infinitely far. Returns 1 for empty
    /// input, and the largest finite distance if the percentile itself is culled.
    public static func radius(of points: [SIMD4<Double>], projection: ProjectionSettings,
                              percentile: Double = defaultPercentile,
                              orientations: [simd_double4x4] = sampleOrientations) -> Double {
        guard !points.isEmpty, !orientations.isEmpty else { return 1 }
        let step = max(1, (points.count + maxPoints - 1) / maxPoints)
        let sampled = Swift.stride(from: 0, to: points.count, by: step).map {
            Projection4D.spherize(points[$0], s: projection.spherize)
        }
        var distances: [Double] = []
        distances.reserveCapacity(orientations.count * sampled.count)
        for r in orientations {
            for v in sampled {
                if let q = Projection4D.project(r * v, kappa: projection.kappa) {
                    distances.append(simd_length(q))
                } else {
                    distances.append(.infinity)
                }
            }
        }
        distances.sort()
        let p = min(max(percentile, 0), 1)
        let k = min(distances.count - 1, max(0, Int((p * Double(distances.count)).rounded(.up)) - 1))
        var r = distances[k]
        if !r.isFinite { r = distances.last(where: { $0.isFinite }) ?? 1 }
        return r > 1e-9 ? r : 1
    }

    /// The fitted radius of a complex, measured on its vertices.
    public static func radius(of complex: Complex4D, projection: ProjectionSettings) -> Double {
        radius(of: complex.vertices, projection: projection)
    }

    /// Metres per object unit so that the fitted radius fills `fillFraction` of a box whose
    /// smallest side is `boxSide` metres, times the user's size factor.
    public static func metresPerUnit(fittedRadius: Double, boxSide: Double, sizeFactor: Double) -> Double {
        0.5 * fillFraction * boxSide / max(fittedRadius, 1e-9) * sizeFactor
    }

    /// A length given relative to the fitted radius (edge and face thickness), in object units
    /// for the current `metresPerUnit`, such that it keeps its size in metres when the object is
    /// zoomed or the window resized (D28). It equals `relative × fittedRadius` at size factor 1
    /// in a box of `referenceSide` metres.
    public static func fixedLength(_ relative: Double, referenceSide: Double, metresPerUnit: Double) -> Double {
        relative * 0.5 * fillFraction * referenceSide / max(metresPerUnit, 1e-12)
    }

    /// How far (metres) the object's centre rises when the size factor is above 1, so that its
    /// fitted bottom stays where it is at factor 1, above the floor disc (D21). Smaller objects
    /// stay centred.
    public static func lift(boxSide: Double, sizeFactor: Double) -> Double {
        0.5 * fillFraction * boxSide * max(0, sizeFactor - 1)
    }
}
