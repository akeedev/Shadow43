// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import RealityKit
import simd
import UIKit

/// The object's four 4D axes (D20): one thin line per axis from −eᵢ to +eᵢ, rotated and projected
/// with the object (`AxisCross`), and a label at the + end that always faces the viewer.
///
/// Lives in metres next to the scaled content, so line thickness and labels keep their size.
/// Only transforms change per frame; the meshes are built once.
@MainActor
final class AxisEntities {
    let root = Entity()
    private var lines: [ModelEntity] = []
    private var labels: [Entity] = []

    static let names = ["x", "y", "z", "w"]
    static let colors: [UIColor] = [
        UIColor(red: 0.95, green: 0.25, blue: 0.2, alpha: 1),
        UIColor(red: 0.3, green: 0.85, blue: 0.3, alpha: 1),
        UIColor(red: 0.3, green: 0.5, blue: 1, alpha: 1),
        UIColor(red: 1, green: 0.8, blue: 0.1, alpha: 1),
    ]
    /// Line radius in metres.
    static let lineRadius: Float = 0.003
    /// Label height in metres, and its gap beyond the + end.
    static let labelSize: Float = 0.045

    init() {
        root.name = "Axes"
        root.isEnabled = false
        let unitCylinder = MeshResource.generateCylinder(height: 1, radius: 1)
        for i in 0..<4 {
            let material = UnlitMaterial(color: Self.colors[i])
            let line = ModelEntity(mesh: unitCylinder, materials: [material])
            line.name = "Axis-\(Self.names[i])"
            line.components.set(DynamicLightShadowComponent(castsShadow: false))
            root.addChild(line)
            lines.append(line)

            let text = MeshResource.generateText(Self.names[i], extrusionDepth: 0.002,
                                                 font: .systemFont(ofSize: CGFloat(Self.labelSize), weight: .semibold))
            let glyph = ModelEntity(mesh: text, materials: [material])
            glyph.position = -text.bounds.center  // centre the letter on its anchor
            glyph.components.set(DynamicLightShadowComponent(castsShadow: false))
            let label = Entity()
            label.name = "AxisLabel-\(Self.names[i])"
            label.components.set(BillboardComponent())
            label.addChild(glyph)
            root.addChild(label)
            labels.append(label)
        }
    }

    /// Places lines and labels for the projected axes (object units → metres).
    func update(_ axes: [AxisCross.Axis], metresPerUnit: Float) {
        for axis in axes where axis.index < lines.count {
            let a = SIMD3<Float>(axis.negativeEnd) * metresPerUnit
            let b = SIMD3<Float>(axis.positiveEnd) * metresPerUnit
            let span = b - a
            let length = simd_length(span)
            let line = lines[axis.index]
            // An axis along w collapses to a point: only its label stays, at the centre.
            line.isEnabled = length > 1e-4
            if line.isEnabled {
                line.position = (a + b) / 2
                line.orientation = simd_quatf(from: [0, 1, 0], to: span / length)
                line.scale = [Self.lineRadius, length, Self.lineRadius]
            }
            let outwards = simd_length(b) > 1e-4 ? simd_normalize(b) : SIMD3<Float>.zero
            labels[axis.index].position = b + outwards * Self.labelSize
        }
    }
}
