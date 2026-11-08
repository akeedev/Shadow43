// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation

/// The three classic projections as points in the (κ, s) plane (DESIGN 3.3).
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

/// Named partial assignments of the display layers (DESIGN 3.4).
public enum DisplayPreset: String, CaseIterable, Codable, Sendable {
    case wireframe, glass, solid, cells

    /// Applies the preset. Layers that the preset does not mention stay unchanged, except that
    /// leaving *Cells* also leaves its per-cell colour and explode behind.
    public func apply(to d: inout DisplaySettings) {
        let wasCells = DisplayPreset.cells.matches(d)
        switch self {
        case .wireframe:
            d.edgesVisible = true
            d.edgeThickness = 0.012
            d.faceOpacity = 0
        case .glass:
            d.edgesVisible = true
            d.edgeThickness = 0.012
            d.faceOpacity = 0.25
            d.faceStyle = .glowing
        case .solid:
            d.edgesVisible = true
            d.edgeThickness = 0.005
            d.faceOpacity = 1
            if d.faceStyle == .glowing { d.faceStyle = .matte }
        case .cells:
            d.edgesVisible = true
            d.edgeThickness = 0.005
            d.explode = 0.2
            d.faceOpacity = 1
            d.colorSource = .perCell
            if d.faceStyle == .glowing { d.faceStyle = .matte }
        }
        if wasCells && self != .cells {
            d.explode = 0
            d.colorSource = .byW
        }
    }

    /// Whether the settings currently look like this preset.
    public func matches(_ d: DisplaySettings) -> Bool {
        switch self {
        case .wireframe: d.edgesVisible && d.faceOpacity == 0
        case .glass: d.edgesVisible && d.faceOpacity == 0.25 && d.faceStyle == .glowing && d.explode == 0
        case .solid: d.faceOpacity == 1 && d.explode == 0 && d.edgeThickness == 0.005
        case .cells: d.faceOpacity == 1 && d.explode == 0.2 && d.colorSource == .perCell
        }
    }
}

/// Motion presets: each sets Ω only; R is left alone (DESIGN 3.2).
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
