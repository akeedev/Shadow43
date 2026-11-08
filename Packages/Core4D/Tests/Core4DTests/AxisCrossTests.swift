// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

@Suite("Axis cross")
struct AxisCrossTests {
    let far = 1000.0

    @Test func identityShowsXYZAndHidesW() {
        let axes = AxisCross.axes(rotation: matrix_identity_double4x4, kappa: 0, maxRadius: far)
        #expect(axes.map(\.index) == [0, 1, 2, 3])
        #expect(axes[0].positiveEnd == SIMD3(1, 0, 0) && axes[0].negativeEnd == SIMD3(-1, 0, 0))
        #expect(axes[1].positiveEnd == SIMD3(0, 1, 0))
        #expect(axes[2].negativeEnd == SIMD3(0, 0, -1))
        // w is the direction that is projected away.
        #expect(axes[3].positiveEnd == .zero && axes[3].negativeEnd == .zero)
    }

    @Test func aQuarterTurnInXWSwapsTheRolesOfXAndW() {
        let r = Rotation4D.plane(.xw, angle: .pi / 2)
        let axes = AxisCross.axes(rotation: r, kappa: 0.5, maxRadius: far)
        // x now points along w and collapses; w lies along −x (x turns towards w, w towards −x).
        #expect(simd_length(axes[0].positiveEnd) < 1e-12 && simd_length(axes[0].negativeEnd) < 1e-12)
        #expect(simd_distance(axes[3].positiveEnd, SIMD3(-1, 0, 0)) < 1e-12)
        #expect(simd_distance(axes[3].negativeEnd, SIMD3(1, 0, 0)) < 1e-12)
    }

    @Test(arguments: [(0.0, 0.0), (0.5, 0.0), (0.5, 0.5), (1.0, 1.0), (0.3, 0.8)])
    func axisEndsMeetTheObjectsPoints(kappa: Double, spherize: Double) {
        let r = Rotation4D.plane(.yz, angle: 0.4) * Rotation4D.plane(.xw, angle: 0.7)
            * Rotation4D.plane(.zw, angle: -0.3)
        let axes = AxisCross.axes(rotation: r, kappa: kappa, maxRadius: far)
        for axis in axes {
            let e = Rotation4D.axis(axis.index)
            let plus = Projection4D.pipeline(e, rotation: r, kappa: kappa, spherize: spherize)
            let minus = Projection4D.pipeline(-e, rotation: r, kappa: kappa, spherize: spherize)
            #expect(simd_distance(axis.positiveEnd, plus!) < 1e-9)
            #expect(simd_distance(axis.negativeEnd, minus!) < 1e-9)
        }
    }

    @Test func projectedAxesRunThroughTheCentre() {
        let r = Rotation4D.plane(.xw, angle: 0.9) * Rotation4D.plane(.xy, angle: 0.2)
        for axis in AxisCross.axes(rotation: r, kappa: 0.8, maxRadius: far) {
            // Both ends lie on one line through the origin, on opposite sides.
            let cross = simd_cross(axis.positiveEnd, axis.negativeEnd)
            #expect(simd_length(cross) < 1e-9)
            #expect(simd_dot(axis.positiveEnd, axis.negativeEnd) <= 1e-12)
        }
    }

    @Test func anEndAtTheEyeIsPulledBackAndClamped() {
        // x tipped 85° towards w: in the stereographic view (κ = 1) its tip is almost at the eye.
        let r = Rotation4D.plane(.xw, angle: 85 * .pi / 180)
        let free = AxisCross.axes(rotation: r, kappa: 1, maxRadius: far)[0].positiveEnd
        // Pulled back to 1 − κw = ε: x = s·cos 85° / ε with s = (1 − ε) / sin 85°, about 4.29.
        let s = (1 - Projection4D.defaultEpsilon) / sin(85 * .pi / 180)
        #expect(abs(free.x - s * cos(85 * .pi / 180) / Projection4D.defaultEpsilon) < 1e-9)
        #expect(free.y == 0 && free.z == 0)
        let clamped = AxisCross.axes(rotation: r, kappa: 1, maxRadius: 3)[0].positiveEnd
        #expect(abs(simd_length(clamped) - 3) < 1e-9 && clamped.x > 0)

        // Exactly at the eye (x turned fully into w, κ = 1): the end stays finite.
        let atEye = AxisCross.axes(rotation: Rotation4D.plane(.xw, angle: .pi / 2), kappa: 1, maxRadius: far)
        #expect(atEye.allSatisfy { $0.positiveEnd.x.isFinite && $0.negativeEnd.x.isFinite })
    }
}
