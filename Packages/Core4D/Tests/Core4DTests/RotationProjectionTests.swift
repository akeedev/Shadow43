// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

@Suite("Rotation")
struct RotationTests {
    @Test func staysOrthonormalAfterAMillionSteps() {
        let omega = MotionPreset.drift.omega.scaled(by: 10)
        var r = matrix_identity_double4x4
        for _ in 0..<1_000_000 {
            r = Rotation4D.advance(r, omega: omega, dt: 1.0 / 90)
        }
        #expect(maxAbsDifference(r.transpose * r, matrix_identity_double4x4) < 1e-12)
        #expect(abs(r.determinant - 1) < 1e-12)
    }

    @Test(arguments: RotationPlane.allCases)
    func fullTurnIsIdentity(_ plane: RotationPlane) {
        #expect(maxAbsDifference(Rotation4D.plane(plane, angle: 2 * .pi), matrix_identity_double4x4) < 1e-12)
        var r = matrix_identity_double4x4
        var omega = AngularVelocity4D()
        omega[plane] = 2 * .pi
        for _ in 0..<1000 { r = Rotation4D.advance(r, omega: omega, dt: 0.001) }
        #expect(maxAbsDifference(r, matrix_identity_double4x4) < 1e-9)
    }

    @Test func xyAndZWCommute() {
        let a = Rotation4D.plane(.xy, angle: 0.7)
        let b = Rotation4D.plane(.zw, angle: -1.3)
        #expect(maxAbsDifference(a * b, b * a) < 1e-14)
    }

    @Test func positiveAngleTurnsFirstAxisTowardsSecond() {
        let g = Rotation4D.plane(.xw, angle: .pi / 2)
        #expect(maxAbs(g * Rotation4D.axis(0) - Rotation4D.axis(3)) < 1e-12)
        #expect(maxAbs(g * Rotation4D.axis(3) + Rotation4D.axis(0)) < 1e-12)
        #expect(maxAbs(g * Rotation4D.axis(1) - Rotation4D.axis(1)) < 1e-12)
    }

    @Test func generalPlaneMatchesCoordinatePlane() {
        let a = Rotation4D.plane(a: Rotation4D.axis(1), b: Rotation4D.axis(2), angle: 0.4)
        #expect(maxAbsDifference(a, Rotation4D.plane(.yz, angle: 0.4)) < 1e-14)
    }

    @Test func stepIsTheProductOfPlaneRotations() {
        let omega = AngularVelocity4D(xy: 0.3, xw: -0.2, zw: 0.5)
        let dt = 0.1
        var expected = matrix_identity_double4x4
        for p in RotationPlane.allCases where omega[p] != 0 {
            expected = Rotation4D.plane(p, angle: omega[p] * dt) * expected
        }
        #expect(maxAbsDifference(Rotation4D.step(omega, dt: dt), expected) < 1e-14)
    }

    @Test func frictionDampsAndSnapsToZero() {
        let omega = AngularVelocity4D(xw: 1)
        let damped = Rotation4D.damp(omega, friction: 1, dt: 1)
        #expect(abs(damped.xw - exp(-1)) < 1e-12)
        #expect(Rotation4D.damp(omega, friction: 0, dt: 1) == omega)
        #expect(Rotation4D.damp(AngularVelocity4D(xw: 1e-4), friction: 1, dt: 0.01).isZero)
    }

    @Test func orthonormalizeRepairsDrift() {
        var m = Rotation4D.plane(.yw, angle: 0.3)
        m[0][1] += 1e-3
        let o = Rotation4D.orthonormalize(m)
        #expect(maxAbsDifference(o.transpose * o, matrix_identity_double4x4) < 1e-12)
        #expect(o.determinant > 0)
    }

    @Test func embed3DLeavesWFixed() {
        let q = simd_quatd(angle: 0.8, axis: simd_normalize(SIMD3<Double>(1, 2, 3)))
        let m = Rotation4D.embed3D(simd_double3x3(q))
        #expect(maxAbs(m * Rotation4D.axis(3) - Rotation4D.axis(3)) < 1e-12)
        #expect(abs(m.determinant - 1) < 1e-12)
    }
}

@Suite("Projection")
struct ProjectionTests {
    @Test func kappaZeroIsOrthographic() {
        let p = SIMD4<Double>(0.3, -0.2, 0.7, 0.9)
        let q = Projection4D.project(p, kappa: 0)!
        #expect(simd_distance(q, SIMD3(0.3, -0.2, 0.7)) < 1e-15)
    }

    @Test func pointsWithWZeroStayInPlace() {
        let p = SIMD4<Double>(0.3, -0.2, 0.7, 0)
        for kappa in stride(from: 0.0, through: 1.0, by: 0.25) {
            #expect(simd_distance(Projection4D.project(p, kappa: kappa)!, SIMD3(0.3, -0.2, 0.7)) < 1e-15)
        }
    }

    @Test func pointsAtOrBehindTheEyeAreDropped() {
        #expect(Projection4D.project([0, 0, 0, 1], kappa: 1) == nil)
        #expect(Projection4D.project([0, 0, 0, 0.99], kappa: 1) == nil)
        #expect(Projection4D.project([0, 0, 0, 0.9], kappa: 1) != nil)
    }

    @Test func stereographicPolesAndEquator() {
        #expect(simd_length(Projection4D.project([0, 0, 0, -1], kappa: 1)!) < 1e-15)
        for k in 0..<20 {
            let t = Double(k) * 0.3
            let p = SIMD4<Double>(cos(t) * cos(2 * t), sin(t) * cos(2 * t), sin(2 * t), 0)
            #expect(abs(simd_length(Projection4D.project(p, kappa: 1)!) - 1) < 1e-12)
        }
    }

    @Test(arguments: 0..<8)
    func stereographicMapsGreatCirclesToCirclesOrLines(_ seed: Int) {
        var rng = SeededGenerator(seed: UInt64(seed + 1))
        let a = simd_normalize(randomVector(&rng))
        var b = randomVector(&rng)
        b = simd_normalize(b - simd_dot(b, a) * a)
        let points = (0..<24).compactMap { k -> SIMD3<Double>? in
            let t = 2 * Double.pi * Double(k) / 24 + 0.01
            return Projection4D.project(cos(t) * a + sin(t) * b, kappa: 1, epsilon: 1e-6)
        }
        #expect(points.count >= 20)
        #expect(isCircleOrLine(points))
    }

    @Test func spherizeBlendsTowardsTheSphere() {
        let v = SIMD4<Double>(0.5, 0, 0, 0)
        #expect(Projection4D.spherize(v, s: 0) == v)
        #expect(abs(simd_length(Projection4D.spherize(v, s: 1)) - 1) < 1e-15)
        #expect(abs(Projection4D.spherize(v, s: 0.5).x - 0.75) < 1e-15)
    }

    func randomVector(_ rng: inout SeededGenerator) -> SIMD4<Double> {
        SIMD4((0..<4).map { _ in Double.random(in: -1...1, using: &rng) })
    }

    /// Whether 3D points lie on one circle or one straight line.
    func isCircleOrLine(_ p: [SIMD3<Double>]) -> Bool {
        let a = p[0], b = p[p.count / 3], c = p[2 * p.count / 3]
        let n = simd_cross(b - a, c - a)
        if simd_length(n) < 1e-9 {
            return p.allSatisfy { simd_length(simd_cross($0 - a, b - a)) < 1e-6 * max(1, simd_length(b - a)) }
        }
        let normal = simd_normalize(n)
        // Circumcentre of a, b, c.
        let ab = b - a, ac = c - a
        let centre = a + (simd_length_squared(ac) * simd_cross(n, ab) + simd_length_squared(ab) * simd_cross(ac, n))
            / (2 * simd_length_squared(n))
        let radius = simd_distance(centre, a)
        return p.allSatisfy { q in
            abs(simd_dot(q - a, normal)) < 1e-6 * max(1, radius)
                && abs(simd_distance(q, centre) - radius) < 1e-6 * max(1, radius)
        }
    }
}

/// A small deterministic random number generator (SplitMix64) for reproducible tests.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
