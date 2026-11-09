// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

/// Level placement of the room content (D36).
@Suite("Room placement")
struct RoomPlacementTests {
    private func head(at position: SIMD3<Double>, yaw: Double, pitch: Double, roll: Double = 0) -> simd_double4x4 {
        let r = simd_quatd(angle: yaw, axis: [0, 1, 0]) * simd_quatd(angle: pitch, axis: [1, 0, 0])
            * simd_quatd(angle: roll, axis: [0, 0, 1])
        var m = simd_double4x4(r)
        m.columns.3 = SIMD4(position, 1)
        return m
    }

    @Test func pitchAndRollAreDropped() {
        for pitch in [-1.2, -0.4, 0, 0.5, 1.3] {
            for roll in [-0.3, 0, 0.6] {
                let pose = LevelPose(head: head(at: [0.3, 1.6, -0.2], yaw: 0.8, pitch: pitch, roll: roll))
                #expect(abs(pose.yaw - 0.8) < 1e-9, "pitch \(pitch) roll \(roll)")
                #expect(simd_length(pose.position - [0.3, 1.6, -0.2]) < 1e-12)
            }
        }
    }

    @Test func yawTurnsMinusZIntoTheViewingDirection() {
        // Turned 90° to the left: looking along −x.
        let pose = LevelPose(head: head(at: .zero, yaw: .pi / 2, pitch: 0))
        let forward = pose.rotation.act(SIMD3<Double>(0, 0, -1))
        #expect(simd_length(forward - [-1, 0, 0]) < 1e-9)
    }

    @Test func lookingStraightDownOrUpKeepsTheDirection() {
        let down = LevelPose(head: head(at: .zero, yaw: 0.5, pitch: -.pi / 2))
        let up = LevelPose(head: head(at: .zero, yaw: 0.5, pitch: .pi / 2))
        #expect(abs(down.yaw - 0.5) < 1e-6)
        #expect(abs(up.yaw - 0.5) < 1e-6)
    }

    @Test func sortDirectionTurnsOnlyPastTheThreshold() {
        // D44: small head movements keep the order; walking round the object re-sorts.
        let front = SIMD3<Float>(0, 0, 1)
        let small = SIMD3<Float>(sin(0.1), 0, cos(0.1)) * 2
        #expect(SortDirection.update(front, towards: small) == front)
        let large = SIMD3<Float>(sin(0.3), 0, cos(0.3)) * 2
        #expect(simd_distance(SortDirection.update(front, towards: large), simd_normalize(large)) < 1e-6)
        let behind = SortDirection.update(front, towards: [0, 0.2, -3])
        #expect(behind.z < -0.9 && abs(simd_length(behind) - 1) < 1e-6)
        // A head at the centre gives no direction.
        #expect(SortDirection.update(front, towards: .zero) == front)
    }
}
