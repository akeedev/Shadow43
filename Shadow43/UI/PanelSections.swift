// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import SwiftUI

/// Object choice, grouped by kind; p and q for duoprisms.
struct ObjectSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            ForEach([ObjectKind.polytope, .surface, .curves], id: \.self) { kind in
                HStack(spacing: 8) {
                    Text(kind.label).font(.headline).frame(width: 100, alignment: .leading)
                    ForEach(ObjectID.allCases.filter { $0.kind == kind }, id: \.self) { id in
                        SelectButton(title: id.label, isSelected: model.object == id) {
                            model.object = id
                        }
                    }
                }
            }
            if model.object == .duoprism {
                HStack(spacing: 24) {
                    Stepper(value: $model.duoprism.p, in: DuoprismParameters.range) {
                        Text("p = \(model.duoprism.p)")
                    }
                    Stepper(value: $model.duoprism.q, in: DuoprismParameters.range) {
                        Text("q = \(model.duoprism.q)")
                    }
                }
            }
        }
    }
}

/// Projection: three presets plus the κ and s sliders (DESIGN 3.3).
struct ProjectionSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(ProjectionPreset.allCases, id: \.self) { preset in
                    SelectButton(title: preset.label,
                                 isSelected: ProjectionPreset.matching(model.projection) == preset) {
                        withAnimation(.easeInOut(duration: 0.6)) { model.projection = preset.settings }
                    }
                }
            }
            LabeledSlider(title: "Perspective κ", value: $model.projection.kappa, range: 0...1)
            LabeledSlider(title: "Spherize s", value: $model.projection.spherize, range: 0...1)
        }
    }
}

/// Display: four presets plus the layer controls (DESIGN 3.4).
struct DisplaySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let kind = model.object.kind
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(DisplayPreset.allCases, id: \.self) { preset in
                    SelectButton(title: preset.label, isSelected: preset.matches(model.display)) {
                        preset.apply(to: &model.display)
                    }
                    .disabled(preset == .cells && kind != .polytope)
                }
            }
            HStack(spacing: 16) {
                Toggle("Edges", isOn: $model.display.edgesVisible).fixedSize()
                Picker("Edge colour", selection: $model.display.edgeColor) {
                    ForEach(EdgeColorMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .fixedSize()
                Toggle("Floor shadow", isOn: $model.display.floorShadow).fixedSize()
            }
            LabeledSlider(title: "Edge thickness", value: $model.display.edgeThickness,
                          range: DisplaySettings.thicknessRange, format: "%.3f")
            LabeledSlider(title: "Face opacity", value: $model.display.faceOpacity, range: 0...1,
                          format: "%.0f %%", displayScale: 100)
            HStack(spacing: 16) {
                Picker("Colour", selection: $model.display.colorSource) {
                    ForEach(ColorSource.allCases.filter { $0.isAvailable(for: kind) }, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .fixedSize()
                Picker("Style", selection: $model.display.faceStyle) {
                    ForEach(FaceStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            LabeledSlider(title: "Explode", value: $model.display.explode,
                          range: DisplaySettings.explodeRange, format: "%.0f %%", displayScale: 100)
                .disabled(kind != .polytope)
        }
    }
}

/// Motion: presets, friction, Stop, Reset and one speed slider per plane (DESIGN 3.2).
struct MotionSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(MotionPreset.allCases, id: \.self) { preset in
                    SelectButton(title: preset.label,
                                 isSelected: MotionPreset.matching(model.motion.omega) == preset) {
                        model.motion.omega = preset.omega
                    }
                }
                Spacer()
                Button("Stop", systemImage: "stop.fill") { model.stop() }
                Button("Reset", systemImage: "arrow.counterclockwise") { model.resetOrientation() }
            }
            LabeledSlider(title: "Friction", value: $model.motion.friction,
                          range: MotionSettings.frictionRange)
            ForEach(RotationPlane.allCases, id: \.self) { plane in
                LabeledSlider(title: plane.label, value: $model.motion.omega[plane],
                              range: MotionSettings.speedRange, format: "%.2f rad/s")
            }
        }
    }
}

/// Developer section: spikes S1–S3, freezing time and the experimental room.
struct DeveloperSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Transparency (S1)").frame(width: 190, alignment: .leading)
                Picker("Transparency (S1)", selection: $model.developer.transparency) {
                    ForEach(TransparencyMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 12) {
                Text("Floor shadow (S4)").frame(width: 190, alignment: .leading)
                Picker("Floor shadow (S4)", selection: $model.developer.floorShadowMethod) {
                    ForEach(FloorShadowMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 24) {
                LabeledSlider(title: "Drag k (rad/m)", value: $model.gestureMapping.radiansPerMetre,
                              range: 5...60, format: "%.1f")
                Toggle("Invert drag", isOn: Binding(
                    get: { model.gestureMapping.sign < 0 },
                    set: { model.gestureMapping.sign = $0 ? -1 : 1 }))
                    .fixedSize()
            }
            HStack(spacing: 24) {
                Toggle("Performance overlay (S2)", isOn: $model.developer.showsPerformanceOverlay)
                    .fixedSize()
                Toggle("Gesture test (S3)", isOn: $model.developer.showsGestureTest).fixedSize()
            }
            HStack(spacing: 24) {
                Toggle("Freeze time", isOn: $model.developer.freezesTime).fixedSize()
                Toggle("Fine subdivision (S2 stress)", isOn: $model.developer.forcesFineSubdivision).fixedSize()
            }
            LabeledSlider(title: "Scale", value: $model.scale, range: ViewState.scaleRange)
            Button(model.isRoomOpen ? "Close room" : "Open in room (experimental)",
                   systemImage: "cube.transparent") {
                Task {
                    if model.isRoomOpen {
                        await dismissImmersiveSpace()
                        model.isRoomOpen = false
                    } else if case .opened = await openImmersiveSpace(id: RoomView.spaceID) {
                        model.isRoomOpen = true
                    }
                }
            }
            if !model.launchProblems.isEmpty {
                Text("Ignored launch arguments: \(model.launchProblems.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A button that shows whether its option is selected.
struct SelectButton: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : nil)
    }
}

/// A slider with a title and the current value.
struct LabeledSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"
    var displayScale: Double = 1

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 150, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value * displayScale))
                .monospacedDigit()
                .frame(width: 110, alignment: .trailing)
        }
    }
}
