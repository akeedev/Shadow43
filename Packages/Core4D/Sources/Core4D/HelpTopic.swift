// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation

/// Tabs of the control panel (DESIGN 8.3). The raw value is the `-panel` launch argument.
public enum PanelTab: String, CaseIterable, Identifiable, Sendable {
    case object, projection, display, surface, motion, developer
    public var id: String { rawValue }
}

/// Everything the info window can explain (D22, DESIGN 8.4): the About page, each tab, each object
/// and each control. The texts live in the app.
public enum HelpTopic: Hashable, Sendable, CaseIterable {
    case about
    case tab(PanelTab)
    case object(ObjectID)
    case duoprismParameters
    case projectionPreset(ProjectionPreset)
    case kappa, spherize
    case displayPreset(DisplayPreset)
    case edges, floorShadow, axes, edgeThickness, faceOpacity, colorSource, explode, size, room
    case faceStyle, pattern, faceThickness
    case motionPreset(MotionPreset)
    case stop, reset, friction, planeSpeed
    case transparency, floorShadowMethod, dragMapping, performanceOverlay, gestureTest, freezeTime
    case fineSubdivision, viewerSide
    case resetAll

    /// Every topic, in the order of the panel.
    public static let allCases: [HelpTopic] =
        [.about] + PanelTab.allCases.map(HelpTopic.tab) + ObjectID.allCases.map(HelpTopic.object)
        + [.duoprismParameters]
        + ProjectionPreset.allCases.map(HelpTopic.projectionPreset) + [.kappa, .spherize]
        + DisplayPreset.allCases.map(HelpTopic.displayPreset)
        + [.edges, .floorShadow, .axes, .edgeThickness, .faceOpacity, .colorSource, .explode, .size, .room]
        + [.faceStyle, .pattern, .faceThickness]
        + MotionPreset.allCases.map(HelpTopic.motionPreset) + [.stop, .reset, .friction, .planeSpeed]
        + [.transparency, .floorShadowMethod, .dragMapping, .performanceOverlay, .gestureTest, .freezeTime,
           .fineSubdivision, .viewerSide]
        + [.resetAll]

    /// The `-help` launch argument (D45): `about`, a tab, an object or a preset by its own launch
    /// value, a control by its name here (`kappa`, `faceOpacity`, `resetAll`).
    public var launchValue: String {
        switch self {
        case .about: "about"
        case .tab(let t): t.rawValue
        case .object(let id): id.rawValue
        case .projectionPreset(let p): p.rawValue
        case .displayPreset(let p): p.rawValue
        case .motionPreset(let p): p.rawValue
        case .duoprismParameters: "duoprismParameters"
        case .kappa: "kappa"
        case .spherize: "spherize"
        case .edges: "edges"
        case .floorShadow: "floorShadow"
        case .axes: "axes"
        case .edgeThickness: "edgeThickness"
        case .faceOpacity: "faceOpacity"
        case .colorSource: "colorSource"
        case .explode: "explode"
        case .size: "size"
        case .room: "room"
        case .faceStyle: "faceStyle"
        case .pattern: "pattern"
        case .faceThickness: "faceThickness"
        case .stop: "stop"
        case .reset: "reset"
        case .friction: "friction"
        case .planeSpeed: "planeSpeed"
        case .transparency: "transparency"
        case .floorShadowMethod: "floorShadowMethod"
        case .dragMapping: "dragMapping"
        case .performanceOverlay: "performanceOverlay"
        case .gestureTest: "gestureTest"
        case .freezeTime: "freezeTime"
        case .fineSubdivision: "fineSubdivision"
        case .viewerSide: "viewerSide"
        case .resetAll: "resetAll"
        }
    }

    public init?(launchValue: String) {
        guard let topic = Self.allCases.first(where: { $0.launchValue == launchValue }) else { return nil }
        self = topic
    }

    /// The tab whose control this topic explains. Nil for About and for Reset all, which sit
    /// beside the tabs.
    public var homeTab: PanelTab? {
        switch self {
        case .about, .resetAll: nil
        case .tab(let t): t
        case .object, .duoprismParameters: .object
        case .projectionPreset, .kappa, .spherize: .projection
        case .displayPreset, .edges, .floorShadow, .axes, .edgeThickness, .faceOpacity, .colorSource,
             .explode, .size, .room: .display
        case .faceStyle, .pattern, .faceThickness: .surface
        case .motionPreset, .stop, .reset, .friction, .planeSpeed: .motion
        case .transparency, .floorShadowMethod, .dragMapping, .performanceOverlay, .gestureTest,
             .freezeTime, .fineSubdivision, .viewerSide: .developer
        }
    }

    /// The object an explanation also shows in the volume, the best picture of it (D22): the
    /// explained object, or the duoprism for its p and q, whose steppers only it has.
    public var shownObject: ObjectID? {
        switch self {
        case .object(let id): id
        case .duoprismParameters: .duoprism
        default: nil
        }
    }
}
