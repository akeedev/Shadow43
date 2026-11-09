// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// The two panels, each in its own window so the user can move it (D25): the controls left of the
/// volume, help and About ("Info") below the controls (D40).
///
/// Neither opens at the default spot in front of the volume: a window there made visionOS push
/// the volume back and dim it (D23). Neither is restored at launch. The volume opens the controls
/// when it appears, and the controls open and close Info (D46). Closing the volume or the
/// controls closes the whole app (D34).
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

    /// Below the controls, wherever the user has put them (D40), so Info comes back near them each
    /// time it opens. Not beside the volume: a second window placed there opened out of view
    /// (simulator). Where the system puts utility panels if the controls are closed.
    static func infoPlacement(in context: WindowPlacementContext) -> WindowPlacement {
        guard let controls = context.windows.first(where: { $0.id == controlsID }) else {
            return WindowPlacement(.utilityPanel)
        }
        return WindowPlacement(.below(controls))
    }
}

/// Content of the controls window. It opens and closes Info as the help topic comes and goes
/// (D46). Closing it closes the app (D34).
struct ControlsWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ControlPanel()
            // Info opened together with the controls (help at launch) would not find them yet
            // and land at the utility-panel spot; opened from here it goes below them (D40).
            .onAppear { if model.helpTopic != nil { openWindow(id: PanelWindow.infoID) } }
            .onChange(of: model.helpTopic != nil) { _, shows in
                if shows {
                    openWindow(id: PanelWindow.infoID)
                } else {
                    dismissWindow(id: PanelWindow.infoID)
                }
            }
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
