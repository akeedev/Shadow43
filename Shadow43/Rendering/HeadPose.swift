// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import ARKit
import QuartzCore

/// The viewer's head pose, read once from ARKit's world tracking when the room opens (D36).
/// ARKit's origin is the immersive space's origin, and both are gravity-aligned (y up).
enum HeadPose {
    /// The head's transform in the immersive space, or nil if world tracking is not available,
    /// would need an authorization, or reports no tracked pose within `timeout`.
    @MainActor
    static func current(timeout: Duration = .seconds(2)) async -> simd_float4x4? {
        let log = ShadowRenderer.logger
        guard WorldTrackingProvider.isSupported else {
            log.notice("Head pose: world tracking is not supported")
            return nil
        }
        // World tracking needs no authorization [verify]; never ask for one without a usage text.
        guard WorldTrackingProvider.requiredAuthorizations.isEmpty else {
            log.notice("Head pose: world tracking needs \(String(describing: WorldTrackingProvider.requiredAuthorizations), privacy: .public)")
            return nil
        }
        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        do {
            try await session.run([provider])
        } catch {
            log.error("Head pose: world tracking did not start: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        defer { session.stop() }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let device = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), device.isTracked {
                return device.originFromAnchorTransform
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        log.notice("Head pose: no tracked pose within \(timeout, privacy: .public)")
        return nil
    }
}
