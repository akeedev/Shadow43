// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Snapshot mode (DESIGN 12.5): launch arguments such as
/// `-object tesseract -projection perspective -display glass -time 1.5` set every visual state
/// (D45), and `-time` freezes time at a fixed t.
///
/// Recognised keys (all optional):
/// - `object` (ObjectID raw value), `p`, `q` (duoprism)
/// - `projection` (preset), `kappa`, `spherize`
/// - `display` (preset), `edges` (bool), `thickness`, `edgeColor` (faces/light), `opacity`,
///   `colors` (ColorSource raw value), `style` (matte/glossy/glowing/metal/ceramic/frosted),
///   `explode`, `floorShadow` (bool), `axes` (bool), `pattern` (none/grid/marble/wood),
///   `faceThickness`
/// - `motion` (preset or `none`), `omega` ("xy,xz,yz,xw,yw,zw"), `friction`
/// - `scale`, `time` (seconds; freezes time after integrating the motion for that long)
/// - `transparency` (additive/sorted/cells), `shadowMethod` (light/grounding), `overlay`,
///   `gestureTest`, `fine` (bool), `dragGain` (k in rad/m), `invertDrag` (bool)
/// - `panel` (a tab); `help` (a `HelpTopic.launchValue`): opens Info and, like a tap, selects
///   the topic's object and tab, overriding `object` and `panel`; `helpMode` (bool): "?" mode,
///   by default on with any topic but About; without `help` it shows the tab's overview
/// - `room` (bool: open the immersive space), `viewpoint` (front/right/back/left: fixes the viewer
///   side), `volumeSize` ("w,h,d" in metres: the volume's default size)
///
/// Numbers are limited to their ranges (`ViewState.clamped()`, D41).
public struct LaunchConfiguration: Equatable, Sendable {
    public var state: ViewState
    /// k and sign of the one-hand drag (Developer tab).
    public var gestureMapping: GestureMapping
    /// If set, the orientation is integrated for this many seconds and time is frozen.
    public var time: Double?
    /// Control-panel tab to show at launch.
    public var panel: PanelTab?
    /// Topic to show in the info window at launch.
    public var help: HelpTopic?
    /// Whether "?" mode is on at launch.
    public var helpMode = false
    /// Whether to open the immersive space at launch.
    public var opensRoom = false
    /// Fixed viewer side (snapshot mode); nil = follow the system.
    public var viewSide: ViewSide?
    /// Default size of the volume in metres; visionOS uses it only for a new window.
    public var volumeSize: SIMD3<Double>?
    /// `key=value` of every argument that could not be understood; logged and listed in the
    /// Developer tab.
    public var problems: [String] = []

    public init(state: ViewState = ViewState(), gestureMapping: GestureMapping = GestureMapping()) {
        self.state = state
        self.gestureMapping = gestureMapping
    }

    /// Every key `parse` reads.
    public static let recognizedKeys: Set<String> = [
        "object", "p", "q", "projection", "kappa", "spherize", "display", "edges", "thickness",
        "edgeColor", "opacity", "colors", "style", "explode", "floorShadow", "axes", "pattern",
        "faceThickness", "motion", "omega", "friction", "scale", "transparency", "overlay",
        "gestureTest", "fine", "shadowMethod", "dragGain", "invertDrag", "time", "panel", "help",
        "helpMode", "room", "viewpoint", "volumeSize",
    ]

    /// Snapshot mode: at least one recognised key is given. The app then starts from the default
    /// settings instead of the saved ones and saves nothing (D29), so snapshots are reproducible.
    public static func isSnapshot(_ args: [String: String]) -> Bool {
        args.keys.contains(where: recognizedKeys.contains)
    }

    /// Parses launch arguments given as a key → string dictionary (the `UserDefaults` argument
    /// domain), on top of `base` and `gestureMapping`. Values that cannot be understood are
    /// recorded in `problems` and otherwise ignored.
    public static func parse(_ args: [String: String], base: ViewState = ViewState(),
                             gestureMapping: GestureMapping = GestureMapping()) -> LaunchConfiguration {
        var config = LaunchConfiguration(state: base, gestureMapping: gestureMapping)
        var s = config.state
        var mapping = config.gestureMapping

        func value<T>(_ key: String, _ convert: (String) -> T?) -> T? {
            guard let raw = args[key] else { return nil }
            if let v = convert(raw) { return v }
            config.problems.append("\(key)=\(raw)")
            return nil
        }
        let double: (String) -> Double? = finiteDouble
        let bool: (String) -> Bool? = { raw in
            switch raw.lowercased() {
            case "1", "yes", "true", "on": true
            case "0", "no", "false", "off": false
            default: nil
            }
        }

        if let o = value("object", ObjectID.init(rawValue:)) { s.object = o }
        if let p = value("p", { Int($0) }) { s.duoprism.p = p }
        if let q = value("q", { Int($0) }) { s.duoprism.q = q }

        if let preset = value("projection", ProjectionPreset.init(rawValue:)) { s.projection = preset.settings }
        if let k = value("kappa", double) { s.projection.kappa = k }
        if let sp = value("spherize", double) { s.projection.spherize = sp }

        if let preset = value("display", DisplayPreset.init(rawValue:)) { preset.apply(to: &s.display) }
        if let e = value("edges", bool) { s.display.edgesVisible = e }
        if let t = value("thickness", double) { s.display.edgeThickness = t }
        if let c = value("edgeColor", EdgeColorMode.init(rawValue:)) { s.display.edgeColor = c }
        if let o = value("opacity", double) { s.display.faceOpacity = o }
        if let c = value("colors", ColorSource.init(rawValue:)) { s.display.colorSource = c }
        if let st = value("style", FaceStyle.init(rawValue:)) { s.display.faceStyle = st }
        if let e = value("explode", double) { s.display.explode = e }
        if let f = value("floorShadow", bool) { s.display.floorShadow = f }
        if let a = value("axes", bool) { s.display.axesVisible = a }
        if let pt = value("pattern", SurfacePattern.init(rawValue:)) { s.display.pattern = pt }
        if let ft = value("faceThickness", double) { s.display.faceThickness = ft }

        let motion = { (raw: String) -> AngularVelocity4D? in
            raw == "none" ? .zero : MotionPreset(rawValue: raw)?.omega
        }
        if let m = value("motion", motion) { s.motion.omega = m }
        if let o = value("omega", parseOmega) { s.motion.omega = o }
        if let f = value("friction", double) { s.motion.friction = f }

        if let sc = value("scale", double) { s.scale = sc }
        if let tr = value("transparency", TransparencyMethod.init(rawValue:)) { s.developer.transparency = tr }
        if let ov = value("overlay", bool) { s.developer.showsPerformanceOverlay = ov }
        if let g = value("gestureTest", bool) { s.developer.showsGestureTest = g }
        if let f = value("fine", bool) { s.developer.forcesFineSubdivision = f }
        if let m = value("shadowMethod", FloorShadowMethod.init(rawValue:)) { s.developer.floorShadowMethod = m }
        if let k = value("dragGain", double) { mapping.radiansPerMetre = k }
        if let i = value("invertDrag", bool) { mapping.sign = i ? -1 : 1 }

        if let t = value("time", double) {
            config.time = max(0, t)
            s.developer.freezesTime = true
        }
        if let r = value("room", bool) { config.opensRoom = r }
        if let v = value("viewpoint", ViewSide.init(rawValue:)) { config.viewSide = v }
        if let size = value("volumeSize", parseVolumeSize) { config.volumeSize = size }

        // Help acts like a tap on the topic's control (D45), so it comes after `object` and `panel`.
        config.panel = value("panel", PanelTab.init(rawValue:))
        let helpMode = value("helpMode", bool)
        if let topic = value("help", HelpTopic.init(launchValue:)) {
            config.help = topic
            if let o = topic.shownObject { s.object = o }
            if let tab = topic.homeTab { config.panel = tab }
            config.helpMode = helpMode ?? (topic != .about)
        } else if helpMode == true {
            config.help = .tab(config.panel ?? .object)
            config.helpMode = true
        }

        config.state = s.clamped()
        config.gestureMapping = mapping.clamped()
        return config
    }

    /// A finite number; "nan" and "inf" would pass every clamp unchanged.
    static func finiteDouble(_ raw: String) -> Double? {
        guard let v = Double(raw.trimmingCharacters(in: .whitespaces)), v.isFinite else { return nil }
        return v
    }

    static func parseOmega(_ raw: String) -> AngularVelocity4D? {
        let parts = raw.split(separator: ",").map { finiteDouble(String($0)) }
        guard parts.count == 6, parts.allSatisfy({ $0 != nil }) else { return nil }
        let v = parts.map { $0! }
        return AngularVelocity4D(xy: v[0], xz: v[1], yz: v[2], xw: v[3], yw: v[4], zw: v[5])
    }

    /// "w,h,d" in metres, each positive; sides below the volume's minimum are raised to it.
    static func parseVolumeSize(_ raw: String) -> SIMD3<Double>? {
        let parts = raw.split(separator: ",").map { finiteDouble(String($0)) }
        guard parts.count == 3, parts.allSatisfy({ ($0 ?? 0) > 0 }) else { return nil }
        let v = SIMD3(parts[0]!, parts[1]!, parts[2]!)
        return simd_max(v, SIMD3(repeating: VolumeSize.minimumSide))
    }

    /// Integrates the orientation for `time` seconds from the current R with the current Ω, in
    /// steps of 1/90 s (the frame rate), as the running app would.
    public static func integrate(_ state: ViewState, time: Double) -> ViewState {
        var s = state
        let dt = 1.0 / 90
        var t = 0.0
        var r = s.orientation.matrix
        var omega = s.motion.omega
        while t < time - 1e-9 {
            let h = min(dt, time - t)
            r = Rotation4D.advance(r, omega: omega, dt: h)
            omega = Rotation4D.damp(omega, friction: s.motion.friction, dt: h)
            t += h
        }
        s.orientation = Orientation4D(matrix: r)
        s.motion.omega = omega
        return s
    }
}

extension Comparable {
    /// The value limited to a closed range.
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
