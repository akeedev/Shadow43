// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import Testing
@testable import Core4D

/// Settings kept between launches (D29).
@Suite("Saved settings")
struct SavedSettingsTests {
    private func changed() -> SavedSettings {
        var s = ViewState(object: .twentyFourCell, duoprism: DuoprismParameters(p: 5, q: 7),
                          projection: ProjectionPreset.stereographic.settings, scale: 1.7)
        s.display.pattern = .marble
        s.display.faceStyle = .metal
        s.motion.friction = 0.4
        s.developer.transparency = .sorted
        s.developer.floorShadowMethod = .grounding
        s.orientation = Orientation4D(matrix: Rotation4D.plane(.xw, angle: 0.7))
        return SavedSettings(state: s, gestureMapping: GestureMapping(radiansPerMetre: 7, sign: -1))
    }

    @Test func roundTripKeepsEverythingButTheOrientation() throws {
        let saved = changed()
        #expect(saved.state.orientation == .start)
        let decoded = try SavedSettings.decode(saved.encoded())
        #expect(decoded == saved)
        #expect(decoded.state.object == .twentyFourCell && decoded.gestureMapping.radiansPerMetre == 7)
        #expect(decoded.state.developer.transparency == .sorted)
        #expect(decoded.state.developer.floorShadowMethod == .grounding)
    }

    @Test func diagnosticsAreNotSaved() throws {
        // D43: a session that ended with time frozen or an overlay on starts without them.
        var s = ViewState()
        s.developer = DeveloperSettings(transparency: .perCellEntities, showsPerformanceOverlay: true,
                                        showsGestureTest: true, freezesTime: true, forcesFineSubdivision: true)
        s.developer.floorShadowMethod = .grounding
        let decoded = try SavedSettings.decode(SavedSettings(state: s).encoded())
        var expected = DeveloperSettings(transparency: .perCellEntities)
        expected.floorShadowMethod = .grounding
        #expect(decoded.state.developer == expected)
        // Also when an older record still contains them.
        var json = try #require(try JSONSerialization.jsonObject(with: SavedSettings().encoded()) as? [String: Any])
        json["developer"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s.developer))
        let old = try SavedSettings.decode(JSONSerialization.data(withJSONObject: json))
        #expect(old.state.developer == expected)
    }

    @Test func anUnreadablePartFallsBackAlone() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: changed().encoded()) as? [String: Any])
        json["display"] = "not a display"
        json.removeValue(forKey: "motion")
        let decoded = try SavedSettings.decode(JSONSerialization.data(withJSONObject: json))
        #expect(decoded.state.display == DisplaySettings.defaults)
        #expect(decoded.state.motion == ViewState().motion)
        #expect(decoded.state.object == .twentyFourCell)
        #expect(decoded.state.developer.transparency == .sorted)
    }

    @Test func emptyRecordGivesDefaultsAndNonObjectsThrow() throws {
        #expect(try SavedSettings.decode(Data("{}".utf8)) == SavedSettings())
        #expect(throws: (any Error).self) { try SavedSettings.decode(Data("[1, 2]".utf8)) }
        #expect(throws: (any Error).self) { try SavedSettings.decode(Data("garbage".utf8)) }
    }

    @Test func numbersAreLimitedToTheirRanges() throws {
        var s = changed()
        s.state.scale = 100
        s.state.duoprism.p = 1
        s.state.display.faceOpacity = -3
        s.state.motion.omega = AngularVelocity4D(xw: 30, zw: -8)
        s.gestureMapping.radiansPerMetre = 500
        s.gestureMapping.sign = -0.2
        let decoded = try SavedSettings.decode(s.encoded())
        #expect(decoded.state.scale == ViewState.scaleRange.upperBound)
        #expect(decoded.state.duoprism.p == DuoprismParameters.range.lowerBound)
        #expect(decoded.state.display.faceOpacity == 0)
        #expect(decoded.state.motion.omega == AngularVelocity4D(xw: 4, zw: -4))
        #expect(decoded.gestureMapping.radiansPerMetre == GestureMapping.radiansPerMetreRange.upperBound)
        #expect(decoded.gestureMapping.sign == -1)
        #expect(SavedSettings().clamped() == SavedSettings())
    }

    @Test func snapshotModeNeedsARecognisedKey() {
        #expect(LaunchConfiguration.isSnapshot(["object": "tesseract"]))
        #expect(LaunchConfiguration.isSnapshot(["time": "0", "NSDocumentRevisionsDebugMode": "YES"]))
        #expect(!LaunchConfiguration.isSnapshot([:]))
        #expect(!LaunchConfiguration.isSnapshot(["NSDocumentRevisionsDebugMode": "YES"]))
    }

    @Test func everyRecognisedKeyIsParsed() {
        // A value no key accepts is reported as a problem, for every key.
        for key in LaunchConfiguration.recognizedKeys {
            let config = LaunchConfiguration.parse([key: "§"])
            #expect(config.problems == ["\(key)=§"], "key \(key)")
        }
    }
}
