// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import RealityKit
import SwiftUI

/// The RealityKit view that hosts the shadow content. The content depends only on the
/// `SceneHost` value, so the window and the immersive space show the same thing (DESIGN 9.3).
struct ShadowRealityView: View {
    let host: SceneHost
    @Environment(AppModel.self) private var model
    @State private var renderer: ShadowRenderer?
    @State private var subscriptions: [EventSubscription] = []

    var body: some View {
        RealityView { content in
            let renderer = ShadowRenderer(model: model, host: host)
            switch host.kind {
            case .window:
                content.add(renderer.root)
            case .room:
                // In front of the viewer, fixed in the room (D30) and level (D36): under the head's
                // pose without its pitch and roll, so the disc is parallel to the floor. The
                // tracking keeps running, so translucent faces sort towards the head (D44).
                let tracker = HeadTracker()
                var head: simd_float4x4?
                if await tracker.start() { head = await tracker.firstPose() }
                if let head {
                    let pose = LevelPose(head: Self.double(head))
                    ShadowRenderer.logger.notice("Head pose: room placed level at \(pose.position.debugDescription, privacy: .public), yaw \(pose.yaw, privacy: .public)")
                    let level = Entity()
                    level.name = "RoomLevel"
                    level.position = SIMD3<Float>(pose.position)
                    level.orientation = simd_quatf(vector: SIMD4<Float>(pose.rotation.vector))
                    level.addChild(renderer.roomBase)
                    content.add(level)
                    renderer.headTracker = tracker
                } else {
                    // Without world tracking: the head anchor, tilted if the head was; sorted
                    // towards +z, where the viewer stood.
                    tracker.stop()
                    let anchor = AnchorEntity(.head, trackingMode: .once)
                    anchor.addChild(renderer.roomBase)
                    content.add(anchor)
                }
            }
            self.renderer = renderer
            subscriptions = ManipulationProbe.subscribe(content, probe: renderer.probe, log: model.gestureLog)
        } update: { _ in
            // Also runs once the renderer exists, so a resize during setup is not lost (D19).
            renderer?.setHost(host)
        }
        .modifier(ShadowGestures())
        .onChange(of: host.bounds) { renderer?.setHost(host) }
        .onDisappear {
            renderer?.tearDown()
            subscriptions.forEach { $0.cancel() }
        }
    }

    private static func double(_ m: simd_float4x4) -> simd_double4x4 {
        simd_double4x4(columns: (SIMD4<Double>(m.columns.0), SIMD4<Double>(m.columns.1),
                                 SIMD4<Double>(m.columns.2), SIMD4<Double>(m.columns.3)))
    }
}
