# Night report 2026-11-08

## Summary
All seven milestones M0–M6 got done in the simulator. The app shows every object from DESIGN 3.1
(5-, 8-, 16-, 24-, 120-, 600-cell, duoprisms p×q, Klein bottle, Clifford torus, Hopf fibration).
It has the continuous κ/s projection, display layers and presets, five colour sources, explode,
a floor shadow, all three S1 transparency methods, variant-A gestures, an S3 gesture test scene,
an S2 performance overlay and the experimental room. Core4D has 65 green Swift Testing tests,
including every f-vector from DESIGN 6.8. The most important open points need the device:
1. Faces cast a floor shadow only in some simulator runs (edges always do), so S4 is partial.
2. No gesture could be tried, because the simulator cannot be driven from the command line.
3. Uploading very large meshes (≥ 250k triangles) costs 6–13 ms per frame in the simulator.

A crash of your Windows server interrupted the session once early in M0, before any file had been
written. Nothing needed cleaning up, and the run continued from scratch.

## Milestones
| Milestone | Status (done/partial/blocked/not started) | Notes |
|---|---|---|
| M0 | done | `project.yml`, `Config/Shared.xcconfig`, Core4D package, volumetric window + `ImmersiveSpace` (shared `AppModel`, `SceneHost`), String Catalog, snapshot mode (launch arguments → `ViewState`, `-time` freezes time) |
| M1 | done | `Complex4D`, generic polytope generator (6.6), rotation (G, step, Gram–Schmidt, friction), projection (κ, s), tessellation → `RenderMesh4D`, per-frame `FrameBuilder`; all 6.8 tests for these objects green |
| M2 | done | `LowLevelMesh` for faces and tubes, RealityKit `System`, motion and projection presets, control panel (5 tabs), S2 overlay; screenshots of the 3 projections and the 4 small polytopes |
| M3 | done; S4 partial | layers, 4 display presets, colour sources (uniform, by W, per cell + surface, per fibre), explode, floor shadow; S1: additive, sorted and per-cell entities switchable; S4: edge shadows clear, face shadows unreliable in the simulator |
| M4 | done (device check pending) | variant A: drag → 4D, two-hand twist → 3D, magnify → scale, release → throw, pinch-hold → catch, double tap → reset; mapping (k, sign, throw, velocity window) tested in Core4D; S3 panel with raw values + `ManipulationComponent` probe (variant C); k and sign adjustable in the Developer section |
| M5 | done | 600- and 120-cell via the bootstrap, duoprisms p×q (p, q 3…24), subdivision only when s > 0 and by size, profiling (S2 numbers below); Core4D compiled with `-O` in Debug too |
| M6 | done | Klein bottle, Clifford torus (checkerboard by surface parameter), Hopf fibration (3 × 16 fibres, colour per fibre); tests for S³, disjointness, great circles, Hopf map and seam condition green |

## Screenshots
All in `build/screenshots/` (git-ignored). Assessment in brackets.
- `M0-placeholder.png` – placeholder cube in the volume, panel below. [OK]
- `M2-tesseract-perspective.png` – perspective, Glass (additive), colour by W; default scale, small. [OK]
- `M2-tesseract-orthographic.png` – XW-rotated tesseract as overlapping cubes; edge shadow on the disc. [OK]
- `M2-tesseract-stereographic.png` – circular arcs, blue inner and red outer shells; clipped by the volume at scale 1.3. [OK, clipping expected]
- `M2-5cell.png`, `M2-16cell.png`, `M2-24cell.png` – the other small polytopes in perspective, Glass. [OK]
- `M2-24cell-solid-animated.png` – Drift motion running; overlay 120 Hz, 1.5 ms CPU (unoptimised Core4D at that time). [OK]
- `M3-display-wireframe.png` – Wireframe with thick edges; clear edge shadow on the floor disc. [OK]
- `M3-display-cells.png` – Cells preset (explode 20 %, palette per cell). [OK; the large front cell dominates in perspective]
- `M3-floor-shadow-light.png` – Solid 24-cell, directional light: no face shadow visible. [S4 problem]
- `M3-floor-shadow-grounding.png` – same with `GroundingShadowComponent`: disc darker overall, no shape. [S4 problem]
- `M3-transparency-sorted.png` – Glass, matte, sorted alpha: clean glass, no sorting errors visible. [OK]
- `M3-transparency-cells.png` – per-cell entities, explode 20 %, palette: translucent cells layered correctly. [OK]
- `M3-color-uniform-glossy.png` – uniform colour, glossy 16-cell, shadow visible. [OK]
- `M4-gesture-test.png` – Developer tab, S3 panel with raw values (all "–"), yellow manipulation probe. [OK]
- `M5-120cell-stereographic-debug.png` / `M5-120cell-stereographic.png` – the soap-bubble 120-cell; Debug before the `-O` fix 34.7 ms CPU (28 Hz), Release 0.8 ms (109 Hz). [OK, picture correct]
- `M5-600cell-stereographic.png` – 600-cell, Debug app with optimised Core4D: 1.4 ms, 106 Hz. [OK]
- `M5-S2-stress-120cell-cells-fine.png` – S2 stress: 503k triangles, 13.4 ms CPU (build 2.3 ms), 65 Hz. [OK as a measurement]
- `M5-duoprism-6x12-stereographic.png` – opaque Solid; the outer inside-out cell hides the rest. [OK but not informative]
- `M5-duoprism-6x12-glass.png` – ring of 12 hexagonal prisms, palette per cell. [OK]
- `M6-klein-bottle.png` – checkerboard; the pattern flips at the seam (non-orientability visible). [OK]
- `M6-clifford-torus.png` – stereographic, torus with a regular checkerboard; slightly clipped. [OK]
- `M6-hopf-fibration.png` – nested tori of linked circles, colour per fibre; circles through the pole are cut by the volume. [OK]
- `M6-room-experimental.png` – "Open in room": the same 24-cell at room scale (z = −2.8 m), behind the window and synchronised with it. A first placement at z = −1.6 m covered the window and was moved back. [OK, experimental]

## Device checklist for the morning
First create `Config/Signing.local.xcconfig` (see README), run `xcodegen generate`, open the
project and run the Shadow43 scheme on the Vision Pro. Turn on Developer → Performance overlay.
1. **Start-up:** a volume with a rotating Glass tesseract (perspective, colour by W) and the panel
   below. Expected: smooth rotation, panel readable, nothing clipped at default scale.
2. **Performance (S2, 90 Hz):** Object → 120-cell, Projection → Stereographic. Expected: overlay
   ≈ 11 ms per frame (90 Hz), CPU under 3 ms. Then Developer → "Fine subdivision (S2 stress)" plus
   Display → Cells (about 500k triangles). Note the CPU and build times; this answers S2.
3. **Transparency (S1):** Display → Glass on the tesseract and on the 24-cell, then switch
   Developer → Transparency between Additive, Sorted and Per-cell entities (per-cell needs
   explode > 0, e.g. Display → Explode 20 %). Walk around the volume. Expected: no flicker and no
   popping of faces. Note which method looks best; the design favours Additive for Glass.
4. **Floor shadow (S4):** Display → Solid on the 24-cell, Floor shadow on. Expected: a shadow of
   the faces (not only the edges) on the disc below. If it is missing, switch Developer → Floor
   shadow to "Grounding shadow" and compare.
5. **Drag (variant A):** pinch the object and drag right/left, up/down, forward/back. Expected:
   the shadow deforms (XW, YW, ZW); the motion stops the moment you pinch (catch).
6. **Throw:** drag quickly and release. Expected: the rotation continues in the drag direction;
   with Motion → Friction above 0 it slows down.
7. **Two hands:** pinch with both hands and twist, then move the hands apart/together. Expected:
   rigid 3D rotation, then scaling. The twist direction is mapped from SwiftUI's y-down space
   [verify]: if the object turns the wrong way, the mapping in `ShadowGestures.realityKitQuaternion`
   needs a sign change.
8. **Double tap:** Expected: orientation resets to the start position.
9. **Feel:** rate the drag sensitivity and direction. Developer → "Drag k" (default 2π per 0.3 m
   ≈ 20.9 rad/m) and "Invert drag" change it live; tell me the values you like.
10. **Gesture test (S3):** Developer → Gesture test. Do each gesture and watch the raw values in
    the panel at the right. Grab the yellow probe sphere at the front right corner and move or
    turn it (variant C). Expected: "Manipulation (C)" shows translation and rotation; it springs
    back on release.
11. **Surfaces and curves:** Klein bottle and Clifford torus with Display → Colour → Surface
    parameter; Hopf fibration with Per fibre, Stereographic. Expected: smooth surfaces, readable
    checkerboard, linked circles.
12. **Room (experimental):** Developer → "Open in room". Expected: the same object at about 2 m,
    in front of you behind the window, mirroring every control change; "Close room" ends it.

## Questions for the user
1. **Debug performance (D11):** Core4D is now always compiled with `-O` via `unsafeFlags` in
   `Package.swift`. Otherwise the default Debug run reaches only about 28 Hz for the 120-cell.
   Alternative: drop the flag and set the scheme's Run action to Release. Which do you prefer?
2. **Floor shadow (S4):** I kept the directional light as default; the grounding shadow is a
   switch in the Developer section. Decide after device check 4.
3. **Leaving the Cells preset (D13):** it resets explode to 0 and the colour to "by W". If you
   want purely partial presets, change `DisplayPreset.apply`.
4. **Default scale:** 0.2 m per object unit in a 0.8 m volume. The stereographic 120-cell, the
   600-cell and the Hopf fibres are clipped by the volume at this scale. Should the default scale
   depend on the projection, or stay a user control only (as now)?
5. **String Catalog:** `Localizable.xcstrings` exists and all UI text is `LocalizedStringKey`, but
   `xcodebuild` did not fill the catalog. Xcode does that on the first IDE build; please check the
   catalog then.

## Deviations from DESIGN.md
- **Double-sided faces:** faces are emitted in both windings with back-face culling instead of
  `faceCulling = .none` (D12). They look the same.
- **Per-cell entities (S1):** each cell gets its own `ModelSortGroup` (back faces order 0, front
  faces order 1), and its entities are placed at the cell centroid so that RealityKit's distance
  sort works. Outward winding is recomputed every frame, because projection can turn cells inside
  out.
- **`ViewState`:** besides the fields in 6.2, it also holds `duoprism` (p, q) and `developer`
  (transparency method, floor-shadow method, overlay, gesture test, freeze time, fine
  subdivision), so that every visual state can be set by launch arguments.
- **Colour key:** `RenderMesh4D.colorKey` is `SIMD2<Float>` instead of `Float`, because the surface
  checkerboard needs (u, v).
- **Gesture tuning:** k and the sign are adjustable in the Developer section (not in DESIGN).
  This lets you tune the feel on the device.
- **Floor-shadow method:** the S4 fallback (grounding shadow) is a Developer switch rather than a
  code change.

## Changes after v0.9 (day session, 2026-11-08)
Decided with the user after the night run (DESIGN D11 extended, D15–D18):
- **D11:** the app target is now also compiled with `-O` in Debug, so a normal Run shows the real
  speed.
- **D15, automatic size:** each object fills 75 % of the volume (80 % touched the floor disc), measured by the 90th-percentile
  vertex radius over 32 orientations. *Size* moved from Developer to Display and is a factor on
  top. Edge thickness is relative to the fitted radius.
- **D16, flipped faces:** each face triangle has a front copy and a back copy with its own normals,
  so lit styles are correct from every side.
- **D17, viewer side:** the window sorts towards the side of the volume the viewer is on
  (`onVolumeViewpointChange`). The Developer section shows the side; `-viewpoint` fixes it.
  ARKit head pose in the room comes later.
- **D18, start orientation:** a 3D tilt, so the tesseract starts as a cube inside a cube.

New screenshots (`M7-…`): `tesseract-start` (cube inside a cube, automatic size) [OK],
`24cell-solid-lit` [OK], `120cell-stereographic-fit` [OK, outer cells cut as intended],
`klein-bottle-glossy` [OK], `tesseract-per-cell-entities` [OK], `sorted-viewpoint-back` [renders;
panel line with the side is off-screen in the simulator], `S2-stress-optimised-app` [18–23 ms,
simulator noise, see DESIGN §8].

Changes to the device checklist:
- **Step 1:** expect the tilted cube inside a cube, filling most of the volume.
- **Step 3:** with *Sorted*, walk to each side and check Developer → "Viewer side". If it says
  Left when you stand on the right, `ViewSide.direction` needs left and right swapped. Between the
  four sides small sorting errors are expected.
- **Step 4 (new part):** with *Solid* and *Glossy*, walk around the volume. Faces should be lit
  correctly from behind too, not dark.
- **Size:** Display → Size (×0.25–4) replaces Developer → Scale.

## Files
New, unless marked as changed.
- **Root:** `project.yml`, `NIGHT_REPORT.md`; changed: `DESIGN.md` (§7 D11–D14, §8 findings),
  `README.md` (snapshot mode)
- **Config/:** `Shared.xcconfig`
- **Packages/Core4D/:** `Package.swift`
- **Packages/Core4D/Sources/Core4D/:** `Complex4D.swift`, `PolytopeGenerator.swift`,
  `Polytopes.swift`, `Surfaces.swift`, `Rotation4D.swift`, `Projection4D.swift`,
  `Tessellation.swift`, `FrameBuilder.swift`, `GestureMapping.swift`, `ViewState.swift`,
  `Presets.swift`, `LaunchOptions.swift`
- **Packages/Core4D/Tests/Core4DTests/:** `PolytopeTests.swift`, `RotationProjectionTests.swift`,
  `TessellationTests.swift`, `SurfaceTests.swift`, `GestureTests.swift`,
  `LaunchOptionsTests.swift`, `TestHelpers.swift`
- **Shadow43/App/:** `Shadow43App.swift`, `AppModel.swift`, `SceneHost.swift`, `VolumeView.swift`,
  `RoomView.swift`
- **Shadow43/UI/:** `ControlPanel.swift`, `PanelSections.swift`, `Labels.swift`
- **Shadow43/Rendering/:** `ShadowRealityView.swift`, `ShadowSystem.swift`, `ShadowRenderer.swift`,
  `DynamicMesh.swift`, `Materials.swift`, `ColorTextures.swift`, `CellEntities.swift`,
  `FloorShadow.swift`
- **Shadow43/Input/:** `ShadowGestures.swift`
- **Shadow43/Debug/:** `SnapshotMode.swift`, `PerformanceOverlay.swift`, `GestureTest.swift`
- **Shadow43/Resources/:** `Localizable.xcstrings`
- **Shadow43/:** `Info.plist` (generated by XcodeGen from `project.yml`)
- **Not tracked:** `Shadow43.xcodeproj` (generated), `build/` (DerivedData, screenshots),
  `Packages/Core4D/.build`
