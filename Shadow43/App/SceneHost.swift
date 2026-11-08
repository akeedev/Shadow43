// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Supplies the viewer's position in content coordinates, if the host knows it.
/// The volumetric window does not; the immersive space can later use ARKit world tracking.
@MainActor
protocol ViewerPoseProvider: AnyObject {
    func viewerPosition() -> SIMD3<Float>?
}

/// Everything that differs between the volumetric window and the immersive space (DESIGN 3.5).
/// Scene content depends only on this value, never on the hosting scene itself.
@MainActor
struct SceneHost {
    /// Size of the available box in metres.
    var bounds: SIMD3<Float>
    /// Metres per object unit (the object has circumradius 1).
    var defaultScale: Float
    /// Nil in the window.
    var viewerPose: ViewerPoseProvider?
    /// Content offset from the scene origin, in metres.
    var contentOffset: SIMD3<Float>

    /// The volumetric window: a 0.8 m box.
    static let window = SceneHost(bounds: [0.8, 0.8, 0.8], defaultScale: 0.2, viewerPose: nil,
                                  contentOffset: .zero)
    /// The immersive space: room scale, about 2 m across, in front of the user at eye height.
    static let room = SceneHost(bounds: [3, 2.5, 3], defaultScale: 0.6, viewerPose: nil,
                                contentOffset: [0, 1.5, -2.8])

    /// Height of the floor disc below the content centre, in metres.
    var floorY: Float { -bounds.y * 0.45 }
}
