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
        s.orientation = Orientation4D(matrix: Rotation4D.plane(.xw, angle: 0.7))
        return SavedSettings(state: s, gestureMapping: GestureMapping(radiansPerMetre: 7, sign: -1))
    }

    @Test func roundTripKeepsEverythingButTheOrientation() throws {
        let saved = changed()
        #expect(saved.state.orientation == .start)
        let decoded = try SavedSettings.decode(saved.encoded())
        #expect(decoded == saved)
        #expect(decoded.state.object == .twentyFourCell && decoded.gestureMapping.radiansPerMetre == 7)
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
        s.gestureMapping.radiansPerMetre = 500
        s.gestureMapping.sign = -0.2
        let decoded = try SavedSettings.decode(s.encoded())
        #expect(decoded.state.scale == ViewState.scaleRange.upperBound)
        #expect(decoded.state.duoprism.p == DuoprismParameters.range.lowerBound)
        #expect(decoded.state.display.faceOpacity == 0)
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
        // A value no key accepts is either reported as a problem or, for the free-text keys
        // panel and help, passed through.
        for key in LaunchConfiguration.recognizedKeys {
            let config = LaunchConfiguration.parse([key: "§"])
            let passedThrough = (key == "panel" && config.panel == "§") || (key == "help" && config.help == "§")
            #expect(config.problems == ["\(key)=§"] || passedThrough, "key \(key)")
        }
    }
}
