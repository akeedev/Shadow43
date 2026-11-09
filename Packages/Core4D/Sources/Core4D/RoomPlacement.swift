// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Where the room content goes (D36): the viewer's head pose without its pitch and roll, so the
/// content and its floor disc stay level however the head was tilted when the room opened.
public struct LevelPose: Equatable, Sendable {
    /// The head's position.
    public var position: SIMD3<Double>
    /// Turn about the vertical (+y) axis, in radians; 0 looks along −z.
    public var yaw: Double

    public init(position: SIMD3<Double>, yaw: Double) {
        self.position = position
        self.yaw = yaw
    }

    /// The level pose of a head transform in a gravity-aligned space (y up), as ARKit reports
    /// the device. The viewing direction is the head's −z axis projected onto the floor; when
    /// looking straight up or down, the head's up (+y) or down axis, which then points forward.
    public init(head: simd_double4x4) {
        let position = SIMD3(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let back = SIMD3(head.columns.2.x, head.columns.2.y, head.columns.2.z)
        let up = SIMD3(head.columns.1.x, head.columns.1.y, head.columns.1.z)
        var forward = SIMD3(-back.x, 0, -back.z)
        if simd_length(forward) < 1e-3 {
            // Looking up (back points down) the top of the head points backwards, so use −up.
            let sign: Double = back.y < 0 ? -1 : 1
            forward = SIMD3(sign * up.x, 0, sign * up.z)
        }
        let yaw = simd_length(forward) < 1e-9 ? 0 : atan2(-forward.x, -forward.z)
        self.init(position: position, yaw: yaw)
    }

    /// The rotation about +y by `yaw`.
    public var rotation: simd_quatd { simd_quatd(angle: yaw, axis: [0, 1, 0]) }
}
