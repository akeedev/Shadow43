// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import RealityKit
import SwiftUI

/// Shadow43: the rotating 3D shadow of 4D objects.
///
/// v1 shows a volumetric window with two panel windows beside it (D25). An `ImmersiveSpace`
/// (mixed immersion) hosts the same content and shares the same `AppModel` (DESIGN 3.5, D5).
@main
struct Shadow43App: App {
    @State private var model: AppModel
    @State private var roomStyle: any ImmersionStyle = MixedImmersionStyle()

    init() {
        let model = AppModel()
        // The saved settings are the base, launch arguments change it. In snapshot mode (any
        // recognised launch argument) the app starts from the defaults and saves nothing (D29).
        let args = SnapshotMode.launchArguments()
        let isSnapshot = LaunchConfiguration.isSnapshot(args)
        let saved = isSnapshot ? nil : SettingsStore.load()
        let config = LaunchConfiguration.parse(args, base: saved?.state ?? ViewState())
        model.apply(config)
        if let saved { model.gestureMapping = saved.gestureMapping }
        model.persistsSettings = !isSnapshot
        SnapshotMode.log(config)
        _model = State(initialValue: model)
        ShadowSystem.registerSystem()
        ShadowInputComponent.registerComponent()
    }

    // `SwiftUI.Scene` must be qualified because RealityKit also defines `Scene` (DESIGN 6.1).
    var body: some SwiftUI.Scene {
        WindowGroup(id: VolumeView.windowID) {
            VolumeView()
                .environment(model)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: Double(SceneHost.defaultWindowBounds.x),
                     height: Double(SceneHost.defaultWindowBounds.y),
                     depth: Double(SceneHost.defaultWindowBounds.z), in: .meters)
        // The user can resize the volume; VolumeView sets the minimum (D19).
        .windowResizability(.contentMinSize)

        // The panels are windows of their own, so they can be moved (D25). The volume opens and
        // closes them; the system neither opens them at launch nor restores them.
        Window("Controls", id: PanelWindow.controlsID) {
            ControlsWindow()
                .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, context in PanelWindow.controlsPlacement(in: context) }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("Info", id: PanelWindow.infoID) {
            InfoWindow()
                .environment(model)
        }
        .defaultSize(HelpPanel.defaultSize)
        .windowResizability(.contentMinSize)
        .defaultWindowPlacement { _, context in PanelWindow.infoPlacement(in: context) }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        ImmersiveSpace(id: RoomView.spaceID) {
            RoomView()
                .environment(model)
        }
        .immersionStyle(selection: $roomStyle, in: .mixed)
    }
}
