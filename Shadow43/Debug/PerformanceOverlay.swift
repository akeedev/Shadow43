// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import SwiftUI

/// Spike S2: frame time, CPU time of the per-frame pipeline and triangle count.
struct PerformanceOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.stats
        let fps = s.frameTimeMs > 0 ? 1000 / s.frameTimeMs : 0
        HStack(spacing: 20) {
            Text("Frame \(s.frameTimeMs, specifier: "%.1f") ms (\(fps, specifier: "%.0f") Hz)")
            Text("CPU \(s.cpuTimeMs, specifier: "%.1f") ms (build \(s.buildTimeMs, specifier: "%.1f"))")
            Text("\(s.triangles) triangles")
            Text("\(s.vertices) vertices")
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .glassBackgroundEffect()
    }
}
