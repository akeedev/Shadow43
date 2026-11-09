// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import ARKit
import QuartzCore

/// The viewer's head in the room, from ARKit world tracking: read once when the room opens, to
/// place the content level (D36), then every frame, to sort translucent faces towards the head
/// (D44). ARKit's origin is the immersive space's origin, and both are gravity-aligned (y up).
@MainActor
final class HeadTracker {
    private let session = ARKitSession()
    private let provider = WorldTrackingProvider()
    private var isRunning = false

    /// Starts world tracking. False if it is not supported, would need an authorization, or does
    /// not start.
    func start() async -> Bool {
        let log = ShadowRenderer.logger
        guard WorldTrackingProvider.isSupported else {
            log.notice("Head pose: world tracking is not supported")
            return false
        }
        // World tracking needs no authorization [verify]; never ask for one without a usage text.
        guard WorldTrackingProvider.requiredAuthorizations.isEmpty else {
            log.notice("Head pose: world tracking needs \(String(describing: WorldTrackingProvider.requiredAuthorizations), privacy: .public)")
            return false
        }
        do {
            try await session.run([provider])
        } catch {
            log.error("Head pose: world tracking did not start: \(error.localizedDescription, privacy: .public)")
            return false
        }
        isRunning = true
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        session.stop()
    }

    /// The head's transform in the immersive space now, if it is tracked.
    func headTransform() -> simd_float4x4? {
        guard isRunning, let device = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              device.isTracked else { return nil }
        return device.originFromAnchorTransform
    }

    /// The head's position in the immersive space now, if it is tracked.
    func headPosition() -> SIMD3<Float>? {
        headTransform().map { SIMD3($0.columns.3.x, $0.columns.3.y, $0.columns.3.z) }
    }

    /// The first tracked pose within `timeout`, to place the room.
    func firstPose(timeout: Duration = .seconds(2)) async -> simd_float4x4? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let head = headTransform() { return head }
            try? await Task.sleep(for: .milliseconds(50))
        }
        ShadowRenderer.logger.notice("Head pose: no tracked pose within \(timeout, privacy: .public)")
        return nil
    }
}
