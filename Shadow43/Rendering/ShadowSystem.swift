// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import RealityKit

/// Marks the root entity of the shadow content and gives the system its renderer.
struct ShadowComponent: Component {
    let renderer: ShadowRenderer
}

/// Drives the per-frame pipeline (DESIGN 6.3) for every shadow root in the scene.
struct ShadowSystem: System {
    private static let query = EntityQuery(where: .has(ShadowComponent.self))

    init(scene: RealityKit.Scene) {}

    mutating func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            entity.components[ShadowComponent.self]?.renderer.update(deltaTime: context.deltaTime)
        }
    }
}
