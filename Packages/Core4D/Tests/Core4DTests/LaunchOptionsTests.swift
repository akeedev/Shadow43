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

    @Test func clampsEveryNumber() {
        // One range per field (D41), the same as the sliders'.
        let high = LaunchConfiguration.parse([
            "p": "100", "q": "100", "kappa": "5", "spherize": "5", "thickness": "1", "opacity": "2",
            "explode": "1", "faceThickness": "1", "omega": "9,-9,0,5,-5,1", "friction": "7",
            "scale": "10", "dragGain": "100",
        ])
        #expect(high.problems.isEmpty)
        let s = high.state
        #expect(s.duoprism.p == DuoprismParameters.range.upperBound && s.duoprism.q == DuoprismParameters.range.upperBound)
        #expect(s.projection.kappa == 1 && s.projection.spherize == 1)
        #expect(s.display.edgeThickness == DisplaySettings.thicknessRange.upperBound)
        #expect(s.display.faceOpacity == 1)
        #expect(s.display.explode == DisplaySettings.explodeRange.upperBound)
        #expect(s.display.faceThickness == DisplaySettings.faceThicknessRange.upperBound)
        #expect(s.motion.omega == AngularVelocity4D(xy: 4, xz: -4, yz: 0, xw: 4, yw: -4, zw: 1))
        #expect(s.motion.friction == MotionSettings.frictionRange.upperBound)
        #expect(s.scale == ViewState.scaleRange.upperBound)
        #expect(high.gestureMapping.radiansPerMetre == GestureMapping.radiansPerMetreRange.upperBound)
        let low = LaunchConfiguration.parse(["q": "-3", "thickness": "0", "friction": "-1", "scale": "0", "time": "-2"])
        #expect(low.state.duoprism.q == DuoprismParameters.range.lowerBound)
        #expect(low.state.display.edgeThickness == DisplaySettings.thicknessRange.lowerBound)
        #expect(low.state.motion.friction == 0 && low.state.scale == ViewState.scaleRange.lowerBound)
        #expect(low.time == 0)
        #expect(ViewState().clamped() == ViewState())
    }

    @Test func rejectsNumbersThatAreNotFinite() {
        // NaN would pass every clamp unchanged.
        let config = LaunchConfiguration.parse(["kappa": "nan", "scale": "inf", "omega": "0,0,0,nan,0,0"])
        #expect(config.problems.sorted() == ["kappa=nan", "omega=0,0,0,nan,0,0", "scale=inf"])
        #expect(config.state == ViewState())
    }

    @Test func parsesTheDragMappingAndTheVolumeSize() {
        let config = LaunchConfiguration.parse(["dragGain": "6", "invertDrag": "1", "volumeSize": "1.2, 0.3,2"])
        #expect(config.gestureMapping == GestureMapping(radiansPerMetre: 6, sign: -1))
        // Sides below the volume's minimum are raised to it.
        #expect(config.volumeSize == SIMD3(1.2, VolumeSize.minimumSide, 2))
        #expect(LaunchConfiguration.parse([:]).volumeSize == nil)
        #expect(LaunchConfiguration.parse(["volumeSize": "1,1"]).problems == ["volumeSize=1,1"])
        #expect(LaunchConfiguration.parse(["volumeSize": "1,0,1"]).problems == ["volumeSize=1,0,1"])
        // Without arguments, the base mapping (the saved one) is kept.
        let saved = GestureMapping(radiansPerMetre: 4, sign: -1)
        #expect(LaunchConfiguration.parse([:], gestureMapping: saved).gestureMapping == saved)
    }

    @Test func parsesOmegaAndMotionNone() {
        let config = LaunchConfiguration.parse(["omega": "1,2,3,-4,0.5,-0.25"])
        #expect(config.state.motion.omega == AngularVelocity4D(xy: 1, xz: 2, yz: 3, xw: -4, yw: 0.5, zw: -0.25))
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

    @Test func helpActsLikeATap() {
        // D45: the topic's object and tab are selected, as a tap in "?" mode would.
        #expect(LaunchConfiguration.parse([:]).help == nil)
        let object = LaunchConfiguration.parse(["help": "tesseract", "object": "klein-bottle", "panel": "motion"])
        #expect(object.help == .object(.tesseract) && object.state.object == .tesseract)
        #expect(object.panel == .object && object.helpMode)
        let control = LaunchConfiguration.parse(["help": "kappa"])
        #expect(control.help == .kappa && control.panel == .projection && control.problems.isEmpty)
        let pq = LaunchConfiguration.parse(["help": "duoprismParameters"])
        #expect(pq.state.object == .duoprism && pq.panel == .object)
        // About leaves the tab alone and "?" mode off, unless asked for.
        let about = LaunchConfiguration.parse(["help": "about", "panel": "display"])
        #expect(about.help == .about && about.panel == .display && !about.helpMode)
        #expect(LaunchConfiguration.parse(["help": "about", "helpMode": "1"]).helpMode)
        #expect(!LaunchConfiguration.parse(["help": "kappa", "helpMode": "0"]).helpMode)
        // "?" mode alone shows the tab's overview, as the ? button does.
        let mode = LaunchConfiguration.parse(["helpMode": "yes", "panel": "motion"])
        #expect(mode.help == .tab(.motion) && mode.helpMode)
        #expect(LaunchConfiguration.parse(["helpMode": "1"]).help == .tab(.object))
        #expect(LaunchConfiguration.parse(["helpMode": "0"]).help == nil)
        // Unknown values are reported like any other.
        let bad = LaunchConfiguration.parse(["help": "everything", "panel": "settings"])
        #expect(bad.help == nil && bad.panel == nil)
        #expect(bad.problems.sorted() == ["help=everything", "panel=settings"])
    }

    @Test func everyHelpTopicHasItsOwnLaunchValue() {
        let topics = HelpTopic.allCases
        #expect(topics.count == 56)
        #expect(Set(topics).count == topics.count)
        #expect(Set(topics.map(\.launchValue)).count == topics.count)
        for topic in topics { #expect(HelpTopic(launchValue: topic.launchValue) == topic) }
        // Only About and Reset all sit beside the tabs; every tab explains itself.
        #expect(topics.filter { $0.homeTab == nil } == [.about, .resetAll])
        for tab in PanelTab.allCases { #expect(HelpTopic.tab(tab).homeTab == tab) }
        #expect(HelpTopic.faceThickness.homeTab == .surface && HelpTopic.freezeTime.homeTab == .developer)
        #expect(topics.compactMap(\.shownObject).count == ObjectID.allCases.count + 1)
    }

    @Test func parsesAxes() {
        #expect(LaunchConfiguration.parse([:]).state.display.axesVisible == false)
        #expect(LaunchConfiguration.parse(["axes": "1"]).state.display.axesVisible)
        let bad = LaunchConfiguration.parse(["axes": "maybe"])
        #expect(bad.state.display.axesVisible == false && bad.problems == ["axes=maybe"])
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
        #expect(d.edgesVisible && d.faceOpacity == 0 && d.edgeThickness == 0.012)
        DisplayPreset.cells.apply(to: &d)
        #expect(d.explode == 0.2 && d.faceOpacity == 1 && d.colorSource == .perCell)
        DisplayPreset.solid.apply(to: &d)
        #expect(d.explode == 0 && d.colorSource == .byW && d.faceOpacity == 1 && d.faceStyle == .matte)
        #expect(DisplayPreset.glass.matches(DisplaySettings.defaults))
    }

    @Test func everyDisplayPresetSetsTheExplode() {
        // D48 (replaces D13): leaving Cells undoes its explode and per-cell colour, also after the
        // explode slider moved; the others keep a colour source of the user's.
        var d = DisplaySettings.defaults
        DisplayPreset.cells.apply(to: &d)
        d.explode = 0.3
        DisplayPreset.glass.apply(to: &d)
        #expect(d.explode == 0 && d.colorSource == .byW)
        d.colorSource = .uniform
        d.explode = 0.1
        DisplayPreset.solid.apply(to: &d)
        #expect(d.explode == 0 && d.colorSource == .uniform)
        // A lit style chosen on the Surface tab stays; only glowing turns matte.
        d.faceStyle = .metal
        DisplayPreset.cells.apply(to: &d)
        #expect(d.faceStyle == .metal)
    }

    @Test func aPresetIsHighlightedWhenApplyingItChangesNothing() {
        for preset in DisplayPreset.allCases {
            var x = DisplaySettings.defaults
            x.faceStyle = .ceramic
            preset.apply(to: &x)
            #expect(preset.matches(x), "\(preset) should match after applying it")
            for other in DisplayPreset.allCases where other != preset {
                #expect(!other.matches(x), "\(other) should not match \(preset)")
            }
        }
        var d = DisplaySettings.defaults
        d.explode = 0.1
        #expect(!DisplayPreset.glass.matches(d))
        d = DisplaySettings.defaults
        d.edgeThickness = 0.02
        #expect(!DisplayPreset.glass.matches(d))
        d = DisplaySettings.defaults
        d.pattern = .wood
        d.floorShadow = false
        #expect(DisplayPreset.glass.matches(d))
    }

    @Test func projectionMorphEasesToTheTarget() {
        let from = ProjectionPreset.orthographic.settings, to = ProjectionPreset.stereographic.settings
        let morph = ProjectionMorph(from: from, to: to, start: 10)
        for t in [9.0, 10] {
            let v = morph.value(at: t)
            #expect(v.settings == from && !v.isFinished)
        }
        let half = morph.value(at: 10 + ProjectionMorph.duration / 2)
        #expect(abs(half.settings.kappa - 0.5) < 1e-12 && abs(half.settings.spherize - 0.5) < 1e-12)
        for t in [10 + ProjectionMorph.duration + 1e-9, 99] {
            let v = morph.value(at: t)
            #expect(v.settings == to && v.isFinished)
        }
        // Smooth: it starts and ends slowly and never overshoots.
        var last = -1.0
        for k in 0...60 {
            let kappa = morph.value(at: 10 + Double(k) / 100).settings.kappa
            #expect(kappa >= last && kappa <= 1)
            last = kappa
        }
        #expect(morph.value(at: 10.01).settings.kappa < 0.01)
    }

    @Test func perCellColourForcesMinimumExplode() {
        var d = DisplaySettings.defaults
        d.colorSource = .perCell
        d.explode = 0
        #expect(d.effectiveExplode(for: .polytope) == DisplaySettings.perCellMinimumExplode)
        #expect(d.effectiveExplode(for: .surface) == 0)
        #expect(d.effectiveColorSource(for: .surface) == .uniform)
    }

    @Test func perCellEntitiesOnlyForFewExplodedCells() {
        // D31: the 120- and 600-cell fall back to sorted; every duoprism (≤ 48 cells) keeps it.
        let cells = TransparencyMethod.perCellEntities
        #expect(cells.effective(cellCount: 24, explode: 0.2) == .perCellEntities)
        #expect(cells.effective(cellCount: 48, explode: 0.2, hasPattern: true) == .perCellEntities)
        #expect(cells.effective(cellCount: 120, explode: 0.2) == .sorted)
        #expect(cells.effective(cellCount: 600, explode: 0.2) == .sorted)
        #expect(cells.effective(cellCount: 8, explode: 0) == .sorted)
        let duoprismMax = DuoprismParameters.range.upperBound * 2
        #expect(duoprismMax <= TransparencyMethod.maxCellsForPerCellEntities)
        #expect(TransparencyMethod.sorted.effective(cellCount: 600, explode: 0, additiveReady: false) == .sorted)
    }

    @Test func additiveFallsBackToSortedForPatternsAndUntilReady() {
        // D47: one rule for every fallback.
        let additive = TransparencyMethod.additive
        #expect(additive.effective(cellCount: 600, explode: 0.2) == .additive)
        #expect(additive.effective(cellCount: 8, explode: 0, hasPattern: true) == .sorted)
        #expect(additive.effective(cellCount: 8, explode: 0, additiveReady: false) == .sorted)
        #expect(TransparencyMethod.perCellEntities.effective(cellCount: 8, explode: 0.2, additiveReady: false)
            == .perCellEntities)
    }

    @Test func presetsAreRecognised() {
        for p in ProjectionPreset.allCases { #expect(ProjectionPreset.matching(p.settings) == p) }
        for m in MotionPreset.allCases { #expect(MotionPreset.matching(m.omega) == m) }
    }
}
