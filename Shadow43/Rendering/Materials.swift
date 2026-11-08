// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import Foundation
import RealityKit

/// What a face or edge material depends on.
struct MaterialKey: Hashable {
    var style: FaceStyle
    var texture: ColorTexture
    /// 1 = opaque.
    var opacity: Float
    var blend: Blend
    var culling: Culling

    enum Blend: Hashable {
        case opaque
        /// Alpha blending without depth writes (sorted, per-cell entities).
        case alpha
        /// `.add` blending without depth writes (additive).
        case additive
    }

    enum Culling: Hashable {
        case none, front, back
    }
}

/// Creates and caches materials (DESIGN 6.5): `PhysicallyBasedMaterial` for matte/glossy,
/// `UnlitMaterial` for glowing, each with a colour texture.
@MainActor
final class MaterialFactory {
    private var textures: [ColorTexture: MaterialParameters.Texture] = [:]
    private var cache: [MaterialKey: any RealityKit.Material] = [:]
    private var unlitAdditive: UnlitMaterial.Program?
    private var litAdditive: PhysicallyBasedMaterial.Program?

    /// Whether the additive programs are ready. Until then additive falls back to alpha.
    private(set) var isReady = false

    /// Creates the `.add` blend programs (their initialisers are async).
    func prepare() async {
        var unlitDescriptor = UnlitMaterial.Program.Descriptor()
        unlitDescriptor.blendMode = .add
        unlitAdditive = await UnlitMaterial.Program(descriptor: unlitDescriptor)
        var litDescriptor = PhysicallyBasedMaterial.Program.Descriptor()
        litDescriptor.blendMode = .add
        litAdditive = await PhysicallyBasedMaterial.Program(descriptor: litDescriptor)
        isReady = true
        cache.removeAll()
    }

    func texture(_ kind: ColorTexture) -> MaterialParameters.Texture? {
        if let t = textures[kind] { return t }
        let t = kind.makeTexture()
        textures[kind] = t
        return t
    }

    func material(_ key: MaterialKey) -> any RealityKit.Material {
        if let m = cache[key] { return m }
        let m = makeMaterial(key)
        cache[key] = m
        return m
    }

    private func makeMaterial(_ key: MaterialKey) -> any RealityKit.Material {
        let texture = texture(key.texture)
        let culling: MaterialParameterTypes.FaceCulling = switch key.culling {
        case .none: .none
        case .front: .front
        case .back: .back
        }
        switch key.style {
        case .glowing:
            var m: UnlitMaterial
            if key.blend == .additive, let program = unlitAdditive {
                m = UnlitMaterial(program: program)
            } else {
                m = UnlitMaterial()
            }
            m.color = UnlitMaterial.BaseColor(tint: .white, texture: texture)
            m.faceCulling = culling
            (m.blending, m.writesDepth) = blendSettings(key)
            return m
        case .matte, .glossy:
            var m: PhysicallyBasedMaterial
            if key.blend == .additive, let program = litAdditive {
                m = PhysicallyBasedMaterial(program: program)
            } else {
                m = PhysicallyBasedMaterial()
            }
            m.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .white, texture: texture)
            m.roughness = .init(floatLiteral: key.style == .glossy ? 0.15 : 0.75)
            m.metallic = .init(floatLiteral: 0)
            if key.style == .glossy { m.clearcoat = .init(floatLiteral: 1) }
            m.faceCulling = culling
            (m.blending, m.writesDepth) = blendSettings(key)
            return m
        }
    }

    /// `UnlitMaterial.Blending` and `PhysicallyBasedMaterial.Blending` are the same type in the SDK.
    private func blendSettings(_ key: MaterialKey) -> (PhysicallyBasedMaterial.Blending, Bool) {
        switch key.blend {
        case .opaque: (.opaque, true)
        case .alpha, .additive: (.transparent(opacity: .init(floatLiteral: key.opacity)), false)
        }
    }
}
