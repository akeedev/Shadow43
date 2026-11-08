// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import SwiftUI

/// The control panel in its own window left of the volume (D25), at most two levels deep
/// (DESIGN 3.6): a tab row with help, About and Reset all, then the controls of that tab.
struct ControlPanel: View {
    @Environment(AppModel.self) private var model
    /// Reset all needs a second tap within a few seconds.
    @State private var isResetArmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                // Buttons, not a segmented picker: on the device the segmented picker in this
                // ornament highlighted but did not react to taps (DESIGN §8).
                ForEach(PanelTab.allCases) { tab in
                    SelectButton(title: tab.label, isSelected: model.panelTab == tab) {
                        model.panelTab = tab
                        if model.isHelpMode { model.showHelp(.tab(tab)) }
                    }
                }
                Spacer(minLength: 16)
                Button("Help", systemImage: "questionmark") { toggleHelpMode() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .tint(model.isHelpMode ? .accentColor : nil)
                Button("About", systemImage: "info.circle") {
                    if model.showsHelp && model.helpTopic == .about {
                        model.closeHelp()
                    } else {
                        model.showHelp(.about)
                    }
                }
                .buttonStyle(.bordered)
                .tint(model.showsHelp && model.helpTopic == .about ? .accentColor : nil)
                resetAllButton
            }

            Group {
                switch model.panelTab {
                case .object: ObjectSection()
                case .projection: ProjectionSection()
                case .display: DisplaySection()
                case .surface: SurfaceSection()
                case .motion: MotionSection()
                case .developer: DeveloperSection()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The window draws the glass; it takes this size (D25).
        .padding(24)
        .frame(width: 1060)
    }

    private var resetAllButton: some View {
        Button(isResetArmed ? "Confirm reset" : "Reset all",
               systemImage: "arrow.uturn.backward") {
            if isResetArmed {
                model.resetAll()
                isResetArmed = false
            } else {
                isResetArmed = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    isResetArmed = false
                }
            }
        }
        .buttonStyle(.bordered)
        .tint(isResetArmed ? .red : nil)
        .helpTarget(.resetAll)
    }

    /// "?" mode (D22): on, it shows the current tab's overview; the info window explains every
    /// control tapped afterwards. Off, it closes the info window.
    private func toggleHelpMode() {
        if model.isHelpMode {
            model.closeHelp()
        } else {
            model.isHelpMode = true
            model.showHelp(.tab(model.panelTab))
        }
    }
}
