// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation

/// Snapshot mode (DESIGN 12.5): launch arguments such as
/// `-object tesseract -projection perspective -display glass -time 1.5` set `ViewState`, and
/// `-time` freezes time at a fixed t.
///
/// Recognised keys (all optional):
/// - `object` (ObjectID raw value), `p`, `q` (duoprism)
/// - `projection` (preset), `kappa`, `spherize`
/// - `display` (preset), `edges` (0/1), `thickness`, `edgeColor` (faces/light), `opacity`,
///   `colors` (ColorSource raw value), `style` (matte/glossy/glowing/metal/ceramic/frosted),
///   `explode`, `floorShadow` (0/1), `axes` (0/1), `pattern` (none/grid/marble/wood),
///   `faceThickness` (0…0.08)
/// - `motion` (preset or `none`), `omega` ("xy,xz,yz,xw,yw,zw"), `friction`
/// - `scale`, `time` (seconds; freezes time after integrating the motion for that long)
/// - `transparency` (additive/sorted/cells), `overlay` (0/1), `gestureTest` (0/1), `fine` (0/1),
///   `shadowMethod` (light/grounding)
/// - `panel` (control-panel tab), `room` (0/1: open the immersive space at launch),
///   `help` (`about`, a tab or an object: opens the help window in "?" mode)
/// - `viewpoint` (front/right/back/left: fixes the viewer side and ignores the system's updates)
public struct LaunchConfiguration: Equatable, Sendable {
    public var state: ViewState
    /// If set, the orientation is integrated for this many seconds and time is frozen.
    public var time: Double?
    /// Control-panel tab to show at launch.
    public var panel: String?
    /// Help window to open at launch, in "?" mode: `about`, a tab or an object (read by the app).
    public var help: String?
    /// Whether to open the immersive space at launch.
    public var opensRoom: Bool
    /// Fixed viewer side (snapshot mode); nil = follow the system.
    public var viewSide: ViewSide?
    /// Keys whose values could not be understood; reported in the log.
    public var problems: [String]

    public init(state: ViewState = ViewState(), time: Double? = nil, panel: String? = nil,
                opensRoom: Bool = false, viewSide: ViewSide? = nil, problems: [String] = []) {
        self.state = state
        self.time = time
        self.panel = panel
        self.opensRoom = opensRoom
        self.viewSide = viewSide
        self.problems = problems
    }

    /// Every key `parse` reads.
    public static let recognizedKeys: Set<String> = [
        "object", "p", "q", "projection", "kappa", "spherize", "display", "edges", "thickness",
        "edgeColor", "opacity", "colors", "style", "explode", "floorShadow", "axes", "pattern",
        "faceThickness", "motion", "omega", "friction", "scale", "transparency", "overlay",
        "gestureTest", "fine", "shadowMethod", "time", "panel", "help", "room", "viewpoint",
    ]

    /// Snapshot mode: at least one recognised key is given. The app then starts from the default
    /// settings instead of the saved ones and saves nothing (D29), so snapshots are reproducible.
    public static func isSnapshot(_ args: [String: String]) -> Bool {
        args.keys.contains(where: recognizedKeys.contains)
    }

    /// Parses launch arguments given as a key → string dictionary (the `UserDefaults` argument
    /// domain). Unknown values are recorded in `problems` and otherwise ignored.
    public static func parse(_ args: [String: String], base: ViewState = ViewState()) -> LaunchConfiguration {
        var config = LaunchConfiguration(state: base)
        var s = config.state

        func value<T>(_ key: String, _ convert: (String) -> T?) -> T? {
            guard let raw = args[key] else { return nil }
            if let v = convert(raw) { return v }
            config.problems.append("\(key)=\(raw)")
            return nil
        }
        let double: (String) -> Double? = { Double($0) }
        let bool: (String) -> Bool? = { raw in
            switch raw.lowercased() {
            case "1", "yes", "true", "on": true
            case "0", "no", "false", "off": false
            default: nil
            }
        }

        if let o = value("object", ObjectID.init(rawValue:)) { s.object = o }
        if let p = value("p", { Int($0) }) { s.duoprism.p = p.clamped(to: DuoprismParameters.range) }
        if let q = value("q", { Int($0) }) { s.duoprism.q = q.clamped(to: DuoprismParameters.range) }

        if let preset = value("projection", ProjectionPreset.init(rawValue:)) { s.projection = preset.settings }
        if let k = value("kappa", double) { s.projection.kappa = k.clamped(to: 0...1) }
        if let sp = value("spherize", double) { s.projection.spherize = sp.clamped(to: 0...1) }

        if let preset = value("display", DisplayPreset.init(rawValue:)) { preset.apply(to: &s.display) }
        if let e = value("edges", bool) { s.display.edgesVisible = e }
        if let t = value("thickness", double) { s.display.edgeThickness = t.clamped(to: DisplaySettings.thicknessRange) }
        if let c = value("edgeColor", EdgeColorMode.init(rawValue:)) { s.display.edgeColor = c }
        if let o = value("opacity", double) { s.display.faceOpacity = o.clamped(to: 0...1) }
        if let c = value("colors", ColorSource.init(rawValue:)) { s.display.colorSource = c }
        if let st = value("style", FaceStyle.init(rawValue:)) { s.display.faceStyle = st }
        if let e = value("explode", double) { s.display.explode = e.clamped(to: DisplaySettings.explodeRange) }
        if let f = value("floorShadow", bool) { s.display.floorShadow = f }
        if let a = value("axes", bool) { s.display.axesVisible = a }
        if let pt = value("pattern", SurfacePattern.init(rawValue:)) { s.display.pattern = pt }
        if let ft = value("faceThickness", double) {
            s.display.faceThickness = ft.clamped(to: DisplaySettings.faceThicknessRange)
        }

        if let m = args["motion"] {
            if m == "none" { s.motion.omega = .zero }
            else if let preset = MotionPreset(rawValue: m) { s.motion.omega = preset.omega }
            else { config.problems.append("motion=\(m)") }
        }
        if let o = value("omega", parseOmega) { s.motion.omega = o }
        if let f = value("friction", double) { s.motion.friction = f.clamped(to: MotionSettings.frictionRange) }

        if let sc = value("scale", double) { s.scale = sc.clamped(to: ViewState.scaleRange) }
        if let tr = value("transparency", TransparencyMethod.init(rawValue:)) { s.developer.transparency = tr }
        if let ov = value("overlay", bool) { s.developer.showsPerformanceOverlay = ov }
        if let g = value("gestureTest", bool) { s.developer.showsGestureTest = g }
        if let f = value("fine", bool) { s.developer.forcesFineSubdivision = f }
        if let m = value("shadowMethod", FloorShadowMethod.init(rawValue:)) { s.developer.floorShadowMethod = m }

        if let t = value("time", double) {
            config.time = max(0, t)
            s.developer.freezesTime = true
        }
        config.panel = args["panel"]
        config.help = args["help"]
        if let r = value("room", bool) { config.opensRoom = r }
        if let v = value("viewpoint", ViewSide.init(rawValue:)) { config.viewSide = v }

        config.state = s
        return config
    }

    static func parseOmega(_ raw: String) -> AngularVelocity4D? {
        let parts = raw.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 6, parts.allSatisfy({ $0 != nil }) else { return nil }
        let v = parts.map { $0! }
        return AngularVelocity4D(xy: v[0], xz: v[1], yz: v[2], xw: v[3], yw: v[4], zw: v[5])
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
