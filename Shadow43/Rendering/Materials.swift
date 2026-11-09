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

/// The `.add` blend programs of the additive transparency method, created once for the whole
/// app: their initialisers are async, and every renderer, the room's too, shares them. Until they
/// exist, additive is drawn sorted (D47).
@MainActor
enum AdditivePrograms {
    private(set) static var unlit: UnlitMaterial.Program?
    private(set) static var lit: PhysicallyBasedMaterial.Program?
    private static var task: Task<Void, Never>?

    static var isReady: Bool { unlit != nil && lit != nil }

    /// Starts creating the programs, once.
    static func prepare() {
        guard task == nil else { return }
        task = Task {
            var unlitDescriptor = UnlitMaterial.Program.Descriptor()
            unlitDescriptor.blendMode = .add
            let unlitProgram = await UnlitMaterial.Program(descriptor: unlitDescriptor)
            var litDescriptor = PhysicallyBasedMaterial.Program.Descriptor()
            litDescriptor.blendMode = .add
            let litProgram = await PhysicallyBasedMaterial.Program(descriptor: litDescriptor)
            unlit = unlitProgram
            lit = litProgram
        }
    }
}

/// Creates and caches materials (DESIGN 11.6): `PhysicallyBasedMaterial` for the lit styles,
/// `UnlitMaterial` for glowing, each with a colour texture.
@MainActor
final class MaterialFactory {
    private var textures: [ColorTexture: MaterialParameters.Texture] = [:]
    private var cache: [MaterialKey: any RealityKit.Material] = [:]
    /// The opacity is part of the key, so moving its slider would add a material per value.
    private static let cacheLimit = 64

    func texture(_ kind: ColorTexture) -> MaterialParameters.Texture? {
        if let t = textures[kind] { return t }
        let t = kind.makeTexture()
        textures[kind] = t
        return t
    }

    func material(_ key: MaterialKey) -> any RealityKit.Material {
        if let m = cache[key] { return m }
        if cache.count >= Self.cacheLimit { cache.removeAll() }
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
            if key.blend == .additive, let program = AdditivePrograms.unlit {
                m = UnlitMaterial(program: program)
            } else {
                m = UnlitMaterial()
            }
            m.color = UnlitMaterial.BaseColor(tint: .white, texture: texture)
            m.faceCulling = culling
            (m.blending, m.writesDepth) = blendSettings(key)
            return m
        case .matte, .glossy, .metal, .ceramic, .frostedGlass:
            var m: PhysicallyBasedMaterial
            if key.blend == .additive, let program = AdditivePrograms.lit {
                m = PhysicallyBasedMaterial(program: program)
            } else {
                m = PhysicallyBasedMaterial()
            }
            m.baseColor = PhysicallyBasedMaterial.BaseColor(tint: .white, texture: texture)
            let look = Self.look(key.style)
            m.roughness = .init(floatLiteral: look.roughness)
            m.metallic = .init(floatLiteral: look.metallic)
            if look.clearcoat > 0 {
                m.clearcoat = .init(floatLiteral: look.clearcoat)
                m.clearcoatRoughness = .init(floatLiteral: look.clearcoatRoughness)
            }
            m.faceCulling = culling
            (m.blending, m.writesDepth) = blendSettings(key)
            return m
        }
    }

    /// Surface parameters of the lit styles. Metal, ceramic and frosted glass are the
    /// experimental looks of D24; the room's lighting gives the reflections.
    private static func look(_ style: FaceStyle) -> (roughness: Float, metallic: Float, clearcoat: Float,
                                                      clearcoatRoughness: Float) {
        switch style {
        case .glossy: (0.15, 0, 1, 0)
        case .metal: (0.22, 1, 0, 0)
        case .ceramic: (0.35, 0, 1, 0.05)
        case .frostedGlass: (0.6, 0, 0.5, 0.3)
        case .matte, .glowing: (0.75, 0, 0, 0)
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
