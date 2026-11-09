// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Supplies the viewer's position in content coordinates, if the host knows it.
/// The volumetric window does not; the immersive space can later use ARKit world tracking.
@MainActor
protocol ViewerPoseProvider: AnyObject {
    func viewerPosition() -> SIMD3<Float>?
}

/// Everything that differs between the volumetric window and the immersive space (DESIGN 9.3).
/// Scene content depends only on this value, never on the hosting scene itself.
@MainActor
struct SceneHost {
    enum Kind { case window, room }

    var kind: Kind
    /// Size of the available box in metres. The object is sized automatically to fill
    /// `SizeFit.fillFraction` of its smallest side (D15).
    var bounds: SIMD3<Float>
    /// Nil in the window.
    var viewerPose: ViewerPoseProvider?
    /// Content offset in metres: from the window's centre, or in the room from the viewer's head
    /// when the room opened (D30).
    var contentOffset: SIMD3<Float>
    /// Whether the host reports which side of the volume the viewer is on (window only, D17).
    var tracksVolumeViewpoint: Bool
    /// Box side (metres) at which edge and face thickness are relative to the fitted radius;
    /// they keep that size in metres when the object is zoomed or the window resized (D28).
    var thicknessReferenceSide: Float

    /// Default size of the volumetric window: a 1 m box. The user can resize it (D19).
    static let defaultWindowBounds: SIMD3<Float> = [1, 1, 1]
    /// Smallest side the user can resize the window to, in metres.
    static let minimumWindowSide: Float = 0.5
    /// How far the shadow may reach out of the volume on every side before it is clipped, in
    /// metres, as requested from the system; it may grant less (D27).
    static let requestedClippingMargin: Float = 0.5

    /// The volumetric window with its current size.
    static func window(bounds: SIMD3<Float> = defaultWindowBounds) -> SceneHost {
        SceneHost(kind: .window, bounds: bounds, viewerPose: nil, contentOffset: .zero,
                  tracksVolumeViewpoint: true, thicknessReferenceSide: defaultWindowBounds.min())
    }
    /// The immersive space (D30, D36): a 2.4 × 2 × 2.4 m box whose centre is placed once, level,
    /// 2 m in front of the viewer's eyes and 15 cm lower; the object is then about 1.5 m across.
    static let room = SceneHost(kind: .room, bounds: [2.4, 2, 2.4], viewerPose: nil,
                                contentOffset: [0, -0.15, -2], tracksVolumeViewpoint: false,
                                thicknessReferenceSide: 2)

    /// Smallest side of the box in metres.
    var smallestSide: Float { min(bounds.x, min(bounds.y, bounds.z)) }

    /// Height of the floor disc below the content centre, in metres.
    var floorY: Float { -bounds.y * 0.45 }
}
