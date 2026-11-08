// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import RealityKit
import SwiftUI
import UIKit

/// Spike S3: shows the raw values of every gesture, including the `ManipulationComponent`
/// events of a small probe sphere (variant C, not shipped).
struct GestureTestPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let log = model.gestureLog
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            GridRow { Text("Drag").bold(); Text(log.drag) }
            GridRow { Text("Rotate 3D").bold(); Text(log.rotate) }
            GridRow { Text("Magnify").bold(); Text(log.magnify) }
            GridRow { Text("Tap").bold(); Text(log.tap) }
            GridRow { Text("Manipulation (C)").bold(); Text(log.manipulation) }
        }
        .font(.callout.monospacedDigit())
        .frame(width: 640, alignment: .leading)
        .padding(20)
        .glassBackgroundEffect()
        .onAppear { log.isRecording = true }
        .onDisappear { log.isRecording = false }
    }
}

/// The probe for variant C: a small sphere with a `ManipulationComponent`. Its transform
/// updates are logged; turning the wrist would map to 3D rotation and moving the hand to 4D.
@MainActor
enum ManipulationProbe {
    static func make(at position: SIMD3<Float>) -> ModelEntity {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(red: 1, green: 0.8, blue: 0.3, alpha: 1))
        material.roughness = .init(floatLiteral: 0.3)
        let probe = ModelEntity(mesh: .generateSphere(radius: 0.04), materials: [material])
        probe.name = "ManipulationProbe"
        probe.position = position
        ManipulationComponent.configureEntity(probe, collisionShapes: [.generateSphere(radius: 0.04)])
        var manipulation = ManipulationComponent()
        manipulation.releaseBehavior = .reset
        probe.components.set(manipulation)
        return probe
    }

    /// Subscribes to the manipulation events and writes them into the gesture log.
    static func subscribe(_ content: RealityViewContent, log: GestureLog) -> [EventSubscription] {
        [
            content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                log.record(manipulation: "begin, \(event.inputDeviceSet.count) input(s)")
            },
            content.subscribe(to: ManipulationEvents.DidUpdateTransform.self) { event in
                let t = event.entity.transform
                let q = t.rotation
                log.record(manipulation: "t \(format(t.translation)), angle "
                    + String(format: "%.1f° axis ", q.angle * 180 / .pi) + format(q.axis))
            },
            content.subscribe(to: ManipulationEvents.WillEnd.self) { _ in
                log.record(manipulation: "end")
            },
        ]
    }
}
