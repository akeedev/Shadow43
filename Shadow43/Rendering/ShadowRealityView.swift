// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import RealityKit
import SwiftUI

/// The RealityKit view that hosts the shadow content. The content depends only on the
/// `SceneHost` value, so the window and the immersive space show the same thing (DESIGN 3.5).
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
                // Placed once in front of the viewer's head, then fixed in the room (D30). If the
                // head is tilted at that moment, the content is tilted too [verify on device].
                let anchor = AnchorEntity(.head, trackingMode: .once)
                anchor.addChild(renderer.root)
                content.add(anchor)
            }
            self.renderer = renderer
            subscriptions = ManipulationProbe.subscribe(content, log: model.gestureLog)
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
}
