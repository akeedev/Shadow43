// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import RealityKit
import SwiftUI

/// Shadow43: the rotating 3D shadow of 4D objects.
///
/// v1 shows a volumetric window. An `ImmersiveSpace` (mixed immersion) hosts the same content
/// and shares the same `AppModel` (DESIGN 3.5, D5).
@main
struct Shadow43App: App {
    @State private var model: AppModel
    @State private var roomStyle: any ImmersionStyle = MixedImmersionStyle()

    init() {
        let model = AppModel()
        let config = SnapshotMode.launchConfiguration()
        model.apply(config)
        SnapshotMode.log(config)
        _model = State(initialValue: model)
        ShadowSystem.registerSystem()
    }

    // `SwiftUI.Scene` must be qualified because RealityKit also defines `Scene` (DESIGN 6.1).
    var body: some SwiftUI.Scene {
        WindowGroup(id: VolumeView.windowID) {
            VolumeView()
                .environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: Double(SceneHost.window.bounds.x),
                     height: Double(SceneHost.window.bounds.y),
                     depth: Double(SceneHost.window.bounds.z), in: .meters)

        ImmersiveSpace(id: RoomView.spaceID) {
            RoomView()
                .environment(model)
        }
        .immersionStyle(selection: $roomStyle, in: .mixed)
    }
}
