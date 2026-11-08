// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

@Suite("Gesture mapping")
struct GestureTests {
    @Test(arguments: [0.05, 0.1, -0.2])
    func dragAlongXRotatesInTheXWPlaneByKL(_ length: Double) {
        let mapping = GestureMapping()
        let r = mapping.rotation(forDrag: [length, 0, 0])
        let expected = Rotation4D.plane(.xw, angle: mapping.radiansPerMetre * length)
        #expect(maxAbsDifference(r, expected) < 1e-12)
    }

    @Test func dragDirectionsMapToTheirPlanes() {
        let m = GestureMapping(radiansPerMetre: 3)
        #expect(maxAbsDifference(m.rotation(forDrag: [0, 0.1, 0]), Rotation4D.plane(.yw, angle: 0.3)) < 1e-12)
        #expect(maxAbsDifference(m.rotation(forDrag: [0, 0, 0.1]), Rotation4D.plane(.zw, angle: 0.3)) < 1e-12)
        #expect(maxAbsDifference(m.rotation(forDrag: .zero), matrix_identity_double4x4) < 1e-15)
    }

    @Test func signFlipsTheDirection() {
        let plus = GestureMapping(sign: 1).rotation(forDrag: [0.1, 0, 0])
        let minus = GestureMapping(sign: -1).rotation(forDrag: [0.1, 0, 0])
        #expect(maxAbsDifference(plus * minus, matrix_identity_double4x4) < 1e-12)
    }

    @Test func diagonalDragIsARotation() {
        let r = GestureMapping().rotation(forDrag: [0.03, -0.04, 0.02])
        #expect(maxAbsDifference(r.transpose * r, matrix_identity_double4x4) < 1e-12)
        #expect(abs(r.determinant - 1) < 1e-12)
        // The plane is spanned by the drag direction and W: a vector orthogonal to both is fixed.
        let fixed = simd_normalize(SIMD4<Double>(0.04, 0.03, 0, 0))
        #expect(maxAbs(r * fixed - fixed) < 1e-12)
    }

    @Test func throwSetsTheWPlanesFromTheVelocity() {
        let m = GestureMapping(radiansPerMetre: 2)
        let omega = m.angularVelocity(forDragVelocity: [0.5, -0.25, 0.1])
        #expect(omega == AngularVelocity4D(xw: 1, yw: -0.5, zw: 0.2))
    }

    @Test func throwMatchesTheDragOverOneStep() {
        // A drag at velocity v for a short dt rotates like the thrown Ω does over dt.
        let m = GestureMapping()
        let v = SIMD3<Double>(0.2, 0.1, -0.05)
        let dt = 1e-4
        let drag = m.rotation(forDrag: v * dt)
        let thrown = Rotation4D.step(m.angularVelocity(forDragVelocity: v), dt: dt)
        #expect(maxAbsDifference(drag, thrown) < 1e-6)
    }

    @Test func velocityTrackerUsesTheLastTenthOfASecond() {
        var t = VelocityTracker()
        // Slow first, then 1 m/s along x for the last 0.2 s.
        t.add(time: 0, position: [0, 0, 0])
        t.add(time: 0.5, position: [0.01, 0, 0])
        for k in 1...20 { t.add(time: 0.5 + Double(k) * 0.01, position: [0.01 + Double(k) * 0.01, 0, 0]) }
        #expect(abs(t.velocity.x - 1) < 1e-9)
        t.reset()
        #expect(t.velocity == .zero)
    }

    @Test func twoHandTwistLeavesWFixed() {
        let q = simd_quatd(angle: 0.5, axis: [0, 1, 0])
        let r = GestureMapping.rotation(for: q)
        #expect(maxAbs(r * Rotation4D.axis(3) - Rotation4D.axis(3)) < 1e-12)
        #expect(maxAbsDifference(r, Rotation4D.plane(.xz, angle: -0.5)) < 1e-12)
    }

    @Test func throwsAreClamped() {
        let omega = clampedThrow(AngularVelocity4D(xw: 10, yw: 5), maxRate: 4)
        #expect(abs(omega.xw - 4) < 1e-12 && abs(omega.yw - 2) < 1e-12)
        #expect(clampedThrow(AngularVelocity4D(xw: 1)) == AngularVelocity4D(xw: 1))
    }
}
