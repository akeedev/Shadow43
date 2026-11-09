# Shadow43: 4D shadows for Apple Vision Pro

**Design version 0.4 · 2026-11-09 · describes app version 0.10.0**

**Shadow43 shows the three-dimensional shadows of four-dimensional objects in your room and lets
you turn the objects in four dimensions with your hands.** You pick an object, such as the
tesseract, and watch its shadow deform, turn inside out and pass through itself as the object
turns. The shadow is stereoscopic, so you can walk around it. §1 explains the idea without
mathematics.

The design rests on five ideas:

1. **One data model for every object.** Polytopes, surfaces and curves all become a *complex* of
   points, edges, faces and cells in ℝ⁴, so everything downstream treats them alike (§3).
2. **One pipeline of independent stages.** Each stage has a few orthogonal controls; "modes" such
   as *wireframe* or *stereographic* are only named presets of them [D9, D10].

   ```
   Object ──► Prepare ──► Spherize ──► Rotate ──► Project ──► Display
   §3         explode,    s (§5)       R, Ω (§4)  κ (§5)      layers (§6),
              subdivide                                       volume or room (§7)
   ```

3. **One state, one source of motion.** A single `ViewState` describes everything shown; presets,
   launch arguments, saved settings and *Reset all* only assign parts of it. All motion is one
   angular velocity Ω: presets and throws set it, a grab stops it (§4, §9.2).
4. **Pure maths, thin rendering, two places.** A tested Swift package, Core4D, does the maths. The
   app rebuilds the mesh on the CPU whenever something changed and hands it to RealityKit. The
   same content runs in a volumetric window and, at room size, in an immersive space (§7, §9).
5. **Nothing hidden.** Every gesture has a control in the panel, every visual state can be set by
   launch arguments, and a help mode explains every control (§8, §12.5).

**Status.** Milestones M0–M6 are done; the app runs in the simulator and on the Vision Pro. What
is still to check, to fix or to try is in §14.

**How to read this document.** Part A (§1–8) says what the app does, for everyone. Part B (§9–12)
says how it is built, in enough detail to rebuild it. Part C (§13–16) holds the lessons from
testing, the open points, the decision log and a glossary. **[Dn]** points to decision n in §15,
which gives its reason. **[verify]** marks an assumption not yet checked on the device or against
the SDK.

---

# Part A: What the app does

## 1. The idea in plain words

**We cannot see a fourth dimension, but we can see its shadow, just as a flat creature could see
the shadow of a cube.**

In Edwin A. Abbott's novella *Flatland: A Romance of Many Dimensions* (1884), A. Square lives in a
plane. He knows length and breadth, but not height. One day a sphere visits him. All he can see is
a circle that appears from nowhere, grows, shrinks and vanishes: the slices of the sphere as it
passes through his world. Only when the sphere lifts him out of the plane does he understand. Then
he asks about a fourth dimension, and the sphere, who has just explained the third, refuses to
believe it.

We stand where A. Square stood. We cannot picture a fourth direction at right angles to the other
three, but we can reason one dimension down:

- **Building up.** Move a point and you get a line with 2 ends. Move the line sideways: a square
  with 4 corners. Move the square upwards: a cube with 8 corners. Move the cube in a fourth
  direction: a *tesseract*, with 16 corners. A cube is bounded by 6 squares; a tesseract by 8 cubes.
- **Shadows.** Hold a wire cube in the sun. Its shadow on the table is flat, yet you can tell it
  comes from a cube. Turn the cube, and the shadow changes from a square to a hexagon; its lines
  slide through each other, although the cube itself is rigid. Under a lamp close above, the shadow
  becomes a square inside a square, because the near face throws a larger shadow than the far
  one. A Flatlander living in the table top would see only these shadows.

**Shadow43 does this one dimension up.** It shows the 3D shadow of a 4D object: an ordinary 3D
object that you can walk around. Under the "lamp", the tesseract's shadow is a cube inside a cube.
When the tesseract turns in 4D, the shadow deforms and turns inside out: the inner cube grows into
the outer one while the outer one shrinks into the middle. Nothing is wrong with the shadow; a
rigid object is turning in a direction we have no word for. Colour helps where the eye cannot: by
default, parts nearer to the 4D lamp are red, parts farther away blue.

The floor takes the last step down. A light from above throws the shadow of the shadow onto a disc
below the object, which is what a Flatlander would see. So the whole chain 4D → 3D → 2D is in view
at once.

Flatland's sphere shows itself in slices. Shadow43 shows shadows instead, because a shadow shows
the whole object at once; slices are a later idea (§14.4).

## 2. Goal and principles

**Goal: let anyone hold a 4D object, turn it freely and understand what they see.** You choose the
object and how it is projected and drawn, turn it in any of the six 4D rotation planes by hand or
automatically, and look at it from every side. No native spatial app did this when the project
started in November 2026: *4D Toys* shows 3D slices of fixed scenes, the *4D Polytope Viewer* runs
in a browser, and *Four Dimensional Space* shows a single tesseract.

Principles, which every change has to keep:
- **Few independent controls instead of modes.** Every aspect of the picture is its own parameter;
  a mode is a named preset of parameters.
- **Every gesture has a control** in the panel, for the simulator, for precision and for
  accessibility.
- **Every visual state can be set by launch arguments** (snapshot mode, §12.5), so it can be
  checked without clicking.
- **The app explains itself:** a help mode explains every control and object; the About page
  explains the gestures.
- **One source of truth:** `ViewState`. The 3D scene entity is never rotated; all rotation lives in
  R.
- **Native and self-contained:** Swift, SwiftUI and RealityKit, no third-party code, English, open
  source under Apache 2.0.

## 3. Objects

**Every object becomes one data model, a complex in ℝ⁴, centred and scaled to radius 1, so that
rotation, projection and display work the same for all of them.** A complex has vertices (points in
ℝ⁴), edges (polylines), faces (polygons) and cells (closed groups of faces, polytopes only).
Controls that make no sense for an object are disabled or hidden, such as explode for the Klein
bottle.

| Kind | Objects | Made from |
|---|---|---|
| Convex polytopes | 5-cell, tesseract (8-cell), 16-cell, 24-cell, 120-cell, 600-cell, duoprism p×q (p, q = 3…24, default 3×4) | vertices and facet normals; edges, faces and cells are derived (§10.5) |
| Surfaces | Klein bottle, Clifford torus | a parametric surface f(u, v) as a triangle grid (§10.6) |
| Curves | Hopf fibration | 48 great circles of S³ as closed polylines (§10.6) |

The tesseract is also the 4×4 duoprism, turned by 45°, and the duocylinder is the duoprism's limit
for large p and q.

## 4. Motion

**The object has an orientation R, a 4×4 rotation, and an angular velocity Ω, six numbers, one per
rotation plane. Everything that moves the object changes one of the two.**

- **Six rotation planes.** XY, XZ and YZ are the familiar 3D rotations; they only turn the shadow
  rigidly. XW, YW and ZW are the genuinely four-dimensional ones; they deform it.
- **One source of motion.** A motion preset sets Ω, a throw sets Ω, a grab stops it ("catching",
  Ω = 0), *Stop* sets Ω = 0, and friction damps Ω (default 0: the object turns for ever). Dragging
  turns R directly.
- **Presets** (Ω in rad/s): *Simple* XW 0.6 · *Double* XY 0.25 and ZW 0.7 · *Isoclinic* XY and ZW
  0.5 each, the Clifford rotation, which has no 3D counterpart · *Drift* all six planes slowly: XY
  0.07, XZ 0.11, YZ 0.05, XW 0.17, YW 0.13, ZW 0.19. One slider per plane sets its speed, ±2 rad/s.
- **Start orientation:** a pure 3D tilt, 35° in XZ, then 25° in YZ, so the tesseract starts as the
  classic cube inside a cube, seen at an angle [D18]. *Reset* (Motion tab) and a double tap on the
  object return to it.
- **Rotations act in the viewer's frame,** not in the object's: R is always multiplied from the
  left. The 3D scene entity is never rotated. That keeps a single source of truth, and it is
  correct because 3D rotations commute with the projection along W.

## 5. Projection

**Orthographic, perspective and stereographic projection are not three methods but three points in
a plane of two controls, κ and s [D9].** You can morph between them continuously.

- **Perspective strength κ** (kappa, the reciprocal of the 4D eye's distance along W):
  `p = (x, y, z) / (1 − κ·w)`. κ = 0 simply drops W (orthographic: the sun of §1); κ ≈ 0.6 gives
  the classic cube inside a cube (the lamp). Points with w = 0 stay in place for every κ, so the
  picture does not jump.
- **Spherize s** blends each point between its flat position and its position on the 3-sphere:
  s = 0 is the flat polytope, s = 1 the inflated one.
- **Stereographic projection is simply κ = 1, s = 1.** Edges become circular arcs, and the 120-cell
  becomes the familiar soap-bubble picture.
- **Presets:** *Orthographic* (κ 0, s 0), *Perspective* (0.6, 0), *Stereographic* (1, 1). A preset
  is highlighted while the values match it exactly.
- Parts at or behind the 4D eye, and parts flung very far out, are dropped (§10.3).

A slice through a hyperplane, as in *4D Toys* and in Flatland, is not a projection: it creates new
geometry. It is a later idea (§14.4).

## 6. Display

**What you see is a stack of independent layers; the display presets only set some of them [D10].**

### 6.1 Layers

| Layer | Controls |
|---|---|
| Edges | visible; thickness; colour: same as the faces, or plain light |
| Faces | opacity 0–100 %; colour source; material; image pattern; thickness (§6.3) |
| Cells (polytopes) | explode 0–40 %: every cell shrinks towards its centre and becomes a body of its own |
| Axes | visible: the four 4D axes, rotated and projected with the object (§6.4) |
| Floor shadow | visible: the shadow of the shadow on a disc below the object (§6.4) |
| Size | a factor 0.25–4 on top of the automatic size (§6.5) |

Transparent volumes need no mechanism of their own. A cell is drawn by its boundary faces; with
explode above 0, every cell is a glass body of its own, and its transparency is the face opacity.

### 6.2 Presets

| Preset | Sets |
|---|---|
| *Wireframe* | edges on, thickness 0.012, faces 0 % |
| *Glass* (default) | edges on, thickness 0.012, faces 25 %, glowing |
| *Solid* | edges on, thickness 0.005, faces 100 %, matte if glowing |
| *Cells* (polytopes) | edges on, thickness 0.005, faces 100 %, explode 20 %, colour per cell, matte if glowing |

Leaving *Cells* for another preset also sets explode back to 0 and the colour to *by W*, so the
other presets do not look exploded [D13]. A preset is highlighted while the settings match it.

### 6.3 Faces: colour, material, pattern, thickness

- **Colour source**, one for the whole object; the menu offers only those that fit it:
  - *Uniform:* light blue.
  - *By W* (default): blue at w = −1 to red at w = +1. It shows what lies "in front" in 4D and is
    the most helpful single aid to understanding.
  - *Per cell* (polytopes): 12 colours, repeating. Every face belongs to two cells, so this source
    forces an explode of at least 5 %; then every cell has faces of its own [D10].
  - *Surface parameter* (surfaces): a 12 × 6 checkerboard in (u, v). It shows the Klein bottle's
    seam flip.
  - *Per fibre* (Hopf fibration): one hue per circle.
- **Material:** matte, glossy, glowing (unlit; the default), metal, ceramic or frosted glass [D24].
  Edges use the same material.
- **Image pattern:** none, grid, marble or wood. Patterns are drawn in code and fixed in 4D on each
  face, so they show the projection's distortion. A pattern *replaces* the colour source on the
  faces; the edges keep it [D24].
- **Thickness:** faces become slabs, up to 3 cm in the volume. Their rims stay open; edges at least
  half as thick cover them.
- Choosing a material, a pattern or a thickness makes hidden faces visible: an opacity below 5 %
  becomes 100 %; frosted glass gets 50 % instead, also when its opacity is above 90 %.

### 6.4 Axes and floor shadow

- **Axes** [D20]: the object's four axes, from −eᵢ to +eᵢ, rotated and projected like its points:
  x red, y green, z blue, w yellow, each labelled at its + end. The w axis starts as a point,
  because it is the direction projected away, and grows as the object turns into W.
- **Floor shadow:** a light from above throws the shadow of the 3D shadow onto a matt white disc
  below the object: 4D → 3D → 2D in one picture. In the room the disc is also the handle that
  moves the object (§7.2).

### 6.5 Size

**Every object fills its space by itself; *Size* is a factor on top, and lines keep their thickness
in metres.**
- **Automatic size** [D15]: the radius that holds 90 % of the projected vertices fills 75 % of the
  smallest side of the volume or the room's box. It is measured over 32 fixed orientations, so it
  depends only on the object, κ and s and does not pump while the object turns. The few vertices
  that the stereographic projection flings far out do not shrink the rest.
- **Size factor** 0.25–4, also by pinching with two hands. Above 1 the object rises, so that its
  lower part does not sink into the floor disc [D21]; its top is then cut by the volume (after the
  clipping margins), and to see more you make the window bigger.
- **Thickness is metric** [D28]: edges and faces keep their thickness in metres when you zoom or
  resize the window. In the room they are twice as thick (§10.8).

## 7. Places: the volume and the room

**The same content runs in two places that differ only in a small `SceneHost` value (§9.3): a
volumetric window that shares the space with other apps, and the room, where the object stands at
room size.**

### 7.1 The volume

- A 1 m box by default, resizable by its corners, at least 0.5 m per side; the content follows its
  measured size [D19]. visionOS restores the size between launches.
- It requests clipping margins of 0.5 m on every side, so large shadows reach out of the box
  instead of being cut at its walls; the system may grant less [D27].
- It does not know where the viewer's head is, only which side of the volume they are on: front,
  right, back or left. That side is the sort direction for transparency [D17].
- While the room is open, the volume stays empty.

### 7.2 The room

- *Open in room* on the Display tab opens an immersive space with mixed immersion; other apps'
  windows are hidden meanwhile [D37]. The same button closes it, and the object returns to the
  volume.
- The content is placed once, when the room opens: centred 2 m in front of the viewer and 15 cm
  below eye level, in a 2.4 × 2 × 2.4 m box, so the object is about 1.5 m across and the disc about
  1 m below eye level [D30].
- It stands level, even if the head was tilted at that moment: it takes only the head's position
  and heading from ARKit world tracking, without pitch and roll [D36].
- Pinch the disc and drag to move the object through the room; it stays level. Grabbing the object
  itself turns it, as in the volume [D39].
- The Controls stay in their window.

## 8. Interaction

**You act on the object with standard hand gestures and on everything with the control panel; a
help mode explains every control.**

### 8.1 Gestures

The gestures are standard visionOS gestures (variant A) [D3]:

| Gesture | Effect |
|---|---|
| Pinch and drag (one hand) | turn in 4D: the drag direction tips towards W. Right/left → XW, up/down → YW, towards/away → ZW, diagonal → a mix; 10 rad per metre [D26] |
| Let go while moving | throw: the object keeps turning |
| Pinch (grab) | catch: the rotation stops |
| Two hands, twist | turn in 3D |
| Two hands, apart or together | size |
| Double tap | back to the start orientation |
| Room: pinch the disc and drag | move the object through the room |

The object reacts anywhere in the volume, also when it is small or enlarged [D32]. Variant C, in
which one hand does everything (turning the wrist rotates in 3D, moving the hand in 4D), is only
probed in the Developer tab (spike S3, §12.6).

### 8.2 Windows

**There are three windows, the volume, *Controls* and *Info*, and each can be moved on its own.**
- *Controls* opens left of the volume when the volume appears [D25]. *Info* (help and About, 620 ×
  820 pt, resizable) opens below the Controls, wherever the user has put them [D40].
- Neither panel opens by itself at launch or is restored by visionOS. A window that appears in
  front of the volume makes visionOS push the volume back and dim it, and a panel below the volume
  hides the volume's window bar [D23, D25].
- Closing the volume or the Controls ends the app; the other windows and the room close themselves
  [D34]. Closing Info only ends help.
- The panels are windows, not ornaments, because only windows can be moved apart from the volume
  and turn towards the viewer [D38].

### 8.3 Control panel

The Controls window is 1060 pt wide; its height follows the tab. A row of tabs sits on top, and
beside the tabs three buttons: **?** (help mode, §8.4), **About**, and **Reset all**. *Reset all*
needs a second tap within 3 s; it resets every setting, including the Developer ones and the drag
mapping, but keeps the tab, help and the room [D22].

| Tab | Controls |
|---|---|
| Object | one row per kind (polytopes, surfaces, curves); steppers for the duoprism's p and q |
| Projection | 3 presets; sliders κ and s (0–1) |
| Display | 4 presets; edges on/off and edge colour; floor shadow; axes; edge thickness; face opacity; colour source; explode (polytopes); size; *Open in room* |
| Surface | material (6); pattern (4); face thickness (0–0.08). Disabled for curves |
| Motion | 4 presets; Stop; Reset; friction (0–2 /s); one speed slider per plane (±2 rad/s) |
| Developer | transparency method (S1); floor-shadow method (S4); drag gain k (2–18 rad/m) and invert; performance overlay (S2); gesture test (S3); freeze time; fine subdivision (S2 stress test); the viewer's side; ignored launch arguments |

Choices are rows of buttons, not segmented pickers: on the device a segmented picker did not react
to taps (§13.2).

### 8.4 Help

**The app explains itself: in help mode a tap on a control explains it in Info instead of using it
[D22].**
- **?** turns help mode on and shows the current tab's overview. A dashed outline marks everything
  that can be explained, disabled controls included. Closing Info ends help mode.
- A tap shows the control's topic. Taps that only change what is shown, on a tab or an object,
  also take effect, so explaining an object shows it in the volume, the best picture of it.
- **About** shows the version, date, author and licence and a short guide: moving, resizing and
  closing the windows, turning in 4D and 3D, throwing and catching, size, back to the start, help.
- There are 56 topics: About, one overview per tab, one per object and one per control (a few
  controls share one).

---

# Part B: How it is built

## 9. Architecture

**A pure, tested maths package computes everything; the app holds the state, turns it into meshes
and shows them with RealityKit.**

### 9.1 Modules and data flow

```
            Core4D: Foundation + simd only, tested                     App: SwiftUI, RealityKit
ObjectID ─► Complex4D ─► RenderMesh4D ─────► FrameBuilder ──────────► DynamicMesh ─► entities
            once per     when the object,    when R or a parameter     (LowLevelMesh)
            object       explode or the      changed: positions,
                         subdivision change  normals, uv, indices
ViewState ◄── presets · launch arguments · saved settings · panel · gestures          (AppModel)
```

- **Core4D** is a local Swift package that imports only Foundation and simd; every public function
  is tested. It holds Complex4D and the generators, Rotation4D, Projection4D, Tessellation
  (RenderMesh4D), FrameBuilder, ViewState and the presets, LaunchConfiguration, SavedSettings,
  GestureMapping, SizeFit, AxisCross and LevelPose.
- **The app** holds AppModel, the scenes and windows, the control panel and help, the renderer with
  its RealityKit `System`, the gestures and the debug tools.
- **Complex4D** is the exact combinatorics: vertices; edges as polylines (two indices for
  polytopes); faces with their vertices in cyclic order and, for polytopes, their two cells; cells
  with their faces and centre; (u, v) per point for surfaces; a key per curve.
- **RenderMesh4D** is the render-ready, static geometry: face points and edge points, each flat and
  on S³ (`p/|p|`, after explode); a colour key and pattern coordinates per point; triangles;
  polylines; ranges per polygon and per cell.
- **FrameBuilder** turns a RenderMesh4D and the frame's parameters into vertex and index arrays. Its
  buffers are sized once, for the largest case.
- Complex4D, R and Ω use Double; RenderMesh4D and the per-frame work use Float.

### 9.2 State

**`ViewState` is the single source of truth for what is shown; everything that sets it only
assigns parts of it.**

| Stage | Field | Default | Range |
|---|---|---|---|
| Object | object; duoprism p, q | tesseract; 3, 4 | 10 objects; 3…24 |
| Projection | κ, s | 0.6, 0 (Perspective) | 0…1 |
| Display | edges; edge thickness; edge colour | on; 0.012; same as faces | 0.002…0.04 |
| | face opacity; colour source; material | 25 %; by W; glowing | 0…1 |
| | explode; pattern; face thickness | 0; none; 0 | 0…0.4; –; 0…0.08 |
| | floor shadow; axes | on; off | |
| Motion | Ω; friction | Simple; 0 | sliders ±2 rad/s; 0…2 /s |
| Orientation | R | start tilt (§4) | |
| Size | scale | 1 | 0.25…4 |
| Developer | transparency; floor-shadow method; overlay, gesture test, freeze time, fine subdivision | additive; light; all off | |

- Ranges are enforced where values enter: launch arguments, saved settings, sliders and gestures.
- *Effective* values are derived, never stored: explode is 0 for anything but polytopes and at
  least 5 % with per-cell colour; a colour source that does not fit the object falls back to
  uniform; the transparency method falls back as described in §11.5.
- **Partial assignments:** a preset sets a few fields (§4–6), launch arguments set fields one by one
  (§12.5), saved settings restore every stage except R (§9.4), and *Reset all* assigns the
  defaults.
- **AppModel** (`@Observable`, shared by every scene) holds the ViewState and the app's own state:
  the drag mapping (k and sign), the tab, help mode and topic, whether the room is open, whether
  the app is closing, the viewer's side, launch problems, and whether settings are saved. Its
  `tick` advances the motion once per frame for all hosts (§10.2).

### 9.3 Hosts and the entity tree

**Scene content depends only on a `SceneHost` value, never on the scene that hosts it.**

| | Volume | Room |
|---|---|---|
| bounds (m) | the measured window size, default 1 × 1 × 1 | 2.4 × 2 × 2.4 |
| content offset (m) | 0 | (0, −0.15, −2) from the viewer's level pose |
| thickness reference side (m) | 1 | 2 |
| sort direction | the viewer's side of the volume | +z, towards where the viewer stood when the room opened |

In both, the floor disc lies 0.45 × the height below the content centre.

The volume's entity tree:

```
ShadowRoot (ShadowComponent; never rotated)
└─ Stage (disabled while the room is open)
   ├─ Content (scaled to metres, lifted, §6.5) ─ Faces, Edges, CellEntities
   ├─ FloorShadow ─ FloorDisc, FloorLight
   ├─ Axes (lifted)
   ├─ InputTarget (collision sphere, §11.8)
   └─ ManipulationProbe (spike S3)
```

In the room, `RoomLevel` (the head's position and heading, §10.9) holds `RoomBase`, which holds the
same `ShadowRoot` (its FloorShadow keeps only the light) and, beside it, the `FloorDisc` as handle.
Every frame the root is placed above the disc, and both are kept upright [D39]. Without world
tracking the room hangs under a head anchor placed once, which keeps the head's tilt.

### 9.4 Settings and start modes

**The app starts in one of two modes: normally with the saved settings, or in snapshot mode with
the defaults and the launch arguments [D29].**
- **Normal start:** load `SavedSettings` from the user defaults (key `savedSettings`, JSON). Save
  0.5 s after the last change, and at once when the volume leaves the foreground.
- **Snapshot mode:** any recognised launch argument (§12.5), even one with an invalid value. The
  app starts from the defaults, applies the arguments and saves nothing, so snapshots are
  reproducible.
- **Saved:** every ViewState stage except the orientation R, including Ω (a throw resumes) and the
  Developer settings, plus the drag mapping. **Not saved:** R, which always starts at the start
  tilt; the tab; help; the room; the `-viewpoint` override.
- Each part decodes on its own and falls back to its default, so an update that changes one stage
  keeps the others. Numbers are clamped to their ranges (Ω is not).

## 10. Mathematics

### 10.1 Conventions

- x points right, y up, z towards the viewer (RealityKit's convention); w is the fourth axis. The
  projection is along w.
- Rotations act in the world frame: they are multiplied **from the left**.
- Objects are centred on their vertex centroid and scaled to circumradius 1.

### 10.2 Rotation

- Rotation in the plane of the unit vectors a and b by θ (a positive θ turns a towards b):
  `G(a, b, θ) = I + (cos θ − 1)(a aᵀ + b bᵀ) + sin θ (b aᵀ − a bᵀ)`
- Step: `step(Ω, Δt) = G_zw · G_yw · G_xw · G_yz · G_xz · G_xy`, each plane by ω·Δt. The
  approximation is good enough for small Δt; G_xy and G_zw commute exactly.
- Every frame: `R ← orthonormalize(step(Ω, Δt) · R)` (Gram–Schmidt on the columns, against
  rounding drift), then `Ω ← Ω · e^(−friction·Δt)`; Ω becomes exactly 0 once every |ω| < 10⁻³.
- Δt is wall-clock time, at most 0.1 s. Calls less than 2 ms apart are ignored, so the motion
  advances once per frame however many hosts call. Nothing moves while time is frozen.
- Start orientation: `R₀ = G_yz(25°) · G_xz(35°)`.

### 10.3 From a 4D point to a 3D point

One map serves the mesh, the automatic size and the axes:

1. **Spherize:** `v = flat + s · (sphere − flat)`, with `sphere = flat / |flat|`. Only boundary
   points are drawn, so |flat| is never 0.
2. **Rotate:** `r = R · v`.
3. **Project:** `d = 1 − κ·r_w`, `p = r_xyz / d`. Stereographic projection from the north pole
   (0, 0, 0, 1) is κ = 1 on S³.
4. **Drop:** a point is invalid if `d < ε` (ε = 0.02: at or behind the eye) or `|p| > R_max`
   (4 × the largest box side, in object units). Triangles and edge segments with an invalid point
   are dropped. The axes are clamped instead (§10.9).

### 10.4 Explode and subdivision

- **Explode** by the fraction e: each cell gets its own copies of its faces and edges, moved
  towards its centre c: `v' = c + (1 − e)(v − c)`. It is applied before spherizing.
- **Subdivision** makes arcs smooth when s > 0. The projection maps lines to lines, so at s = 0
  every edge stays one segment and every polygon a plain fan [D14]. Only polytopes are subdivided:
  every edge into n segments, every polygon as a fan around its centroid with each fan triangle
  split into m², so a k-gon has k·m² triangles.
- **Levels** by the number of edges: under 200 → n = 8, m = 3; under 1000 → 6, 2; otherwise 5, 2.
  So the 24-cell gets 8, 3, the 600-cell 6, 2 and the 120-cell 5, 2. The Developer switch *fine
  subdivision* forces 8, 3 at any s, as a stress test.
- Points are shared within a polygon but not between polygons, so shading is smooth inside a face
  and crisp at its borders.

### 10.5 Polytope generator

**Every convex 4-polytope follows from its vertices and its facet normals:**
1. Centre the vertices and scale them to circumradius 1.
2. For each normal n, the cell's vertex set is `S_n = { i : v_i·n ≥ max_j(v_j·n) − ε }`, with
   ε = 10⁻⁶ · max(1, |n|).
3. Two cells whose common vertices are at least 3 and span a plane (affine dimension 2, tolerance
   10⁻⁴) share a face. Its vertices are ordered by angle around their centroid.
4. The edges are the polygon sides without duplicates. A cell's centre is the centroid of its
   vertices.

Inputs, before normalisation:

| Object | Vertices | Normals |
|---|---|---|
| 5-cell | (1,1,1,−1/√5), (1,−1,−1,−1/√5), (−1,1,−1,−1/√5), (−1,−1,1,−1/√5), (0,0,0,4/√5) | −vertices |
| Tesseract | (±1, ±1, ±1, ±1) | ±eᵢ |
| 16-cell | permutations of (±1, 0, 0, 0) | (±1, ±1, ±1, ±1) |
| 24-cell | permutations of (±1, ±1, 0, 0) | ±eᵢ and (±½, ±½, ±½, ±½) |
| 600-cell | permutations of (±1,0,0,0); (±½,±½,±½,±½); **even** permutations of ½(±φ, ±1, ±1/φ, 0), φ the golden ratio | its normalised cell centres, see below |
| 120-cell | the normalised cell centres of the 600-cell | the vertices of the 600-cell |
| Duoprism p×q | (cos 2πi/p, sin 2πi/p, cos 2πj/q, sin 2πj/q) | (cos 2π(i+½)/p, sin 2π(i+½)/p, 0, 0) and (0, 0, cos 2π(j+½)/q, sin 2π(j+½)/q) |

**The 600-cell and 120-cell without a list of 600 points:** the 600-cell's edges are the vertex
pairs at minimal distance (tolerance factor 1 + 10⁻⁶); its cells, tetrahedra, are the 4-cliques of
this edge graph; their normalised centroids are its normals and, at the same time, the 120-cell's
vertices. The f-vector tests (§12.4) guard all of this.

### 10.6 Surfaces and curves

- **Surfaces:** a grid of (n_u + 1)(n_v + 1) points, including the closing row. The seams are not
  glued; their points exist twice. Each quad is two triangles, and grid points are shared, so
  shading is smooth. The edges are every k-th grid line. (u, v) is kept for colour and patterns.
- **Klein bottle in ℝ⁴**, without self-intersection:
  `f(u, v) = ((R + r cos v) cos u, (R + r cos v) sin u, r sin v cos(u/2), r sin v sin(u/2))`,
  u, v ∈ [0, 2π], R = 1, r = 0.5, divided by its largest radius 1.5. It satisfies
  f(u + 2π, v) = f(u, −v). Grid 72 × 36; edges every 6th line.
- **Clifford torus:** `(cos u, sin u, cos v, sin v) / √2`. Grid 64 × 64; edges every 8th line.
- **Hopf fibration:** the fibre over the point (θ, φ) of S², θ being the polar angle, is
  `t ↦ (cos(θ/2) cos t, cos(θ/2) sin t, sin(θ/2) cos(t + φ), sin(θ/2) sin(t + φ))`.
  There are 3 latitudes, θ = 0.3π, 0.5π and 0.7π, with 16 base points each, φ = 2πj/16; they form
  nested tori of linked circles. Each fibre is a closed polyline of 96 points; its colour key is
  its index.

### 10.7 Gestures

- **Drag** by Δ (metres, in the input target's space): `R ← G((Δ̂, 0), e_w, sign · k · |Δ|) · R`,
  with k = 10 rad/m and sign ±1 from the Developer tab.
- **Throw:** Ω_xw, Ω_yw, Ω_zw = sign · k · v, with v the drag velocity over the last 0.1 s; the
  other planes are 0, and Ω is scaled down so that no |ω| exceeds 4 rad/s. A throw needs
  |v| ≥ 0.05 m/s and no two-hand gesture running.
- **Catch:** Ω = 0 when a drag or a twist begins.
- **Twist** (two hands, quaternion q, applied in increments): `R ← diag(M(q), 1) · R`, with q
  mirrored to (−x, y, −z, w) [verify].
- **Magnify:** size = clamp(size at the start × magnification, 0.25, 4). It does not catch.
- **Double tap:** R ← R₀.
- While a two-hand gesture runs, drags are ignored.

### 10.8 Size and thickness

- **Fitted radius** r₉₀: the 90th percentile of |p| over 32 fixed orientations (each a product of
  all six plane rotations with fixed pseudo-random angles) and at most 512 sample vertices.
  Dropped points count as infinitely far; if the percentile itself is infinite, the largest finite
  distance is used. It is cached per object, κ and s.
- **Metres per unit:** `0.375 · smallest side / r₉₀ · size`: the fitted radius is 75 % of half the
  smallest side.
- **Lift** for size > 1: `0.375 · smallest side · (size − 1)`, so the bottom of the fitted radius
  stays where it is at size 1.
- **Thickness** t is a fixed length, `t · 0.375 m · reference side` (1 m in the volume, 2 m in the
  room). Edge tubes have this radius: 0.012 gives 4.5 mm in the volume. Faces are offset by half of
  it to each side: 0.08 gives 3 cm slabs.

### 10.9 Axes and room placement

- **Axes:** the ends ±R·eᵢ are projected like points, but not spherized: they are unit vectors, so
  they meet the object also when it is spherized. An end at or behind the eye is pulled back along
  its axis to d = ε, and ends are clamped to R_max. Lines stay straight under every κ.
- **Level pose** (room): the position is the head's position. The heading is
  yaw = atan2(−f_x, −f_z), where f is the head's −z axis projected onto the floor; when looking
  straight up or down, the head's −y or +y axis is used instead. The content turns only about +y.

## 11. Frame loop and rendering

### 11.1 The frame loop

**Every frame, a RealityKit `System` updates each host's renderer, but the mesh is rebuilt only when
R or a parameter has changed.** For each root (the volume's, and the room's while it is open):

1. Advance the motion (`AppModel.tick`, §10.2).
2. Map every point to 3D (§10.3).
3. Drop invalid triangles and segments.
4. Compute normals and the two face copies (§11.3) and build the edge tubes (§11.4).
5. Turn colour keys into texture coordinates (§11.6).
6. Copy vertices and indices into the meshes (§11.2).

Steps 2–6 run only after a rebuild or when the frame's parameters changed: R, κ, s, the colour
modes, the edge radius, the sort direction or the face offset. So nothing is computed while Ω = 0
and nothing else changes. Around these steps:
- **Structure:** when the object, p, q, the effective explode or the subdivision changes,
  RenderMesh4D and FrameBuilder are rebuilt; the meshes are recreated only if they are too small.
- **Layers:** materials and visibility are applied again only when they change.
- **Cheap updates** every frame: scale, lift, input target, floor, axes; in the room, the root
  follows the disc.
- While the room is open, the volume's renderer only ticks.

### 11.2 Meshes

- One `LowLevelMesh` entity for the faces and one for the edges, each with its own material.
- One interleaved vertex buffer of 48 bytes per vertex: position float3 at 0, normal float3 at 16,
  uv0 float2 at 32. Indices are uint32. The single part is replaced at every upload with its index
  count and bounds.
- Capacity is reserved once for the largest case: faces need 2 × points vertices and
  6 × triangles indices, edges 6 vertices per polyline point.
- Very large meshes are expensive to create, so they are reused while they are big enough.

### 11.3 Faces: two copies of every triangle

**Every face triangle exists twice, facing opposite ways, and back-face culling shows the copy
that faces the viewer [D12, D16].** Lit materials are then right from every side without knowing
where the viewer is.
- The front copy has the vertex normals (area-weighted from the polygon's triangles) and the
  winding as built; the back copy has the same points, negated normals and reversed winding.
- Thick faces use the same copies: each moves by h along its own normal (h = 0 is a thin face)
  [D24].
- With per-cell entities, each polygon is first wound to face away from its projected cell centre,
  and the copies are split by cell (§11.5).

### 11.4 Edges: tubes

RealityKit has no thick lines, so every polyline becomes a tube with 6 sides. The tangent comes
from central differences; the first normal is t × x̂ (t × ŷ if |t_x| ≥ 0.9) and is carried along
by parallel transport. Normals are radial. Both ends get flat fan caps, so open ends never show. A
polyline is split at invalid points, and each piece gets its own caps.

### 11.5 Transparency

**Translucent faces must be drawn in the right order; the three methods differ in who orders them
(spike S1).** The method is a Developer setting.

| Method | Order | Blending | Look |
|---|---|---|---|
| Additive (default) | none needed | `.add` program, no depth writes | glowing glass; light patterns wash out to white |
| Sorted | per triangle, back to front along the sort direction | alpha, no depth writes | clean glass |
| Per-cell entities | per cell, by RealityKit; inside a cell the back copies first (`ModelSortGroup`) | alpha | exploded cells layered correctly |

- Faces with an opacity of 99.9 % or more are opaque and write depth; at 0.1 % or less they are
  hidden. Edges are always opaque.
- **Fallbacks:** per-cell entities need explode > 0 and at most 48 cells, otherwise sorted is used
  [D31]; additive with a pattern draws sorted [D24]; until the asynchronous `.add` programs are
  ready, additive draws as unsorted alpha.
- **Sort direction:** in the volume, towards the viewer's side (front +z, right +x [verify], back
  −z, left −x; `-viewpoint` overrides it) [D17]; in the room, +z.
- Per-cell entities are created lazily: per cell one entity with the back copies (order 0) and one
  with the front copies (order 1), placed at the cell's centroid.

### 11.6 Materials and textures

**Every colour source is a small texture plus a texture coordinate, so all sources take one path.**

Glowing is an `UnlitMaterial`; the other materials are `PhysicallyBasedMaterial`s with a white tint
times the texture:

| Material | Roughness | Other |
|---|---|---|
| matte | 0.75 | |
| glossy | 0.15 | clearcoat 1, clearcoat roughness 0 |
| metal | 0.22 | metallic 1 |
| ceramic | 0.35 | clearcoat 1, clearcoat roughness 0.05 |
| frosted glass | 0.6 | clearcoat 0.5, clearcoat roughness 0.3 |

Textures are 8-bit sRGB, clamped, with linear filtering unless noted:

| Source | Texture | uv |
|---|---|---|
| uniform | 4×4, (0.55, 0.85, 1) | (½, ½) |
| plain light (edges) | 4×4, (0.95, 0.95, 0.90) | (½, ½) |
| by W | 256×1: blue (0.15, 0.40, 1) → (0.85, 0.80, 0.95) → red (1, 0.22, 0.18) | ((w + 1)/2, ½), every frame |
| per cell | 12×1 palette, nearest filtering | ((cell mod 12 + ½)/12, ½) |
| surface parameter | 384×192 checkerboard of 12 × 6 squares, (1, 0.80, 0.35) and (0.20, 0.45, 0.90) | (u, v) |
| per fibre | 256×1 hues, HSV(i/256, 0.75, 1) | (key, ½) |

**Patterns** are 256 × 256, tileable, mipmapped and repeating, drawn in code with a wave
t = a sum of five integer-frequency sines:
- *grid:* 10 px lines (0.16, 0.22, 0.40) on two sides of a paper tile (0.93, 0.93, 0.96);
- *marble:* veins (0.42, 0.44, 0.50) in stone (0.95, 0.94, 0.91), mixed by s^0.25 with
  s = ½ + ½ sin 2π(u + 0.3t);
- *wood:* dark (0.52, 0.32, 0.16) to light (0.86, 0.66, 0.42) rings, mixed by (1 − |2f − 1|)^0.6
  with f = frac(3v + 0.25t).

Pattern coordinates are fixed in 4D: in the plane of each polygon, 0.25 units per repeat, the first
axis along the polygon's first side; on surfaces (u, v) × 8.

### 11.7 Floor shadow

- **Disc:** a 4 mm cylinder at the floor height with radius 0.3 × min(width, depth), so 0.3 m in
  the volume and 0.72 m in the room. Physically based white (0.9), roughness 1; it casts no
  shadow.
- **Light:** directional, intensity 3000, pointing down from 0.48 × the height, with a shadow
  (maximum distance 4 m, depth bias 1).
- **Methods** (Developer, spike S4): *directional light*, the default, where faces, edges and cells
  cast shadows; or *grounding shadow*, where the light is off and the casters get a
  `GroundingShadowComponent`. Turning the floor shadow off hides disc and light in the volume; the
  room keeps the disc as handle.
- Edge shadows are clear; face shadows appeared only sometimes (§13.3) [verify on device].

### 11.8 Input

- **Input target:** a separate entity with a static collision sphere, an `InputTargetComponent` and
  a `ShadowInputComponent`; the mesh changes every frame, so it cannot be the target. All gestures
  accept only entities with a `ShadowInputComponent` [D32].
  - Volume: radius ½ × the smallest side, centred and never lifted, because touches outside the
    volume are not delivered.
  - Room: radius 0.375 × the smallest side × size, at the lift.
- **Gestures** are SwiftUI gestures targeted to that entity: `DragGesture(minimumDistance: 0)`,
  whose location is converted into the target's space, plus `RotateGesture3D`, `MagnifyGesture`
  and `SpatialTapGesture(count: 2)` as simultaneous gestures (maths in §10.7).
- **Room disc:** a collision box (2r × 6 cm × 2r), a hover effect and a `ManipulationComponent` on
  the disc itself: it stays where released, translates freely (also vertically), does not rotate
  or scale and has no inertia. It must not sit on an ancestor of the object's input target, or it
  takes the object's grabs too [D39].
- **Gesture test** (spike S3): a 4 cm sphere with its own `ManipulationComponent` (it springs back
  when released) at bounds × (0.4, −0.38, 0.4). A panel beside the volume shows the raw values of
  the SwiftUI gestures and the `ManipulationEvents` of all content.

### 11.9 Performance

- **Budget:** 90 Hz, so under about 3 ms CPU per frame for the 120-cell on the device.
- Work on the CPU with SIMD first and measure. Move to Metal compute only if the budget is
  exceeded, and ask first.
- Core4D and the app are compiled with `-O` even in Debug: the pipeline is about 40× slower without
  it [D11].
- The performance overlay (S2) shows the frame time and rate, the CPU time per frame and per
  build, and the triangle and vertex counts, averaged over 0.5 s. Measurements are in §13.4.

## 12. Project, build and verification

### 12.1 Platform and conventions

- A native visionOS app [D1]: Swift 6 (tools 6.4, language mode 6), SwiftUI, RealityKit, and ARKit
  world tracking for the room's placement. No third-party code; XcodeGen is the only extra tool
  [D6].
- Deployment target visionOS 27.0 [D7]. Core4D also supports macOS 27, so its tests run on the Mac.
- Everything is in English: UI, code, comments and docs. UI strings go through a String Catalog, so
  the app can be localised later [D8].
- Licence: Apache 2.0, © 2026 Andreas Keese (`LICENSE`, `NOTICE`).
- Signing: a free Apple ID (Personal Team), so an install lasts 7 days [D2]. The team ID and the
  real bundle ID live only in the git-ignored `Config/Signing.local.xcconfig`, which the user
  creates.

### 12.2 Project layout

```
visionpro_shadow43/
├── DESIGN.md                      this document
├── CLAUDE.md                      working rules for Claude
├── NIGHT_RUN.md, NIGHT_REPORT.md  plan and log of the unattended runs and device rounds
├── README.md, LICENSE, NOTICE
├── setup/claude-settings.json     Claude Code permissions; the user copies it to .claude/settings.json
├── project.yml                    XcodeGen spec; Shadow43.xcodeproj is generated and git-ignored
├── Config/
│   ├── Shared.xcconfig            committed: placeholder bundle ID, optional include of the local file
│   └── Signing.local.xcconfig     git-ignored: DEVELOPMENT_TEAM, the real PRODUCT_BUNDLE_IDENTIFIER
├── Shadow43/                      app target
│   ├── App/                       app, scenes and windows, AppModel, SceneHost, settings store
│   ├── UI/                        control panel
│   ├── Help/                      help topics, Info window
│   ├── Rendering/                 renderer and System, meshes, materials, textures, floor, axes, head pose
│   ├── Input/                     gestures
│   ├── Debug/                     snapshot mode, performance overlay, gesture test
│   └── Resources/                 String Catalog
└── Packages/Core4D/               local Swift package: Foundation and simd only
    ├── Sources/Core4D/            complex and generators, rotation, projection, tessellation, frame
    │                              builder, state and presets, launch arguments, saved settings,
    │                              gestures, size fit, axes, room pose
    └── Tests/Core4DTests/         Swift Testing
```

- Run `xcodegen generate` after adding or removing a file: XcodeGen lists the sources when it
  generates the project.
- `App.body` must be declared as `some SwiftUI.Scene`, because RealityKit also defines `Scene`.

### 12.3 Build settings

- **project.yml:** visionOS 27.0 and the local package Core4D. Info.plist is generated from
  `info.properties`: display name, development region en, `CFBundleShortVersionString =
  $(MARKETING_VERSION)` (0.10.0), `CFBundleVersion = $(CURRENT_PROJECT_VERSION)` (1), and a scene
  manifest with the volumetric role as the preferred default and multiple scenes. Settings:
  `SWIFT_VERSION` 6.0, automatic signing, `SWIFT_EMIT_LOC_STRINGS` and
  `LOCALIZATION_PREFERS_STRING_CATALOGS` on, `-O` also for Debug [D11].
- **Package.swift:** tools 6.4; platforms macOS 27 and visionOS 27; `unsafeFlags(["-O"])` for
  Core4D, which is acceptable for a local package [D11].
- **Config/Shared.xcconfig:** `PRODUCT_BUNDLE_IDENTIFIER = com.example.shadow43` and
  `#include? "Signing.local.xcconfig"`.
- No privacy keys: world tracking needs no authorization [verify on device].

### 12.4 Tests

- Every public Core4D function has tests (Swift Testing, `swift test`). Pure app logic moves into
  Core4D wherever possible, so it can be tested.
- **f-vectors** (vertices, edges, faces, cells): 5-cell (5, 10, 10, 5), tesseract
  (16, 32, 24, 8), 16-cell (8, 24, 32, 16), 24-cell (24, 96, 96, 24), 600-cell
  (120, 720, 1200, 600), 120-cell (600, 1200, 720, 120), duoprism p×q (pq, 2pq, pq + p + q, p + q).
- **Structure:** Euler characteristic 0; every face in exactly 2 cells; every edge of a cell in
  exactly 2 of its faces; equal edge lengths in regular polytopes; planar, cyclically ordered
  faces.
- **Rotation:** RᵀR = I and det R = 1 after 10⁶ steps; a full turn of 2π gives I; G_xy and G_zw
  commute; friction stops at its threshold.
- **Projection:** κ = 0 returns (x, y, z); w = 0 stays fixed; at κ = 1 on S³ the south pole maps to
  the origin, the equator (w = 0) to the unit sphere, and great circles to circles or lines.
- **Surfaces and curves:** the Clifford torus and the Hopf fibres lie on S³; the fibres are pairwise
  disjoint; the Klein bottle satisfies its seam condition and has no self-intersection.
- **Pipeline:** subdivision counts, explode, culling, sort order, outward cell faces, the visible
  lit copy, tubes, uv modes, patterns, thick faces.
- **Gestures:** a drag by (L, 0, 0) turns XW by k·L; the sign; throws and their clamp; the twist.
- **Settings:** every launch argument with its problems and clamps, `-time`; saved settings (round
  trip without R, per-part fallback, the snapshot rule); size fit; axes; level pose.

### 12.5 Snapshot mode and launch arguments

**Every visual state can be set from the command line, so it can be checked with a screenshot
instead of clicks.** Launch arguments arrive as strings in the `UserDefaults` argument domain, for
example `-object tesseract -projection perspective -display glass -time 1.5`. Any recognised key
starts snapshot mode (§9.4). Presets are applied first, then single keys. Invalid values are
ignored, logged and listed in the Developer tab. Booleans are 1/yes/true/on or 0/no/false/off.

| Stage | Keys and values |
|---|---|
| Object | `object` 5-cell, tesseract, 16-cell, 24-cell, 120-cell, 600-cell, duoprism, klein-bottle, clifford-torus, hopf · `p`, `q` 3…24 |
| Projection | `projection` orthographic, perspective, stereographic · `kappa`, `spherize` 0…1 |
| Display | `display` wireframe, glass, solid, cells · `edges`, `floorShadow`, `axes` (bool) · `thickness`, `opacity`, `explode`, `faceThickness` · `edgeColor` faces, light · `colors` uniform, by-w, per-cell, surface, per-fibre · `style` matte, glossy, glowing, metal, ceramic, frosted · `pattern` none, grid, marble, wood |
| Motion | `motion` simple, double, isoclinic, drift, none · `omega` six numbers "xy,xz,yz,xw,yw,zw" · `friction` · `time` t: advance t seconds in steps of 1/90 s, then freeze time |
| Size | `scale` 0.25…4 |
| Developer | `transparency` additive, sorted, cells · `shadowMethod` light, grounding · `overlay`, `gestureTest`, `fine` (bool) |
| App | `panel` a tab: object, projection, display, surface, motion, developer · `help` about, a tab or an object · `room` (bool) · `viewpoint` front, right, back, left |

### 12.6 Simulator, device and spikes

- **Simulator loop:** generate, test, build, boot "Apple Vision Pro", install, launch with
  arguments, take a screenshot with `simctl io`, shut down. The exact commands are in CLAUDE.md.
  The simulator cannot inject gestures or move windows.
- **Device loop:** the user runs the app from Xcode and reports back; every round of work ends with
  a short device checklist in NIGHT_REPORT.md.
- **Spikes** answered open questions with implementations that stay switchable in the Developer
  tab:
  - S1 transparency: all three methods (§11.5); additive is the default.
  - S2 mesh update: the performance overlay, and *fine subdivision* as a stress test (§13.4).
  - S3 gestures: the gesture test panel and probe; variant A ships, variant C is only probed.
  - S4 floor shadow: directional light (default) or grounding shadow (§11.7).
- **Milestones** [D4], all done: M0 setup and spikes · M1 core maths · M2 first image · M3 display
  · M4 gestures · M5 large polytopes · M6 surfaces and curves.

---

# Part C: Records

## 13. Lessons from testing

Facts learnt while building and testing that the SDK does not make obvious. The decisions they led
to are in §15.

### 13.1 Toolchain and simulator

- Xcode 27.1 with the visionOS 27.0 SDK and Swift 6.4. `xcode-select` points to the Command Line
  Tools, so commands need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- `swift`, `xcodebuild`, `xcrun` and `simctl` fail inside Claude Code's sandbox (no xcrun cache, no
  CoreSimulator) and must run outside it; commands with `cd`, pipes, redirects or `$(...)` stay
  sandboxed even then.
- Installing right after booting the simulator fails with `IXErrorDomain code=3 "Failed to locate
  promise"`; it works about 20 s after `bootstatus -b`.
- The app needs 3–5 s to launch; an earlier screenshot shows the system's loading placeholder.
- The simulator renders at 120 Hz. Its timings are rough; only the device counts.
- In the simulator, the world-tracking device anchor is the space's origin, unturned.
- `xcodebuild` does not write extracted strings back into the String Catalog; a build in the Xcode
  IDE does.
- Installing from Xcode with the 27.0 SDK onto a device with visionOS 27.2 works; the first
  "Preparing device" takes several minutes over Wi-Fi.

### 13.2 Windows, ornaments and panels

- A window that opens at the default spot in front of the volume makes visionOS push the volume
  back and dim it, and the system restores such windows at launch [D23, D25].
- An ornament below the volume hides the volume's window bar and resize corners [D23].
- Ornaments move with their window and cannot be moved apart from it; they do not turn towards the
  viewer; their gesture coordinates, also in `.global` and in named spaces, move with them; content
  outside their bounds is clipped; anchors outside 0…1 work; a `RealityView` in an ornament shows
  nothing [D23, D35, D38].
- A segmented `Picker` in an ornament highlighted on look but did not react to taps on the device.
  Rows of buttons and toggles work.
- `WindowPlacement` offers only the utility-panel spot and the four sides of an existing window. No
  API reads or sets a window's position, and scene geometry preferences cover only its size.
- A second window placed beside the volume opened out of view in the simulator; a window placed
  below the Controls appears [D40].
- A placement closure sees only windows that already exist: Info, opened in the same `onAppear` as
  the Controls, fell back to the utility panel [D40].
- The volume's size is restored between launches; `defaultSize` only applies to a new window.
- The simulator granted 0.47 m of the 0.5 m clipping margins requested; the first report, before
  layout, is 0.

### 13.3 RealityKit

- A `LowLevelMesh` with one interleaved buffer works; its part can be replaced every frame.
- Creating very large meshes (about 240k vertices) stalls once ("Hang detected while waiting for
  renderer to free resources"); hence the reuse.
- `UnlitMaterial.Program(descriptor:)` and its `PhysicallyBasedMaterial` twin are `async`; both
  materials share one blending type.
- simd has no `simd_float4x4(simd_double4x4)` initializer; Core4D has `Rotation4D.float(_:)`.
- Standard materials ignore a `.color` vertex attribute, and their ambient-occlusion map reads uv0,
  not uv1. So combining a colour source with a pattern needs a `ShaderGraphMaterial`.
- Additive blending adds translucent layers up to white, so light patterns vanish; sorted keeps
  them.
- Floor shadow: a directional light casts clear shadows of the edge tubes; shadows of faces
  appeared only in some runs; a fixed orthographic shadow projection showed none; a grounding
  shadow only darkened the whole disc.
- A `ManipulationComponent` on an entity also takes the grabs on its descendants' input targets
  [D39].
- Thick faces show the Klein bottle's seam (its orientation reversal) as a step. Marble reads as
  stone, wood still looks like corrugated cardboard, and metal reflects the room.

### 13.4 Performance

- Unoptimised Swift is about 40× slower for the pipeline: the stereographic 120-cell took 34.7 ms
  CPU per frame in Debug and 0.8 ms optimised [D11].
- Normal settings cost about 1 ms CPU per frame in the simulator (the 120-cell has 81k triangles,
  the 600-cell 69k).
- Stress test (120-cell, stereographic, Cells, fine subdivision): 503k triangles and 13–23 ms CPU
  per frame, of which 2–3 ms is the FrameBuilder; the rest is copying about 17 MB into the meshes.
  If the device is too slow: a 32-byte vertex and writing straight into the mesh buffers, then,
  after asking, Metal.
- Per-cell entities cost about 1 ms per cell per frame: the exploded 600-cell ran at 5 Hz (631 ms)
  in the simulator and crashed the device; the 120-cell ran at 40 Hz [D31].
- The exploded 600-cell is slow on the device, although the simulator runs it at 119 Hz with
  1.2 ms CPU: the GPU is the limit, with many overlapping translucent, reflective layers.

### 13.5 Room and gestures

- `openImmersiveSpace` can fail quietly: on the device the first room button seemed to do nothing,
  so the app logs and shows the result [D30].
- A fixed position in the immersive space's coordinates ended up off to the side; placing relative
  to the head works. A head anchor placed once carries the head's tilt into the content; world
  tracking gives the pose to level it [D30, D36].
- Touches outside the volume's bounds are not delivered, so an input target lifted out of the
  volume stops reacting [D32].
- A drag gain of 2π per 0.3 m was too sensitive; 10 rad/m felt right on the device [D26].

## 14. Open points

### 14.1 To verify on the device

- Info below the Controls: do the Controls grow into Info when their height changes with the tab?
  Is Info too low when the Controls are low? [D40]
- Room: level with a tilted head; world tracking without authorization; dragging the disc;
  turning and throwing the object [D36, D39].
- Viewer side: does `onVolumeViewpointChange` fire in the volume, and does *right* mean +x? [D17]
- Twist: the mirrored quaternion; in the room the twist ignores the room's heading.
- Closing: do all windows and the room close together [D34], also when another app opens a Full
  Space?
- Shadows of faces; sliders and menus in the windows; the device's numbers for S2; variant C (S3).

### 14.2 Known issues

Found in a review of the code on 2026-11-09:
- `-help <object>` and `-help <tab>` show the text but neither select the object nor switch the
  tab, as a tap does.
- Not reachable by launch arguments: 39 of the 56 help topics, "?" together with About, the drag
  mapping, the armed *Reset all*, the room's error text and the volume size.
- Projection presets animate with `withAnimation`, which probably moves only the sliders; the
  shadow jumps.
- Diagnostics are saved like settings: a session that ended with time frozen starts frozen.
- Throws reach 4 rad/s, the speed sliders only ±2; Ω from launch arguments or saved settings is not
  clamped.
- After switching to an object kind without the chosen colour source, the colour menu shows nothing
  (the object is drawn uniform).
- *Reset all*: arming, confirming and arming again within 3 s disarms early, because the timer is
  not cancelled.
- The room's error text stays after the room closes. An invalid `-panel` is ignored silently, and
  an invalid `-help` is not logged.
- The first and last grid lines of a surface are separate tubes in the same place, which can
  z-fight in two colours.
- The material cache grows with every opacity value while the slider moves.
- Cell entities created after the floor-shadow method changed always use the directional light, so
  with the grounding method cells cast no shadow.
- With per-cell transparency, every explode step recreates two meshes per cell.
- The additive programs are created per renderer, so again whenever the room opens.
- The room sorts towards +z, not the head. The drag maps in the volume's axes, so seen from behind,
  right turns −XW.
- In the room, the Manipulation log also records moves of the disc.
- App-side gesture logic (catch, throw minimum, twist mirror, magnify clamp) and the choice of
  texture per colour source are not tested.
- The String Catalog lags behind the code (6 unused keys, several missing) until the next IDE
  build. The About page's date is hard-coded. `TessellationOptions.surfaceEdgeStride` is unused.

### 14.3 Proposed simplifications

- **Presets as data:** each preset lists the fields it assigns; applying and matching follow from
  that, and D13 needs no special case.
- **One range per field,** used by launch arguments, saved settings, sliders and gestures, Ω
  included.
- **One effective-transparency rule** in Core4D: the per-cell limit, pattern → sorted, and programs
  not ready → sorted.
- **Help as one optional topic** (none = Info closed), with "?" mode as a separate flag. The volume
  owns the Controls, the Controls own Info.
- **Convert gesture rotations** with `EntityTargetValue.convert(_:from:to:)` instead of the
  hand-written mirror; that also fixes the room's heading.
- **SceneHost:** drop the unused viewer pose and `tracksVolumeViewpoint`, which equals
  kind == window; keep one source for the sort direction.
- **Diagnostics apart from settings:** do not save freeze time, the overlays and fine subdivision.
- **One uv per point,** set when tessellating; only *by W* changes it every frame.

### 14.4 Later ideas

- Slices by a hyperplane, as in Flatland, and a Flatland mode that shows the same ideas one
  dimension down.
- Colour and pattern together (`ShaderGraphMaterial`); image textures and numbers per cell.
- In the room: sorting by the head pose, hand tracking, shadows on and placement onto real
  surfaces.
- Orientation presets (cell first, vertex first); trails of single vertices.
- The Lawson Klein bottle on S³; more uniform polytopes; named, saved scenes.

## 15. Decision log

Every decision with its date, the sections it shapes and its reason. Replaced decisions stay for
their reasons and name their successor.

- **D1** · 2026-11-08 · §12.1 — A native Swift app instead of WebXR. *Why:* the best gestures; a
  real app.
- **D2** · 2026-11-08 · §12.1 — Test with a free Apple ID (Personal Team) for now. *Why:* enough for
  development; the Developer Program can follow when needed.
- **D3** · 2026-11-08 · §8.1 — Gestures: build variant A from standard gestures; probe the one-hand
  variant C (wrist turn = 3D, hand movement = 4D, via `ManipulationComponent`) only in spike S3.
  *Why:* standard gestures are robust; C is more elegant but unproven.
- **D4** · 2026-11-08 · §12.6 — v1 consists of milestones M0–M6. *Why:* the app is usable from M2
  on, and each milestone is useful on its own.
- **D5** · 2026-11-08 · §7, §9.3 — The volume is the main place; an immersive space hosts the same
  content and shares the state, and everything that differs goes through `SceneHost`. *Why:* keeps
  v1 focused without blocking room scale. D30, D36 and D39 completed the room.
- **D6** · 2026-11-08 · §12.2 — XcodeGen generates the Xcode project from `project.yml`. *Why:* the
  project can be versioned and reviewed as text.
- **D7** · 2026-11-08 · §12.1 — Deployment target visionOS 27.0, the newest. *Why:* the user keeps
  the device up to date.
- **D8** · 2026-11-08 · §12.1 — Everything in English; open source under Apache 2.0,
  © Andreas Keese; git locally first, GitHub later.
- **D9** · 2026-11-08 · §5 — Projection as two controls, κ and s, with presets. *Why:* one formula
  covers orthographic, perspective and stereographic projection and lets you morph between them.
- **D10** · 2026-11-08 · §6 — Display as layers with presets; volumes are cells with explode;
  colour per cell forces a minimum explode. *Why:* fewer modes and orthogonal controls; a face
  between two cells can have only one colour.
- **D11** · 2026-11-08 · §11.9, §12.3 — Core4D (`unsafeFlags` in `Package.swift`) and the app
  (`SWIFT_OPTIMIZATION_LEVEL` for Debug in `project.yml`) are compiled with `-O` in every
  configuration; debug info stays. *Why:* the pipeline is about 40× slower unoptimised, and a
  normal Run from Xcode should show the real speed. Revert locally to step through code in the
  debugger.
- **D12** · 2026-11-08 · §11.3 — Double-sided faces are drawn in both windings with back-face
  culling. *Why:* the same look as no culling, while lit and shadow paths stay uniform. Completed
  by D16.
- **D13** · 2026-11-08 · §6.2 — Leaving the *Cells* preset sets explode to 0 and the colour to
  *by W*. *Why:* otherwise every other preset would still look exploded.
- **D14** · 2026-11-08 · §10.4 — Subdivide only when s > 0, with fewer levels for large polytopes.
  *Why:* the projection maps lines to lines, and large polytopes stay within the budget.
- **D15** · 2026-11-08 · §6.5, §10.8 — Automatic size: the 90th-percentile vertex radius over 32
  fixed orientations fills 75 % of the smallest side; the user's size is a factor on top. *Why:*
  every object and projection fills the volume, stereographic outliers do not shrink the rest, and
  nothing pumps while the object turns. At 80 % the tesseract touched the floor disc. Its rule for
  thickness was replaced by D28.
- **D16** · 2026-11-08 · §11.3 — Every face triangle has a front copy, whose normal follows its
  winding, and a back copy with reversed winding and negated normal. *Why:* lit materials look
  right from every side without knowing the viewer; it costs twice the face vertices, little next
  to the tubes.
- **D17** · 2026-11-08 · §7.1, §11.5 — The volume sorts towards the viewer's side
  (`onVolumeViewpointChange`, four sides); the head pose only later, in the room. *Why:* the shared
  space gives no head pose, and four sides are much better than a fixed +z.
- **D18** · 2026-11-08 · §4 — The start and reset orientation is a 3D tilt: 35° in XZ, then 25° in
  YZ. *Why:* the tesseract starts as the classic cube inside a cube, seen at an angle;
  axis-aligned views hide edges behind each other.
- **D19** · 2026-11-08 · §7.1 — The volume is a 1 m box by default and resizable, at least 0.5 m;
  its measured size is the host's bounds, so size, floor disc and input target follow. *Why:* a
  0.8 m box looked small on the device, and resizing is the standard way to make a window bigger.
- **D20** · 2026-11-08 · §6.4 — An optional axes layer: the four 4D axes, rotated and projected
  like the object, coloured and labelled. *Why:* it shows how the four directions map into the
  shadow; W grows from a point as the object turns into it.
- **D21** · 2026-11-08 · §6.5, §10.8 — With a size factor above 1 the object rises, so the bottom of
  its fitted radius stays where it is at factor 1. *Why:* enlarged objects sank into the floor
  disc; the rule does not depend on the rotation, so the object does not bob.
- **D22** · 2026-11-08 · §8.3, §8.4 — Help: a "?" mode in which a tap explains a control instead of
  using it, and explaining an object also shows it; an About page; *Reset all* with a second tap to
  confirm. *Why:* the app explains itself; the volume is the best picture of an object; two taps
  work where a dialog might not.
- **D23** · 2026-11-08 · §8.2 — *Replaced by D25.* The controls in an ornament left of the volume,
  help in one right of it, and no second window. *Why:* a panel below the volume hid its window bar
  and resize corners, and a separate help window was restored at launch in front of the volume,
  which visionOS then pushed back and dimmed.
- **D24** · 2026-11-08 · §6.3 — The Surface tab: three more materials (metal, ceramic, frosted
  glass), image patterns drawn in code and fixed in 4D that replace the face colour, and thick
  faces. *Why:* the user wanted to try all three. Standard materials ignore vertex colours, so
  colour and pattern together need a custom shader; a pattern fixed in 4D shows the projection's
  distortion; additive blending washes patterns out, so a pattern switches to sorted.
- **D25** · 2026-11-08 · §8.2 — Controls and Info are separate windows; the Controls open left of
  the volume; neither launches by itself nor is restored by the system; the volume opens the
  Controls. Replaces D23. *Why:* the user wants to move the panels, and ornaments cannot be moved
  apart from their window; placing the windows explicitly avoids D23's push-back. Trade-off: the
  panels do not follow when the volume moves.
- **D26** · 2026-11-08 · §8.1, §10.7 — Drag gain k = 10 rad/m, a full turn per 0.63 m, adjustable
  from 2 to 18 in the Developer tab. *Why:* 2π per 0.3 m was too sensitive; the user chose 10 on
  the device.
- **D27** · 2026-11-08 · §7.1 — The volume requests clipping margins of 0.5 m on every side. *Why:*
  the user dislikes the clipping at the walls; margins let large shadows reach out while keeping a
  window. The system may grant less. A full immersive space would remove all limits but hides
  other apps.
- **D28** · 2026-11-08 · §6.5, §10.8 — Edge and face thickness keep their size in metres when the
  object is zoomed or the window resized: a fixed length per host, with a reference box of 1 m in
  the volume and 2 m in the room. *Why:* the user: "when I zoom or pinch in, the edges should not
  scale". Face thickness follows, so edges still cover the rims of thick faces.
- **D29** · 2026-11-08 · §9.4 — Settings are kept between launches: every stage except the
  orientation, plus the drag mapping, as JSON in the user defaults; each part decodes on its own;
  any recognised launch argument means snapshot mode. *Why:* the user wants the settings kept; the
  orientation always starts at the tilt; per-part decoding keeps most settings across updates;
  snapshots stay reproducible.
- **D30** · 2026-11-08 · §7.2 — The room places the content once, 2 m in front of the viewer and
  15 cm below eye level, in a 2.4 × 2 × 2.4 m box; the volume is empty while the room is open;
  opening reports failures. *Why:* the room button seemed to do nothing on the device, and a fixed
  position in the space was off to the side. D36 made the placement level.
- **D31** · 2026-11-08 · §11.5 — Per-cell entities only with explode and at most 48 cells; the 120-
  and 600-cell use sorted instead. *Why:* the device crashed on the exploded 600-cell; per-cell
  entities cost about 1 ms per cell per frame (§13.4).
- **D32** · 2026-11-08 · §11.8 — In the volume the input target is a sphere that fills it, centred
  and never lifted; in the room it follows size and lift. Gestures accept only entities with a
  `ShadowInputComponent`. *Why:* an enlarged object stopped reacting, because its lifted input
  sphere left the volume, where touches are not delivered; targeting by component keeps other
  touchable entities, such as the room's disc, from turning the object.
- **D33** · 2026-11-08 · §7.2 — *Replaced by D39.* In the room the floor disc redirects the system's
  manipulation to the content root, so dragging it moves everything. *Why:* the user wanted to move
  the room object by its disc.
- **D34** · 2026-11-08 · §8.2 — Closing the volume or the Controls closes the app: both set
  `isClosing`, and then every window and the room close themselves. *Why:* one close should end
  the app, and a window that is going away may no longer be able to close the others [verify].
- **D35** · 2026-11-09 · §8.2 — *Reverted by D38.* Controls and Info as ornaments of the volume, each
  with a grab bar, their places saved relative to the volume. *Why:* the user wanted the panels to
  stay where they put them, relative to the object and across launches, which windows cannot do.
- **D36** · 2026-11-09 · §7.2, §10.9 — The room content is placed level: at the head's position and
  heading without pitch and roll, from ARKit world tracking queried once (a head anchor only as
  fallback); the content stays upright. *Why:* the head's tilt at opening tilted the content, and
  dragging the disc tilted the object.
- **D37** · 2026-11-09 · §7.2, §8.3 — *Open in room* is on the Display tab and no longer marked
  experimental. *Why:* the room works.
- **D38** · 2026-11-09 · §8.2 — D35 reverted: the panels are windows again (D25, D34), and their
  places are not saved. *Why:* on the device, a panel moved in front of the volume could no longer
  be grabbed by its bar and could not be moved away from the volume, the panels did not turn
  towards the viewer, and Info behaved oddly.
- **D39** · 2026-11-09 · §7.2, §11.8 — The room's floor disc carries its own `ManipulationComponent`
  (translation only), as a sibling of the content root; the root follows the disc every frame.
  Replaces D33. *Why:* with the manipulation on the root, grabbing the object moved everything
  instead of turning it.
- **D40** · 2026-11-09 · §8.2 — Info opens below the Controls (at the utility-panel spot only if the
  Controls are closed), and the Controls open Info at launch when help is asked for. *Why:*
  visionOS cannot save a window's place, but placing Info by the Controls keeps it near wherever
  the user moved them; below rather than beside, because the wide Controls could push Info onto the
  volume. Risks: §14.1.

## 16. Glossary

- **Cell:** a 3D boundary body of a 4D polytope. The tesseract has 8 cubes, the 120-cell 120
  dodecahedra.
- **Clifford torus:** a flat torus on S³. Projected stereographically, it looks like an ordinary
  torus.
- **Duoprism p×q:** the product of a p-gon and a q-gon. The 4×4 duoprism is the tesseract.
- **Explode:** shrinking every cell towards its centre, so that the cells come apart.
- **Flatland:** Edwin A. Abbott's 1884 novella about a two-dimensional world (§1).
- **Host:** the scene that shows the content, the volume or the room (`SceneHost`).
- **Hopf fibration:** a decomposition of S³ into great circles (fibres), any two of which are
  linked.
- **Isoclinic (Clifford) rotation:** rotation at the same speed in two perpendicular planes, such as
  XY and ZW. Every point moves on a great circle.
- **Ornament:** a SwiftUI panel attached to a window, which moves with it.
- **Projection:** here, the map from 4D to 3D along W that makes the shadow (§5).
- **Rotation plane:** in 4D you rotate in planes, not about axes. There are six: XY, XZ, YZ, XW, YW
  and ZW.
- **S³ (3-sphere):** the points of ℝ⁴ at distance 1 from the origin.
- **Schlegel diagram:** a perspective image of a polytope in which one cell becomes the outer hull
  ("cube inside a cube").
- **Spherize:** moving every point towards its position on S³ (§5).
- **Stereographic projection:** projection of S³ from the north pole into 3D space. It preserves
  circles and angles.
- **Tesseract:** the 4D cube, with 16 vertices, 32 edges, 24 squares and 8 cubes.
- **Volume:** a volumetric window, a box in space that shares the room with other apps.
