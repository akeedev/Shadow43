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
                        .helpTarget(.object(id))
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
                .helpTarget(.duoprismParameters)
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
                    .helpTarget(.projectionPreset(preset))
                }
            }
            LabeledSlider(title: "Perspective κ", value: $model.projection.kappa, range: 0...1)
                .helpTarget(.kappa)
            LabeledSlider(title: "Spherize s", value: $model.projection.spherize, range: 0...1)
                .helpTarget(.spherize)
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
                    .helpTarget(.displayPreset(preset))
                }
            }
            HStack(spacing: 16) {
                HStack(spacing: 16) {
                    Toggle("Edges", isOn: $model.display.edgesVisible).fixedSize()
                    Picker("Edge colour", selection: $model.display.edgeColor) {
                        ForEach(EdgeColorMode.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .fixedSize()
                }
                .helpTarget(.edges)
                Toggle("Floor shadow", isOn: $model.display.floorShadow).fixedSize()
                    .helpTarget(.floorShadow)
                Toggle("Axes", isOn: $model.display.axesVisible).fixedSize()
                    .helpTarget(.axes)
            }
            LabeledSlider(title: "Edge thickness", value: $model.display.edgeThickness,
                          range: DisplaySettings.thicknessRange, format: "%.3f")
                .helpTarget(.edgeThickness)
            LabeledSlider(title: "Face opacity", value: $model.display.faceOpacity, range: 0...1,
                          format: "%.0f %%", displayScale: 100)
                .helpTarget(.faceOpacity)
            HStack(spacing: 16) {
                Picker("Colour", selection: $model.display.colorSource) {
                    ForEach(ColorSource.allCases.filter { $0.isAvailable(for: kind) }, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .fixedSize()
                .helpTarget(.colorSource)
                // Material, pattern and thickness are on the Surface tab (D24).
            }
            LabeledSlider(title: "Explode", value: $model.display.explode,
                          range: DisplaySettings.explodeRange, format: "%.0f %%", displayScale: 100)
                .disabled(kind != .polytope)
                .helpTarget(.explode)
            // Factor on top of the automatic size (D15); also the two-hand pinch.
            LabeledSlider(title: "Size", value: $model.scale, range: ViewState.scaleRange, format: "× %.2f")
                .helpTarget(.size)
            RoomButton()
        }
    }
}

/// Opens or closes the room (D30; on the Display tab since D37). Why the room did not open is
/// shown below the button and logged.
struct RoomButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var problem: LocalizedStringKey?

    var body: some View {
        HStack(spacing: 16) {
            Button(model.isRoomOpen ? "Close room" : "Open in room", systemImage: "cube.transparent") {
                Task { await toggle() }
            }
            .tint(model.isRoomOpen ? .accentColor : nil)
            .helpTarget(.room)
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func toggle() async {
        if model.isRoomOpen {
            await dismissImmersiveSpace()
            model.isRoomOpen = false
            return
        }
        let result = await openImmersiveSpace(id: RoomView.spaceID)
        ShadowRenderer.logger.notice("Open in room: \(String(describing: result), privacy: .public)")
        switch result {
        case .opened:
            model.isRoomOpen = true
            problem = nil
        case .userCancelled:
            problem = "The room was not opened: cancelled."
        case .error:
            problem = "The room could not be opened (visionOS reported an error)."
        @unknown default:
            problem = "The room could not be opened."
        }
    }
}

/// Surface: how the faces look – material, image pattern, thickness (D24, experimental).
struct SurfaceSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let hasFaces = model.object.kind != .curves
        VStack(alignment: .leading, spacing: 12) {
            OptionRow(title: "Material", titleWidth: 110, options: FaceStyle.allCases,
                      selection: Binding(get: { model.display.faceStyle },
                                         set: { model.display.faceStyle = $0; model.showFaces() })) { $0.label }
                .helpTarget(.faceStyle)
            OptionRow(title: "Pattern", titleWidth: 110, options: SurfacePattern.allCases,
                      selection: Binding(get: { model.display.pattern },
                                         set: { model.display.pattern = $0; if $0 != .none { model.showFaces() } })) { $0.label }
                .helpTarget(.pattern)
            LabeledSlider(title: "Thickness", value: Binding(
                get: { model.display.faceThickness },
                set: { model.display.faceThickness = $0; if $0 > 0 { model.showFaces() } }),
                          range: DisplaySettings.faceThicknessRange, format: "%.3f")
                .helpTarget(.faceThickness)
            Text(hasFaces ? LocalizedStringKey("A pattern replaces the colour on the faces; the edges keep it.")
                          : LocalizedStringKey("Curves have no faces."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .disabled(!hasFaces && !model.isHelpMode)
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
                    .helpTarget(.motionPreset(preset))
                }
                Spacer()
                Button("Stop", systemImage: "stop.fill") { model.stop() }
                    .helpTarget(.stop)
                Button("Reset", systemImage: "arrow.counterclockwise") { model.resetOrientation() }
                    .helpTarget(.reset)
            }
            LabeledSlider(title: "Friction", value: $model.motion.friction,
                          range: MotionSettings.frictionRange)
                .helpTarget(.friction)
            ForEach(RotationPlane.allCases, id: \.self) { plane in
                LabeledSlider(title: plane.label, value: $model.motion.omega[plane],
                              range: MotionSettings.speedRange, format: "%.2f rad/s")
                    .helpTarget(.planeSpeed)
            }
        }
    }
}

/// Developer section: spikes S1–S4, the drag mapping and freezing time.
struct DeveloperSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            OptionRow(title: "Transparency (S1)", titleWidth: 190, options: TransparencyMethod.allCases,
                      selection: $model.developer.transparency) { $0.label }
                .helpTarget(.transparency)
            OptionRow(title: "Floor shadow (S4)", titleWidth: 190, options: FloorShadowMethod.allCases,
                      selection: $model.developer.floorShadowMethod) { $0.label }
                .helpTarget(.floorShadowMethod)
            HStack(spacing: 24) {
                LabeledSlider(title: "Drag k (rad/m)", value: $model.gestureMapping.radiansPerMetre,
                              range: GestureMapping.radiansPerMetreRange, format: "%.1f")
                Toggle("Invert drag", isOn: Binding(
                    get: { model.gestureMapping.sign < 0 },
                    set: { model.gestureMapping.sign = $0 ? -1 : 1 }))
                    .fixedSize()
            }
            .helpTarget(.dragMapping)
            HStack(spacing: 24) {
                Toggle("Performance overlay (S2)", isOn: $model.developer.showsPerformanceOverlay)
                    .fixedSize()
                    .helpTarget(.performanceOverlay)
                Toggle("Gesture test (S3)", isOn: $model.developer.showsGestureTest).fixedSize()
                    .helpTarget(.gestureTest)
            }
            HStack(spacing: 24) {
                Toggle("Freeze time", isOn: $model.developer.freezesTime).fixedSize()
                    .helpTarget(.freezeTime)
                Toggle("Fine subdivision (S2 stress)", isOn: $model.developer.forcesFineSubdivision).fixedSize()
                    .helpTarget(.fineSubdivision)
            }
            HStack(spacing: 4) {
                // Sort direction of the "sorted" method (D17).
                Text("Viewer side:")
                Text(model.viewSide.label)
                if model.viewSideOverride != nil { Text("(launch argument)") }
            }
            .foregroundStyle(.secondary)
            .helpTarget(.viewerSide)
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

/// A title and one `SelectButton` per option; replaces segmented pickers, which did not react to
/// taps in the ornament on the device (DESIGN §8).
struct OptionRow<Option: Hashable>: View {
    let title: LocalizedStringKey
    var titleWidth: CGFloat?
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            Text(title).frame(width: titleWidth, alignment: .leading)
            ForEach(options, id: \.self) { option in
                SelectButton(title: label(option), isSelected: selection == option) {
                    selection = option
                }
            }
        }
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
