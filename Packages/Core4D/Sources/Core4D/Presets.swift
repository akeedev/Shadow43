// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation

/// The three classic projections as points in the (κ, s) plane (DESIGN 5).
public enum ProjectionPreset: String, CaseIterable, Codable, Sendable {
    case orthographic, perspective, stereographic

    public var settings: ProjectionSettings {
        switch self {
        case .orthographic: ProjectionSettings(kappa: 0, spherize: 0)
        case .perspective: ProjectionSettings(kappa: 0.6, spherize: 0)
        case .stereographic: ProjectionSettings(kappa: 1, spherize: 1)
        }
    }

    /// The preset that matches the settings exactly, if any.
    public static func matching(_ settings: ProjectionSettings) -> ProjectionPreset? {
        allCases.first { $0.settings == settings }
    }
}

/// A glide of κ and s from one projection to another (D42): a projection preset morphs the shadow
/// there instead of making it jump, so you see one projection turn into the other.
public struct ProjectionMorph: Equatable, Sendable {
    public static let duration: TimeInterval = 0.6

    public var from: ProjectionSettings
    public var to: ProjectionSettings
    public var start: TimeInterval

    public init(from: ProjectionSettings, to: ProjectionSettings, start: TimeInterval) {
        self.from = from
        self.to = to
        self.start = start
    }

    /// The projection at time `t`, easing in and out (smoothstep); exactly `to` once finished.
    public func value(at t: TimeInterval) -> (settings: ProjectionSettings, isFinished: Bool) {
        let x = (t - start) / Self.duration
        guard x < 1 else { return (to, true) }
        let e = x <= 0 ? 0 : x * x * (3 - 2 * x)
        let settings = ProjectionSettings(kappa: from.kappa + e * (to.kappa - from.kappa),
                                          spherize: from.spherize + e * (to.spherize - from.spherize))
        return (settings, false)
    }
}

/// Named partial assignments of the display layers (DESIGN 6.2, D48).
public enum DisplayPreset: String, CaseIterable, Codable, Sendable {
    case wireframe, glass, solid, cells

    /// Applies the preset. Every preset sets the edges, their thickness, the face opacity and the
    /// explode; the others leave per-cell colour behind (it would force an explode again), and the
    /// lit ones turn glowing faces matte. Layers a preset does not mention stay unchanged.
    public func apply(to d: inout DisplaySettings) {
        d.edgesVisible = true
        switch self {
        case .wireframe:
            d.edgeThickness = 0.012
            d.faceOpacity = 0
        case .glass:
            d.edgeThickness = 0.012
            d.faceOpacity = 0.25
            d.faceStyle = .glowing
        case .solid:
            d.edgeThickness = 0.005
            d.faceOpacity = 1
            if d.faceStyle == .glowing { d.faceStyle = .matte }
        case .cells:
            d.edgeThickness = 0.005
            d.faceOpacity = 1
            d.colorSource = .perCell
            if d.faceStyle == .glowing { d.faceStyle = .matte }
        }
        d.explode = self == .cells ? 0.2 : 0
        if self != .cells, d.colorSource == .perCell { d.colorSource = .byW }
    }

    /// Whether the settings look like this preset: applying it would change nothing.
    public func matches(_ d: DisplaySettings) -> Bool {
        var applied = d
        apply(to: &applied)
        return applied == d
    }
}

/// Motion presets: each sets Ω only; R is left alone (DESIGN 4).
public enum MotionPreset: String, CaseIterable, Codable, Sendable {
    case simple, double, isoclinic, drift

    public var omega: AngularVelocity4D {
        switch self {
        case .simple: AngularVelocity4D(xw: 0.6)
        case .double: AngularVelocity4D(xy: 0.25, zw: 0.7)
        case .isoclinic: AngularVelocity4D(xy: 0.5, zw: 0.5)
        case .drift: AngularVelocity4D(xy: 0.07, xz: 0.11, yz: 0.05, xw: 0.17, yw: 0.13, zw: 0.19)
        }
    }

    public static func matching(_ omega: AngularVelocity4D) -> MotionPreset? {
        allCases.first { $0.omega == omega }
    }
}
