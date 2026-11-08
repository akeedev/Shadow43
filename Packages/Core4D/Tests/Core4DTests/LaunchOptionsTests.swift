// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

@Suite("Launch arguments and presets")
struct LaunchOptionsTests {
    @Test func parsesTheDesignExample() {
        let config = LaunchConfiguration.parse([
            "object": "tesseract", "projection": "perspective", "display": "glass", "time": "1.5",
        ])
        #expect(config.problems.isEmpty)
        #expect(config.state.object == .tesseract)
        #expect(config.state.projection == ProjectionPreset.perspective.settings)
        #expect(DisplayPreset.glass.matches(config.state.display))
        #expect(config.time == 1.5)
        #expect(config.state.developer.freezesTime)
    }

    @Test func reportsBadValuesAndKeepsDefaults() {
        let config = LaunchConfiguration.parse(["object": "dodecahedron", "kappa": "abc"])
        #expect(config.problems.count == 2)
        #expect(config.state.object == ViewState().object)
        #expect(config.state.projection.kappa == ViewState().projection.kappa)
    }

    @Test func clampsNumericValues() {
        let config = LaunchConfiguration.parse(["kappa": "5", "explode": "-1", "p": "100"])
        #expect(config.state.projection.kappa == 1)
        #expect(config.state.display.explode == 0)
        #expect(config.state.duoprism.p == DuoprismParameters.range.upperBound)
    }

    @Test func parsesOmegaAndMotionNone() {
        let config = LaunchConfiguration.parse(["omega": "1,2,3,4,5,6"])
        #expect(config.state.motion.omega == AngularVelocity4D(xy: 1, xz: 2, yz: 3, xw: 4, yw: 5, zw: 6))
        let none = LaunchConfiguration.parse(["motion": "none"])
        #expect(none.state.motion.omega.isZero)
    }

    @Test func integrationMatchesDirectRotation() {
        var s = ViewState()
        s.motion.omega = AngularVelocity4D(xw: 0.6)
        let integrated = LaunchConfiguration.integrate(s, time: 1.5)
        // Ω acts in world coordinates, so the start tilt is applied first.
        let direct = Rotation4D.plane(.xw, angle: 0.9) * Orientation4D.start.matrix
        #expect(maxAbsDifference(integrated.orientation.matrix, direct) < 1e-9)
    }

    @Test func startOrientationIsAPure3DTilt() {
        let r = Orientation4D.start.matrix
        // W is untouched (cube-inside-a-cube in perspective) and xyz is turned.
        #expect(simd_distance(r * SIMD4<Double>(0, 0, 0, 1), SIMD4<Double>(0, 0, 0, 1)) < 1e-12)
        #expect(abs(r[0, 0] - 1) > 0.05 && abs(r[1, 1] - 1) > 0.05)
        #expect(ViewState().orientation == .start)
    }

    @Test func parsesViewpoint() {
        #expect(LaunchConfiguration.parse(["viewpoint": "back"]).viewSide == .back)
        #expect(LaunchConfiguration.parse([:]).viewSide == nil)
        let bad = LaunchConfiguration.parse(["viewpoint": "above"])
        #expect(bad.viewSide == nil && bad.problems == ["viewpoint=above"])
        #expect(ViewSide.back.direction == SIMD3<Float>(0, 0, -1))
        #expect(ViewSide.allCases.allSatisfy { abs(simd_length($0.direction) - 1) < 1e-6 })
    }

    @Test func viewStateRoundTripsThroughJSON() throws {
        var s = ViewState()
        s.orientation = Orientation4D(matrix: Rotation4D.plane(.yw, angle: 0.3))
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(ViewState.self, from: data)
        #expect(decoded == s)
    }

    @Test func displayPresetsSetTheirLayers() {
        var d = DisplaySettings.defaults
        DisplayPreset.wireframe.apply(to: &d)
        #expect(d.edgesVisible && d.faceOpacity == 0)
        DisplayPreset.cells.apply(to: &d)
        #expect(d.explode == 0.2 && d.faceOpacity == 1 && d.colorSource == .perCell)
        DisplayPreset.solid.apply(to: &d)
        #expect(d.explode == 0 && d.colorSource != .perCell && d.faceOpacity == 1)
        for preset in DisplayPreset.allCases {
            var x = DisplaySettings.defaults
            preset.apply(to: &x)
            #expect(preset.matches(x), "\(preset) should match after applying it")
        }
    }

    @Test func perCellColourForcesMinimumExplode() {
        var d = DisplaySettings.defaults
        d.colorSource = .perCell
        d.explode = 0
        #expect(d.effectiveExplode(for: .polytope) == DisplaySettings.perCellMinimumExplode)
        #expect(d.effectiveExplode(for: .surface) == 0)
        #expect(d.effectiveColorSource(for: .surface) == .uniform)
    }

    @Test func presetsAreRecognised() {
        for p in ProjectionPreset.allCases { #expect(ProjectionPreset.matching(p.settings) == p) }
        for m in MotionPreset.allCases { #expect(MotionPreset.matching(m.omega) == m) }
    }
}
