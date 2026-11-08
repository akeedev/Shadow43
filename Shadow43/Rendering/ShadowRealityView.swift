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
            content.add(renderer.root)
            self.renderer = renderer
            subscriptions = ManipulationProbe.subscribe(content, log: model.gestureLog)
        }
        .modifier(ShadowGestures())
        .onDisappear {
            renderer?.tearDown()
            subscriptions.forEach { $0.cancel() }
        }
    }
}
