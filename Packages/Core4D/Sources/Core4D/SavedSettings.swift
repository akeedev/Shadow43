// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation

/// The settings kept between launches (D29): every stage of `ViewState` except the orientation,
/// which starts at `Orientation4D.start` at every launch, plus the drag mapping.
///
/// Each part is decoded on its own and falls back to its default if it is missing or can no
/// longer be read, for example after an update changed its fields; the other parts are kept.
/// Numbers are limited to their current ranges.
public struct SavedSettings: Codable, Equatable, Sendable {
    public var state: ViewState
    public var gestureMapping: GestureMapping

    public init(state: ViewState = ViewState(), gestureMapping: GestureMapping = GestureMapping()) {
        var s = state
        s.orientation = .start
        self.state = s
        self.gestureMapping = gestureMapping
    }

    private enum CodingKeys: String, CodingKey {
        case object, duoprism, projection, display, motion, scale, developer, gestureMapping
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func part<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let d = ViewState()
        let state = ViewState(object: part(.object, d.object), duoprism: part(.duoprism, d.duoprism),
                              projection: part(.projection, d.projection), display: part(.display, d.display),
                              motion: part(.motion, d.motion), scale: part(.scale, d.scale),
                              developer: part(.developer, d.developer))
        self = SavedSettings(state: state, gestureMapping: part(.gestureMapping, GestureMapping())).clamped()
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(state.object, forKey: .object)
        try c.encode(state.duoprism, forKey: .duoprism)
        try c.encode(state.projection, forKey: .projection)
        try c.encode(state.display, forKey: .display)
        try c.encode(state.motion, forKey: .motion)
        try c.encode(state.scale, forKey: .scale)
        try c.encode(state.developer, forKey: .developer)
        try c.encode(gestureMapping, forKey: .gestureMapping)
    }

    /// The settings as JSON.
    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Reads settings written by `encoded()`. Throws only if `data` is not a JSON object at all;
    /// unreadable parts fall back to their defaults.
    public static func decode(_ data: Data) throws -> SavedSettings {
        try JSONDecoder().decode(SavedSettings.self, from: data)
    }

    /// The settings with every number limited to its current range.
    public func clamped() -> SavedSettings {
        var s = self
        let unit: ClosedRange<Double> = 0...1
        s.state.duoprism.p = s.state.duoprism.p.clamped(to: DuoprismParameters.range)
        s.state.duoprism.q = s.state.duoprism.q.clamped(to: DuoprismParameters.range)
        s.state.projection.kappa = s.state.projection.kappa.clamped(to: unit)
        s.state.projection.spherize = s.state.projection.spherize.clamped(to: unit)
        s.state.display.edgeThickness = s.state.display.edgeThickness.clamped(to: DisplaySettings.thicknessRange)
        s.state.display.faceOpacity = s.state.display.faceOpacity.clamped(to: unit)
        s.state.display.explode = s.state.display.explode.clamped(to: DisplaySettings.explodeRange)
        s.state.display.faceThickness = s.state.display.faceThickness.clamped(to: DisplaySettings.faceThicknessRange)
        s.state.motion.friction = s.state.motion.friction.clamped(to: MotionSettings.frictionRange)
        s.state.scale = s.state.scale.clamped(to: ViewState.scaleRange)
        s.gestureMapping.radiansPerMetre = s.gestureMapping.radiansPerMetre.clamped(to: GestureMapping.radiansPerMetreRange)
        s.gestureMapping.sign = s.gestureMapping.sign < 0 ? -1 : 1
        return s
    }
}
