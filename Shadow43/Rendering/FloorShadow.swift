// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import RealityKit
import UIKit

/// The shadow of the shadow (DESIGN 6.4, spike S4): a light from above casts the 3D projection's
/// shadow onto a subtle floor disc. Floor and light live in metres, outside the scaled content.
///
/// Two methods, switchable in the Developer section: a `DirectionalLightComponent` with a shadow
/// (the design's choice), or `GroundingShadowComponent` (the fallback).
@MainActor
final class FloorShadow {
    let root = Entity()
    let disc: ModelEntity
    let light = Entity()
    private var casters: [Entity] = []
    private var method: FloorShadowMethod?
    private var enabled: Bool?
    /// The disc is the room's handle (D33, D39): it then lives beside the content, not in `root`,
    /// and stays visible even without the floor shadow.
    private var isHandle = false

    init(host: SceneHost) {
        root.name = "FloorShadow"
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: UIColor(white: 0.9, alpha: 1))
        material.roughness = .init(floatLiteral: 1)
        material.metallic = .init(floatLiteral: 0)
        // Unit radius, scaled to the box in `layout(for:)`.
        disc = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 1), materials: [material])
        disc.name = "FloorDisc"
        disc.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(disc)

        light.name = "FloorLight"
        light.components.set(DirectionalLightComponent(color: .white, intensity: 3000))
        // (A `.fixed` orthographic shadow camera showed no shadow at all in the simulator.)
        light.components.set(DirectionalLightComponent.Shadow(maximumDistance: 4, depthBias: 1))
        // A directional light shines along its −z axis; turn −z to −y (straight down).
        light.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        root.addChild(light)
        layout(for: host)
    }

    /// Where the disc sits relative to the content's root.
    private(set) var discOffset: SIMD3<Float> = .zero

    /// Sizes and places disc and light for the host's box (also after a resize, D19).
    func layout(for host: SceneHost) {
        let radius = 0.3 * min(host.bounds.x, host.bounds.z)
        disc.scale = [radius, 1, radius]
        discOffset = [0, host.floorY, 0]
        // A handle is placed by its owner and then moved by the user.
        if !isHandle { disc.position = discOffset }
        light.position = [0, host.bounds.y * 0.48, 0]
    }

    /// Makes the disc a handle that the user moves with the system's manipulation, translation
    /// only (D33, D39), and takes it out of `root`; the caller adds it beside the content, places
    /// it and makes the content follow it. The collision box is in the disc's unit-radius space
    /// and scales with it.
    func makeHandle() -> ModelEntity {
        isHandle = true
        disc.removeFromParent()
        disc.components.set(CollisionComponent(shapes: [.generateBox(width: 2, height: 0.06, depth: 2)]))
        disc.components.set(InputTargetComponent())
        disc.components.set(HoverEffectComponent())
        var manipulation = ManipulationComponent()
        manipulation.releaseBehavior = .stay
        manipulation.dynamics.translationBehavior = .unconstrained
        manipulation.dynamics.primaryRotationBehavior = .none
        manipulation.dynamics.secondaryRotationBehavior = .none
        manipulation.dynamics.scalingBehavior = .none
        manipulation.dynamics.inertia = .zero
        disc.components.set(manipulation)
        enabled = nil
        return disc
    }

    /// Registers entities that cast the shadow (the content's mesh entities).
    func attachCaster(_ entity: Entity) {
        casters.append(entity)
        method = nil
    }

    /// A caster got new children (the cell entities): the next `update` sets them up by the
    /// current method too.
    func refreshCasters() {
        method = nil
    }

    func update(enabled: Bool, method newMethod: FloorShadowMethod) {
        guard enabled != self.enabled || newMethod != method else { return }
        self.enabled = enabled
        method = newMethod
        root.isEnabled = enabled || isHandle
        let useLight = enabled && newMethod == .directionalLight
        let useGrounding = enabled && newMethod == .grounding
        light.isEnabled = useLight
        for caster in casters { setCasting(caster, light: useLight, grounding: useGrounding) }
        disc.components.set(GroundingShadowComponent(castsShadow: false, receivesShadow: useGrounding))
    }

    private func setCasting(_ entity: Entity, light: Bool, grounding: Bool) {
        entity.components.set(DynamicLightShadowComponent(castsShadow: light))
        if grounding {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        } else {
            entity.components.remove(GroundingShadowComponent.self)
        }
        for child in entity.children { setCasting(child, light: light, grounding: grounding) }
    }
}
