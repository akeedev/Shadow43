// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import SwiftUI

/// The control panel in the ornament below the window, at most two levels deep (DESIGN 3.6):
/// a tab row, then the controls of that tab.
struct ControlPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            Picker("Section", selection: $model.panelTab) {
                ForEach(PanelTab.allCases) { tab in
                    Text(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch model.panelTab {
                case .object: ObjectSection()
                case .projection: ProjectionSection()
                case .display: DisplaySection()
                case .motion: MotionSection()
                case .developer: DeveloperSection()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 980)
        .glassBackgroundEffect()
    }
}
