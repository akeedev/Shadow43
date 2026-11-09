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

    @Test func defaultGainIsTenInTheMiddleOfItsRange() {
        // D26: 10 rad per metre, a full turn per 2π/10 ≈ 0.63 m of drag.
        let mapping = GestureMapping()
        #expect(mapping.radiansPerMetre == 10)
        let range = GestureMapping.radiansPerMetreRange
        #expect(abs((range.lowerBound + range.upperBound) / 2 - mapping.radiansPerMetre) < 1e-12)
        let r = mapping.rotation(forDrag: [2 * .pi / 10, 0, 0])
        #expect(maxAbsDifference(r, matrix_identity_double4x4) < 1e-12)
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

    @Test func throwsAreScaledIntoTheSpeedRange() {
        // D41: throws and sliders share one range; scaling keeps the throw's direction.
        #expect(MotionSettings.speedRange == -4...4)
        let omega = clampedThrow(AngularVelocity4D(xw: 10, yw: 5))
        #expect(abs(omega.xw - 4) < 1e-12 && abs(omega.yw - 2) < 1e-12)
        #expect(clampedThrow(AngularVelocity4D(xw: 1)) == AngularVelocity4D(xw: 1))
    }

    @Test func twistIsAppliedInIncrements() {
        let a = simd_quatd(angle: 0.2, axis: [0, 1, 0]), b = simd_quatd(angle: 0.5, axis: [0, 1, 0])
        let step = GestureMapping.twistIncrement(from: a, to: b)
        #expect(maxAbsDifference(step, GestureMapping.rotation(for: simd_quatd(angle: 0.3, axis: [0, 1, 0]))) < 1e-12)
        let none = GestureMapping.twistIncrement(from: b, to: b)
        #expect(maxAbsDifference(none, matrix_identity_double4x4) < 1e-12)
    }

    @Test func magnifyStaysInTheSizeRange() {
        #expect(GestureMapping.magnifiedScale(start: 1.5, magnification: 2) == 3)
        #expect(GestureMapping.magnifiedScale(start: 3, magnification: 2) == ViewState.scaleRange.upperBound)
        #expect(GestureMapping.magnifiedScale(start: 0.5, magnification: 0.1) == ViewState.scaleRange.lowerBound)
    }

    @Test func aQuickTapDoesNotCatch() {
        // D49: a double tap keeps the speeds; it neither catches nor throws.
        var grab = GrabSession(time: 0, position: [0, 0, 0])
        _ = grab.move(to: [0.002, 0, 0], at: 0.05, twoHandGesture: false)
        let early = grab.catchesNow(at: 0.1)
        _ = grab.move(to: [0.004, 0.001, 0], at: 0.12, twoHandGesture: false)
        let late = grab.catchesNow(at: 0.12)
        #expect(!early && !late)
        #expect(grab.throwVelocity(mapping: GestureMapping(), twoHandGesture: false) == nil)
    }

    @Test func holdingOrMovingCatchesOnce() {
        var held = GrabSession(time: 1, position: [0, 0, 0])
        let before = held.catchesNow(at: 1.2)
        let atDelay = held.catchesNow(at: 1 + GrabSession.catchDelay)
        let again = held.catchesNow(at: 2)
        #expect(!before && atDelay && !again && held.hasCaught)
        var moved = GrabSession(time: 1, position: [0, 0, 0])
        _ = moved.move(to: [0, 0, -GrabSession.catchDistance], at: 1.05, twoHandGesture: false)
        let caught = moved.catchesNow(at: 1.05)
        #expect(caught)
    }

    @Test func aGrabTurnsByItsStepsAndThrowsOnRelease() throws {
        var grab = GrabSession(time: 0, position: [0, 0, 0])
        var total = SIMD3<Double>.zero
        for k in 1...20 {
            total += grab.move(to: [0.01 * Double(k), 0, 0], at: 0.01 * Double(k), twoHandGesture: false)
            _ = grab.catchesNow(at: 0.01 * Double(k))
        }
        #expect(simd_distance(total, [0.2, 0, 0]) < 1e-12 && grab.hasCaught)
        // 1 m/s along x with k = 2 gives 2 rad/s in XW.
        let omega = try #require(grab.throwVelocity(mapping: GestureMapping(radiansPerMetre: 2), twoHandGesture: false))
        #expect(abs(omega.xw - 2) < 1e-9 && omega.yw == 0 && omega.xy == 0)
        // No throw while a two-hand gesture runs, and its steps are not applied.
        #expect(grab.throwVelocity(mapping: GestureMapping(), twoHandGesture: true) == nil)
        let ignored = grab.move(to: [0.3, 0, 0], at: 0.3, twoHandGesture: true)
        #expect(ignored == .zero)
    }

    @Test func aSlowReleaseDoesNotThrow() {
        var grab = GrabSession(time: 0, position: [0, 0, 0])
        _ = grab.move(to: [0.02, 0, 0], at: 0.1, twoHandGesture: false)
        let caught = grab.catchesNow(at: 0.1)
        #expect(caught)
        // Then the hand rests: the velocity over the last 0.1 s falls below the minimum.
        for k in 1...10 { _ = grab.move(to: [0.02, 0, 0], at: 0.1 + 0.02 * Double(k), twoHandGesture: false) }
        #expect(grab.throwVelocity(mapping: GestureMapping(), twoHandGesture: false) == nil)
    }
}
