// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

@Suite("Automatic size")
struct SizeFitTests {
    let identity = [matrix_identity_double4x4]
    let orthographic = ProjectionSettings(kappa: 0, spherize: 0)

    @Test func orthographicRadiusOfAUnitPolytopeIsAtMostOne() {
        let r = SizeFit.radius(of: Fixtures.tesseract, projection: orthographic)
        #expect(r > 0.8 && r <= 1 + 1e-9)
    }

    @Test func theNinetiethPercentileIgnoresFarOutliers() {
        let points = Array(repeating: SIMD4<Double>(1, 0, 0, 0), count: 95)
            + Array(repeating: SIMD4<Double>(100, 0, 0, 0), count: 5)
        let r90 = SizeFit.radius(of: points, projection: orthographic, orientations: identity)
        #expect(abs(r90 - 1) < 1e-12)
        let r100 = SizeFit.radius(of: points, projection: orthographic, percentile: 1, orientations: identity)
        #expect(abs(r100 - 100) < 1e-9)
    }

    @Test func culledPointsCountAsFarAway() {
        // 20 % of the points sit at the eye (w = 1, κ = 1) and are culled: the 90th percentile is
        // then culled too, so the largest finite distance is used.
        let points = Array(repeating: SIMD4<Double>(0, 0, 0, 1), count: 20)
            + Array(repeating: SIMD4<Double>(0.5, 0, 0, 0), count: 80)
        let stereo = ProjectionSettings(kappa: 1, spherize: 0)
        #expect(abs(SizeFit.radius(of: points, projection: stereo, orientations: identity) - 0.5) < 1e-12)
        #expect(abs(SizeFit.radius(of: points, projection: stereo, percentile: 0.5, orientations: identity) - 0.5) < 1e-12)
    }

    @Test func stereographicFitIsFiniteAndLargerThanOrthographic() {
        let ortho = SizeFit.radius(of: Fixtures.twentyFourCell, projection: orthographic)
        let stereo = SizeFit.radius(of: Fixtures.twentyFourCell, projection: ProjectionSettings(kappa: 1, spherize: 1))
        #expect(stereo.isFinite)
        #expect(stereo > 1.3 * ortho)
    }

    @Test func largeObjectsAreSubsampled() {
        let r = SizeFit.radius(of: Fixtures.oneTwentyCell, projection: ProjectionSettings(kappa: 0.6, spherize: 0))
        #expect(r.isFinite && r > 0.5 && r < 3)
    }

    @Test func sampleOrientationsAreDistinctRotations() {
        let samples = SizeFit.sampleOrientations
        #expect(samples.count == 32)
        for r in samples {
            #expect(maxAbsDifference(r.transpose * r, matrix_identity_double4x4) < 1e-12)
            #expect(abs(simd_determinant(r) - 1) < 1e-12)
        }
        #expect(maxAbsDifference(samples[0], samples[1]) > 0.1)
    }

    @Test func metresPerUnitFillsSeventyFivePercentTimesTheSizeFactor() {
        let m = SizeFit.metresPerUnit(fittedRadius: 2, boxSide: 0.8, sizeFactor: 1)
        #expect(abs(2 * 2 * m - 0.6) < 1e-12)
        #expect(abs(SizeFit.metresPerUnit(fittedRadius: 2, boxSide: 0.8, sizeFactor: 1.5) - 1.5 * m) < 1e-12)
    }

    @Test func emptyInputGivesOne() {
        #expect(SizeFit.radius(of: [SIMD4<Double>](), projection: orthographic) == 1)
    }
}
