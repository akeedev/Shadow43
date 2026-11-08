// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import SwiftUI

/// Content of the volumetric window: the shadow plus the control panel in an ornament.
struct VolumeView: View {
    static let windowID = "volume"

    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        ShadowRealityView(host: .window)
            // The window's only hint where the viewer is: the side of the volume (D17). `.all`
            // reports every side without changing which viewpoints the volume supports.
            .onVolumeViewpointChange(updateStrategy: .all) { _, viewpoint in
                model.systemViewSide = ViewSide(viewpoint.squareAzimuth)
            }
            .ornament(attachmentAnchor: .scene(.bottomFront), contentAlignment: .top) {
                ControlPanel()
            }
            .ornament(visibility: model.developer.showsPerformanceOverlay ? .visible : .hidden,
                      attachmentAnchor: .scene(.topFront), contentAlignment: .bottom) {
                PerformanceOverlay()
            }
            .ornament(visibility: model.developer.showsGestureTest ? .visible : .hidden,
                      attachmentAnchor: .scene(.trailingFront), contentAlignment: .leading) {
                GestureTestPanel()
            }
            .task {
                if SnapshotMode.opensRoomAtLaunch, !model.isRoomOpen {
                    if case .opened = await openImmersiveSpace(id: RoomView.spaceID) {
                        model.isRoomOpen = true
                    }
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
