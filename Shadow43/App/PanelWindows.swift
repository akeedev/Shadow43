// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The two panels, each in its own window so the user can move it (D25): the controls left of the
/// volume, help and About ("Info") where visionOS puts utility panels (low, in front of the user).
///
/// Neither opens at the default spot in front of the volume: a window there made visionOS push
/// the volume back and dim it (D23). Neither is restored at launch. The volume opens the controls
/// when it appears. Closing the volume or the controls closes the whole app (D34).
enum PanelWindow {
    static let controlsID = "controls"
    static let infoID = "info"

    /// Left of the volume; where the system puts utility panels if no volume is open.
    static func controlsPlacement(in context: WindowPlacementContext) -> WindowPlacement {
        guard let volume = context.windows.first(where: { $0.id == VolumeView.windowID }) else {
            return WindowPlacement(.utilityPanel)
        }
        return WindowPlacement(.leading(volume))
    }

    /// Not beside the volume: only the first window placed beside it showed up; a second one,
    /// on the other side, opened out of view (simulator, either side).
    static var infoPlacement: WindowPlacement { WindowPlacement(.utilityPanel) }
}

/// Content of the controls window. Closing it closes the app (D34).
struct ControlsWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ControlPanel()
            .onDisappear { model.isClosing = true }
            .closesWithApp(windowID: PanelWindow.controlsID)
    }
}

/// Content of the info window. Closing the window ends help mode, like its own close button.
struct InfoWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HelpPanel()
            .onDisappear { model.closeHelp() }
            .closesWithApp(windowID: PanelWindow.infoID)
    }
}

/// Closes this window, and the room, once the app is closing (D34). Every window closes itself:
/// the window that is going away may no longer be able to close the others.
struct ClosesWithApp: ViewModifier {
    let windowID: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    func body(content: Content) -> some View {
        content.onChange(of: model.isClosing) { _, closing in
            guard closing else { return }
            Task {
                if model.isRoomOpen {
                    model.isRoomOpen = false
                    await dismissImmersiveSpace()
                }
                dismissWindow(id: windowID)
            }
        }
    }
}

extension View {
    /// See `ClosesWithApp`.
    func closesWithApp(windowID: String) -> some View {
        modifier(ClosesWithApp(windowID: windowID))
    }
}
