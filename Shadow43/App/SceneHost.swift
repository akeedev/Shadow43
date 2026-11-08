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
    /// Size of the available box in metres. The object is sized automatically to fill
    /// `SizeFit.fillFraction` of its smallest side (D15).
    var bounds: SIMD3<Float>
    /// Nil in the window.
    var viewerPose: ViewerPoseProvider?
    /// Content offset from the scene origin, in metres.
    var contentOffset: SIMD3<Float>
    /// Whether the host reports which side of the volume the viewer is on (window only, D17).
    var tracksVolumeViewpoint: Bool

    /// The volumetric window: a 0.8 m box.
    static let window = SceneHost(bounds: [0.8, 0.8, 0.8], viewerPose: nil, contentOffset: .zero,
                                  tracksVolumeViewpoint: true)
    /// The immersive space: room scale, about 2 m across, in front of the user at eye height.
    static let room = SceneHost(bounds: [3, 2.5, 3], viewerPose: nil, contentOffset: [0, 1.5, -2.8],
                                tracksVolumeViewpoint: false)

    /// Smallest side of the box in metres.
    var smallestSide: Float { min(bounds.x, min(bounds.y, bounds.z)) }

    /// Height of the floor disc below the content centre, in metres.
    var floorY: Float { -bounds.y * 0.45 }
}
