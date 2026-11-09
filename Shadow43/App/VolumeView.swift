// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import SwiftUI

/// Content of the volumetric window: the shadow. It opens the controls when it appears (D25) and
/// opens and closes the info window as the model asks. Closing it closes the app (D34).
struct VolumeView: View {
    /// Also read by the panels' placement closures, which are not on the main actor.
    nonisolated static let windowID = "volume"

    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.physicalMetrics) private var metrics
    /// Current size of the volume in metres; follows the user's resizing (D19).
    @State private var bounds = SceneHost.defaultWindowBounds
    @PhysicalMetric(from: .meters) private var minimumSide = CGFloat(SceneHost.minimumWindowSide)
    @PhysicalMetric(from: .meters) private var clippingMargin = CGFloat(SceneHost.requestedClippingMargin)
    /// The margins the system actually granted (points).
    @Environment(\.windowClippingMargins) private var grantedMargins

    var body: some View {
        ShadowRealityView(host: .window(bounds: bounds))
            .frame(minWidth: minimumSide, minHeight: minimumSide)
            .frame(minDepth: minimumSide)
            .background { SettingsSaver() }
            // Large or enlarged shadows may reach out of the volume instead of being cut off at
            // its walls (D27).
            .preferredWindowClippingMargins(.all, clippingMargin)
            .onChange(of: grantedMargins, initial: true) { _, m in
                let cm = { (pt: CGFloat) in Int((metrics.convert(pt, to: .meters) * 100).rounded()) }
                ShadowRenderer.logger.notice("Clipping margins granted (cm): top \(cm(m.top), privacy: .public), bottom \(cm(m.bottom), privacy: .public), leading \(cm(m.leading), privacy: .public), trailing \(cm(m.trailing), privacy: .public), front \(cm(m.front), privacy: .public), back \(cm(m.back), privacy: .public)")
            }
            .onGeometryChange3D(for: Size3D.self) { $0.size } action: { size in
                let metres = SIMD3(Float(metrics.convert(size.width, to: .meters)),
                                   Float(metrics.convert(size.height, to: .meters)),
                                   Float(metrics.convert(size.depth, to: .meters)))
                ShadowRenderer.logger.debug("Volume size \(size.width, privacy: .public) × \(size.height, privacy: .public) × \(size.depth, privacy: .public) pt = \(metres.x, privacy: .public) × \(metres.y, privacy: .public) × \(metres.z, privacy: .public) m")
                // Ignore the zero size before the first layout.
                if metres.min() > 0.05 { bounds = metres }
            }
            // The window's only hint where the viewer is: the side of the volume (D17). `.all`
            // reports every side without changing which viewpoints the volume supports.
            .onVolumeViewpointChange(updateStrategy: .all) { _, viewpoint in
                model.systemViewSide = ViewSide(viewpoint.squareAzimuth)
            }
            .ornament(visibility: model.developer.showsPerformanceOverlay ? .visible : .hidden,
                      attachmentAnchor: .scene(.topFront), contentAlignment: .bottom) {
                PerformanceOverlay()
            }
            .ornament(visibility: model.developer.showsGestureTest ? .visible : .hidden,
                      attachmentAnchor: .scene(.topTrailingFront), contentAlignment: .bottomLeading) {
                GestureTestPanel()
            }
            .onAppear {
                model.isClosing = false
                // The controls open Info if needed, once they exist to place it by (D40).
                openWindow(id: PanelWindow.controlsID)
            }
            .onChange(of: model.showsHelp) { _, shows in
                if shows {
                    openWindow(id: PanelWindow.infoID)
                } else {
                    dismissWindow(id: PanelWindow.infoID)
                }
            }
            // Closing the volume closes the app; the panels close themselves (D34).
            .onDisappear { model.isClosing = true }
            .closesWithApp(windowID: VolumeView.windowID)
            .task {
                if SnapshotMode.opensRoomAtLaunch, !model.isRoomOpen {
                    let result = await openImmersiveSpace(id: RoomView.spaceID)
                    ShadowRenderer.logger.notice("Open in room at launch: \(String(describing: result), privacy: .public)")
                    if case .opened = result { model.isRoomOpen = true }
                }
            }
    }
}

extension ViewSide {
    init(_ azimuth: SquareAzimuth) {
        switch azimuth {
        case .front: self = .front
        case .right: self = .right
        case .back: self = .back
        case .left: self = .left
        }
    }
}
