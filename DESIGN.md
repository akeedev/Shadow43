# Shadow43: 4D shadows for Apple Vision Pro

**Version 0.3 · 2026-11-08 · Status: design final, ready for implementation**

How to read this document:
- Part A (sections 1–4) describes *what* the app does.
- Part B (sections 5–6) describes *how* it is built. It is complete enough to implement from.
- Section 7 is the decision log, section 8 records findings during implementation, and section 9
  is a glossary.

Markers in the text:
- **[verify]**: a technical assumption that must be checked before relying on it. Check it against
  the SDK interface files or a small experiment.
- **[Dn]**: refers to decision n in section 7.

---

# Part A: Concept

## 1. Goal

Shadow43 shows the three-dimensional shadow (the projection) of four-dimensional objects,
floating freely in space. You pick an object and rotate it in four dimensions, either by hand or
automatically. You then watch the shadow deform, turn itself inside out and pass through itself.
The view is stereoscopic, so you can walk around it.

**Guiding principle: a few independent controls instead of many modes.** Every aspect of the
display is its own parameter. "Modes" are only named presets of these parameters.

## 2. Existing solutions (researched 2026-11-08)

| App | Platform | What it does | What it lacks |
|---|---|---|---|
| [4D Toys](https://apps.apple.com/us/app/4d-toys/id1143791442) | iOS, listed for visionOS | 130 scenes with 4D physics, mostly 3D **slices**, wireframe | free object choice, projection modes, rotation planes; last update 2023 |
| [4D Polytope Viewer](https://studio.pardesco.com/4d-viewer) | browser | 1700+ polytopes, 6 rotation planes, perspective and stereographic | not immersive, no gestures |
| [Four Dimensional Space](https://apps.apple.com/us/app/id6762447300) | iPad app | one tesseract next to a black hole | controls, object choice |

**Conclusion:** No native spatial app offers free object choice, all rotation planes, continuous
projections and gesture control.

## 3. Concept: one pipeline with independent stages

```
Object ──► Preparation ──► Spherize ──► Rotate ──► Project ──► Scene
(3.1)      (3.4)           s (3.3)      R, Ω (3.2) κ (3.3)     display (3.4), shadow (3.5)
```

Each stage has its own controls. Changing one stage never requires adjusting another.

### 3.1 Objects

All objects are converted into **one common data model**, a *complex* made of:
- vertices (points in ℝ⁴)
- edges (polylines)
- faces (polygons)
- cells (closed groups of faces, polytopes only)

Rotation, projection and display therefore work the same for every object. Controls that make no
sense for an object, such as cells for the Klein bottle, are disabled.

There are three kinds of objects, each with one generic generator:

| Kind | Generator | Input | Examples |
|---|---|---|---|
| Convex polytopes | vertices + facet normals → full complex | vertex coordinates, directions of the boundary cells | 5-, 8- (tesseract), 16-, 24-, 120-, 600-cell; duoprisms p×q |
| Surfaces in 4D | parametric surface f(u,v) → triangle grid | formula, parameter range | Klein bottle, Clifford torus |
| Curve families | parametric curves → polylines | formula, choice of curves | Hopf fibration |

The polytope generator needs only vertices and normals. It derives edges, faces and cells itself
(6.6). This gives three simplifications:
- Duoprisms, the product of a p-gon and a q-gon, come almost for free.
- The tesseract is the 4×4 duoprism.
- The duocylinder is the limit for large p and q.

All objects are centred and scaled to circumradius 1.

### 3.2 Rotation

- 4D has **6 rotation planes**:
  - XY, XZ and YZ are the familiar 3D rotations. They only turn the shadow rigidly.
  - XW, YW and ZW are the genuinely four-dimensional rotations. They deform the shadow.
- The state consists of the orientation **R** (a 4×4 rotation matrix) and the angular velocity
  **Ω** (six numbers, one per plane).
- **There is only one source of motion.** Auto-rotation and gestures are the same thing:
  - A preset sets Ω.
  - Throwing the object with a hand sets Ω.
  - Grabbing it stops it ("catching").
  - The Stop button sets Ω to zero.
  - The **friction** control damps Ω. The default is off, so the object keeps rotating forever.
- **Motion presets:**
  - *Simple:* XW
  - *Double:* XY + ZW at different speeds
  - *Isoclinic:* XY + ZW at the same speed (Clifford rotation, which has no 3D equivalent)
  - *Drift:* all 6 planes, slow and at different speeds
- **Reset** sets R back to the start orientation: a pure 3D tilt (35° in XZ, then 25° in YZ), so
  the tesseract in perspective shows its cube inside a cube, seen obliquely [D18].
- All rotation planes refer to the user's view, not to the object.
- The 3D entity in the scene is **never rotated itself**; all rotation lives in R. That keeps a
  single source of truth, and it is correct because 3D rotations commute with the projection.

### 3.3 Projection: two controls instead of three modes

Orthographic, perspective and stereographic projection are not different methods. They are
points in a space with two parameters:

- **Perspective strength κ** ("kappa", the reciprocal of the eye distance along W):
  `p = (x, y, z) / (1 − κ·w)`
  - κ = 0 gives the orthographic projection: W is simply dropped.
  - κ ≈ 0.6 gives the classic perspective ("cube within a cube").
  - Points with w = 0 stay in place for every κ, so the image does not jump.
- **Spherize s:** each point is blended between its flat position and its position on the
  3-sphere. s = 0 is the flat polytope, s = 1 the "inflated" one.
- **Stereographic is simply (κ = 1, s = 1).** Edges become circular arcs, and the 120-cell turns
  into the well-known soap-bubble picture.
- The UI offers the three classics as presets: *Orthographic* (0, 0), *Perspective* (0.6, 0),
  *Stereographic* (1, 1). You can morph continuously between them, which none of the existing apps
  can do.
- Parts at or behind the eye (1 − κw near 0) and parts extremely far away are dropped (6.3).

*Scope note:* A slice by a hyperplane, as in 4D Toys, is not a projection. It creates new
geometry, so it is not part of v1. The "Project" stage is encapsulated so that slicing can be added
later.

### 3.4 Display: layers instead of modes

"Wireframe", "solid" and "transparent with wireframe" are combinations of independent layers:

| Layer | Controls |
|---|---|
| Edges | visible, thickness, colour (same as faces, or plain light) |
| Faces | opacity 0–100 %, colour source, style *matte/glossy* or *glowing* |
| Cells (polytopes only) | explode 0–40 %: each cell shrinks towards its centre |
| Axes [D20] | on/off: the object's four 4D axes x, y, z, w, rotated and projected with it |
| Surface [D24, experimental] | material (matte, glossy, glowing, metal, ceramic, frosted glass), image pattern (grid, marble, wood), face thickness |

**Display presets:**
- *Wireframe:* edges on, faces 0 %
- *Glass:* edges on, faces 25 %, glowing
- *Solid:* faces 100 %, thin edges
- *Cells:* explode 20 %, faces 100 %, colour per cell

**Transparent volumes need no mechanism of their own.** A cell is drawn by its boundary faces.
With explode above 0, each cell is a separate glass body whose transparency is set by the face
opacity.

**Colour source** (one choice for the whole object):
- *uniform*
- *by W* (blue ↔ red): shows what lies "in front" in 4D. This is the single most helpful aid to
  understanding.
- *per cell* (palette): every face belongs to **two** cells, so this source automatically applies
  a small minimum explode of 5 %. Then each cell has its own faces.
- *surface parameter:* checkerboard in (u, v), for parametric surfaces
- *per fibre:* for the Hopf fibration

Technically all colour sources go through the same path: a texture coordinate plus a small
texture (6.5). Image textures per cell (wood, glass, digits) can be added later without
restructuring.

### 3.5 Scene

- **v1: volumetric window.** A box in space that can be placed freely and resized: 1 m by default,
  at least 0.5 m; the content follows the size [D19].
- **Automatic size [D15]:** every object is scaled so that the radius holding 90 % of its projected
  vertices fills 75 % of the box's smallest side. The radius is measured over 32 fixed orientations,
  so it depends only on the object, κ and s and does not pump while the object rotates. The few
  vertices that fly far out in the stereographic view do not shrink the rest. The user's *Size*
  control (and the two-hand pinch) is a factor on top. Edge thickness is relative to the fitted
  radius, so tubes keep their size in metres.
- **Shadow of the shadow:** a light from above casts the shadow of the 3D projection onto a subtle
  virtual floor disc in the box. That shows 4D → 3D → 2D in one scene.
- **Immersive space: prepared in v1, completed later [D5]:**
  - The content (root entity plus system) does not depend on the scene that hosts it. The
    volumetric window and an `ImmersiveSpace` (mixed immersion) host *the same* content and share
    one `ViewState`.
  - v1 declares the `ImmersiveSpace` and opens it from an "Open in room (experimental)" button.
    It shows the content at room scale (about 2 m), with the same controls and no extra features.
  - Everything that differs by host goes through one `SceneHost` value: bounds, and what the host
    knows about the viewer. Later additions slot in there without restructuring: head pose for
    transparency sorting via ARKit world tracking, hand tracking, and placing the content on real
    surfaces.
- **Where the viewer is [D17]:** a volumetric window gets no head pose [verify]. It only learns
  which side of the volume the viewer is on (front, right, back, left) from
  `onVolumeViewpointChange`; that side is the sort direction of the *sorted* transparency method.
  In the immersive space, ARKit world tracking can give the exact head pose (next step, not yet
  connected).

### 3.6 Interaction

**Principle: every gesture has an equivalent in the control panel.** This is needed for the
simulator, for precision and for accessibility.

The control panel is a window of its own, opened left of the volume, which the user can move
[D25]; help and About open in a second window, the *Info* panel. The panel is at most two levels
deep:
- **Object:** grouped by kind; p and q for duoprisms
- **Projection:** 3 presets plus the κ and s sliders
- **Display:** 4 presets plus the layer controls from 3.4
- **Surface** [D24]: material, pattern, thickness
- **Motion:** 4 presets, friction, Stop, Reset, and 6 sliders (speed per plane)
- **Developer** (collapsed): transparency method (S1), performance overlay (S2), gesture test (S3),
  "Open in room"
- Next to the tabs [D22]: **?** (help mode: tap any control to have it explained), **About**
  (version, author, usage guide) and **Reset all** (tap twice)

**Gestures [D3]:** variant A is built first; it uses only standard visionOS gestures:

| Gesture | Effect |
|---|---|
| Pinch + drag (one hand) | 4D rotation: the drag direction tips towards W. Right/left → XW, up/down → YW, forward/back → ZW, diagonal → a mix |
| Two hands pinch and twist | 3D rotation |
| Two hands apart/together | scale |
| Release with momentum | throw: the rotation continues |
| Pinch and hold | catch: the rotation stops |
| Double tap | reset orientation |

Variant C is tested in spike S3 and not shipped yet. In it, one hand does everything: turning the
wrist rotates in 3D and moving the hand rotates in 4D, via `ManipulationComponent` events [verify].

## 4. Scope and milestones [D4]

| Milestone | Content |
|---|---|
| **M0** Setup + spikes | XcodeGen project, Core4D package, licence files, technical spikes S1–S4 (6.9) |
| **M1** Core | Core4D: complex, generators for the 5-, 8-, 16- and 24-cell, rotation, projection, all tested |
| **M2** First image | window with edges and faces, object and projection choice, motion presets, basic control panel |
| **M3** Display | all layers, presets, colour sources, explode, floor shadow |
| **M4** Gestures | variant A, throw and catch, gesture test scene for variant C |
| **M5** Large polytopes | 120- and 600-cell, duoprisms, smooth stereographic display, performance |
| **M6** Surfaces and curves | Klein bottle, Clifford torus, Hopf fibration |

The app is usable from M2 on. Each further milestone is useful on its own.

**Deliberately not in v1** (later candidates, roughly by value):
- completing the immersive space beyond what 3.5 prepares
- slice mode
- image textures and cell numbers
- orientation presets (cell first, vertex first)
- trails of individual vertices
- shadows on real surfaces
- the Lawson Klein bottle on S³
- further uniform polytopes
- saving scenes
- a Flatland analogy

---

# Part B: Technical design

## 5. Platform and environment

- **Native visionOS app:** Swift, SwiftUI, RealityKit. No third-party libraries. XcodeGen is the
  only extra tool and is used only to generate the project [D6].
- **Deployment target:** visionOS 27.0 [D7]. Core4D additionally supports macOS 27, so its tests
  run on the Mac.
- **Language:** everything in English, including UI, code, comments and docs [D8]. UI strings still
  go through a String Catalog, so the app can be localised later.
- **Environment (verified 2026-11-08):** see section 8.
- **Signing:** a free Apple ID (Personal Team) for now; an install lasts 7 days. The team ID and the
  real bundle ID live **only** in `Config/Signing.local.xcconfig`. That file is git-ignored and
  created by the user (6.1).
- **Licence:** Apache 2.0, © 2026 Andreas Keese (`LICENSE`, `NOTICE`) [D8].

## 6. Technical design

### 6.1 Project layout and project generation

```
visionpro_shadow43/
├── DESIGN.md                   this document (single source of truth)
├── CLAUDE.md                   working rules for Claude
├── NIGHT_RUN.md                plan for the unattended implementation run
├── README.md, LICENSE, NOTICE
├── setup/claude-settings.json  Claude Code permissions; the user copies it to .claude/settings.json
├── project.yml                 XcodeGen spec; Shadow43.xcodeproj is generated (git-ignored)
├── Config/
│   ├── Shared.xcconfig         committed; placeholder bundle ID; optional include of the local file
│   └── Signing.local.xcconfig  NOT committed; DEVELOPMENT_TEAM, real PRODUCT_BUNDLE_IDENTIFIER
├── Shadow43/                   app target
│   ├── App/                    App, scenes, ViewState, SceneHost
│   ├── UI/                     control panel
│   ├── Rendering/              mesh building, materials, RealityKit system
│   ├── Input/                  gestures → rotations
│   ├── Debug/                  spikes, performance overlay, launch-argument snapshot mode
│   └── Resources/              String Catalog, small textures
└── Packages/Core4D/            local Swift package: Foundation + simd ONLY
    ├── Package.swift
    ├── Sources/Core4D/         Complex, Generators, Rotation, Projection, Tessellation
    └── Tests/Core4DTests/      Swift Testing
```

**Verified template** (built successfully on 2026-11-08 with Xcode 27.1 and XcodeGen 2.46.0):

```yaml
# project.yml
name: Shadow43
options:
  deploymentTarget:
    visionOS: "27.0"
packages:
  Core4D:
    path: Packages/Core4D
targets:
  Shadow43:
    type: application
    platform: visionOS
    sources: [Shadow43]
    configFiles:
      Debug: Config/Shared.xcconfig
      Release: Config/Shared.xcconfig
    dependencies:
      - package: Core4D
    info:
      path: Shadow43/Info.plist
      properties:
        CFBundleDisplayName: Shadow43
        UIApplicationSceneManifest:
          UIApplicationPreferredDefaultSceneSessionRole: UIWindowSceneSessionRoleVolumetricApplication
          UIApplicationSupportsMultipleScenes: true
          UISceneConfigurations: {}
    settings:
      base:
        SWIFT_VERSION: "6.0"
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_STYLE: Automatic
```

```
// Config/Shared.xcconfig
PRODUCT_BUNDLE_IDENTIFIER = com.example.shadow43
#include? "Signing.local.xcconfig"
```

```swift
// Packages/Core4D/Package.swift
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
    name: "Core4D",
    platforms: [.macOS(.v27), .visionOS(.v27)],
    products: [.library(name: "Core4D", targets: ["Core4D"])],
    targets: [
        .target(name: "Core4D"),
        .testTarget(name: "Core4DTests", dependencies: ["Core4D"]),
    ]
)
```

Pitfall: `App.body` must be declared as `some SwiftUI.Scene`. RealityKit also defines `Scene`, and
the unqualified name does not compile.

### 6.2 Data model (sketch; names are suggestions)

```swift
/// Exact combinatorics, built once per object.
struct Complex4D {
    var vertices: [SIMD4<Double>]   // centred, circumradius 1
    var edges: [[Int]]              // polylines; 2 indices each for polytopes
    var faces: [Face]               // polygons, vertices in cyclic order
    var cells: [Cell]               // polytopes only, otherwise empty
    var uv: [SIMD2<Double>]?        // parametric surfaces only
    var curveKey: [Double]?         // curve families only (base point of the fibre)
    var kind: ObjectKind            // .polytope, .surface, .curves
}
struct Face { var vertices: [Int]; var cells: [Int] }        // polytope: exactly 2 cells
struct Cell { var faces: [Int]; var center: SIMD4<Double> }

/// Render-ready and static. Rebuilt only when the object, explode or subdivision changes.
struct RenderMesh4D {
    var flat:   [SIMD4<Float>]      // points after explode and subdivision
    var sphere: [SIMD4<Float>]      // the same points, normalised onto S³
    var colorKey: [Float]           // static colour key (cell, u/v, fibre)
    var triangles: [UInt32]
    var polylines: [[UInt32]]
}

/// Single source of truth for what is shown (@Observable in the app, shared by all scenes).
struct ViewState {
    var objectID: ObjectID
    var projection: Projection          // kappa, spherize
    var display: DisplaySettings        // layers, colour source, explode, style
    var motion: Motion                  // R (4×4 Double), omega (6), friction
    var scale: Double
}

/// What differs between the volumetric window and the immersive space.
struct SceneHost {
    var bounds: SIMD3<Float>            // metres; the object fills 75 % of the smallest side (D15)
    var viewerPose: ViewerPoseProvider? // nil in the window; ARKit later in the immersive space
    var tracksVolumeViewpoint: Bool     // window: the viewer's side of the volume (D17)
}
```

Presets are named partial assignments of `ViewState`. `ViewState` is `Codable`, which serves
launch arguments, snapshots and saving scenes later.

### 6.3 Per-frame pipeline (RealityKit `System`, every frame)

1. `R ← orthonormalize(step(Ω, Δt) · R)`, then `Ω ← Ω · exp(−friction · Δt)`
2. For each point:
   - `p4 = R · lerp(flat, sphere, s)`
   - `p3 = p4.xyz / (1 − κ · p4.w)`
3. Cull triangles and segments that have a point with `1 − κw < ε` (e.g. 0.02) or
   `|p3| > R_max` (e.g. 4 × the box size).
4. Recompute face normals. Build edges as tubes along the polylines: 6 sides, frames by parallel
   transport.
5. Colour key → UV. For "by W", `u = (w + 1) / 2` every frame; otherwise static.
6. Write the buffers into `LowLevelMesh`.

- If Ω = 0 and no parameter has changed, nothing is recomputed.
- **Budget:** 90 Hz, so under about 3 ms of CPU per frame for the 120-cell on the device. Implement
  on the CPU with SIMD first and measure. Use Metal compute only if the budget is exceeded, and
  ask the user first.

### 6.4 Mathematical reference

- **Coordinates:** x right, y up, z towards the viewer (RealityKit convention), w is the fourth
  axis. Projection is along w.
- **Rotation in one plane** by angle θ, spanned by unit vectors a and b (positive θ turns a towards
  b):
  `G(a, b, θ) = I + (cos θ − 1)(a aᵀ + b bᵀ) + sin θ (b aᵀ − a bᵀ)`
- **Step:** `step(Ω, Δt) = Π G(e_i, e_j, ω_ij · Δt)` over the 6 planes. This approximation is enough
  for small Δt. G(XY) and G(ZW) commute exactly.
- **Orthonormalise:** Gram–Schmidt on R every frame, against rounding drift.
- **World frame:** all rotations are multiplied **from the left**.
- **Drag gesture** by vector Δ (scene coordinates, metres): an impulse `k·Δ` on `ω_xw, ω_yw, ω_zw`,
  i.e. `R ← G(Δ̂, e_w, k·|Δ|) · R`. The starting value for k was 2π per 0.3 m; since D26 it is
  2π per 0.6 m. k and the sign are adjustable in the Developer tab.
  - Throw: Ω_xw, Ω_yw, Ω_zw from the velocity over the last 0.1 s.
  - Catch: Ω = 0 when the gesture begins.
- **3D rotation** from the two-hand gesture (quaternion q): `R ← diag(M(q), 1) · R`
- **Projection:** `p = xyz / (1 − κw)`. Stereographic from the north pole (0, 0, 0, 1) is κ = 1 with
  points on S³.
- **Spherize:** `sphere = v / |v|`. Only boundary points are rendered, so |v| is never 0.
- **Explode** by fraction e: `v' = c + (1 − e)(v − c)`, where c is the cell centre. It is applied
  before spherizing.
- **Subdivision:** edges into n segments; polygons as a fan around the centroid with m²
  subdivision. Needed for smooth arcs when s > 0. Starting values n = 8, m = 3; smaller for large
  polytopes.

### 6.5 Rendering

- **Meshes:** `LowLevelMesh`, one entity each for faces and for edges, each with its own material.
- **Material:** `PhysicallyBasedMaterial` (style matte/glossy) or `UnlitMaterial` (style glowing)
  with a base-colour texture.
  - The colour source is UV plus texture: gradient 256×1, palette N×1, checkerboard.
  - Present in the SDK: `faceCulling`, `writesDepth`, `readsDepth`, and blend modes `.alpha` and
    `.add` (via `Program.Descriptor`).
- Faces are rendered **double-sided**. Closed cells and non-orientable surfaces need this. Every
  triangle exists twice, as a front copy whose normal follows its winding and as a back copy with
  reversed winding and negated normal; back-face culling keeps the copy that faces the camera, so
  lit styles are correct from every side without knowing the viewer [D12, D16].
- **Transparency is the main risk (spike S1).** Implement all three candidates behind the
  Developer switch, so the user can compare them on the device:
  1. **Additive** (`.add`, `writesDepth = false`): independent of order, no flicker, a "glowing
     glass" look. This is the *glowing* style and probably the nicest Glass preset.
  2. **Sorted:** sort triangles back to front every frame (the index list is rebuilt every frame
     anyway). In the window the head pose is unknown, so sort towards the side of the volume the
     viewer is on (D17); between the four sides the order is approximate. Later, in the immersive
     space, sort by the real head pose.
  3. **Per-cell entities** (only with explode > 0): RealityKit sorts entities itself. Within a
     convex cell, draw the inner sides first, then the outer sides (`ModelSortGroupComponent`;
     back copies and front copies as two entities, both with back-face culling).
- **Edges as tubes:** RealityKit has no thick lines, so polylines are built as continuous tubes.
- **Input:** the object entity gets an `InputTargetComponent` and a **static**
  `CollisionComponent` (a sphere the size of the box), because the mesh changes all the time.
- **Floor shadow:** `DirectionalLightComponent` with a shadow (`DynamicLightShadowComponent`) onto a
  floor disc [verify: behaviour in a volume]. Fallback: `GroundingShadowComponent`.
- The volume clips content at its edges. The R_max culling from 6.3 is still needed, against
  numerical extremes.

### 6.6 Polytope generator (vertices + facet normals)

**Algorithm** (works for every convex 4-polytope):
1. Centre the vertices and scale them to circumradius 1.
2. For each normal n, the cell's vertex set is `S_n = { i : v_i·n ≥ max_j(v_j·n) − ε }`.
3. For each pair of cells (a, b): if `I = S_a ∩ S_b` has at least 3 elements and is affinely
   2-dimensional, I is a face with cells (a, b). Order its vertices cyclically by angle around the
   centroid in the face plane.
4. Edges are the sides of the face polygons, without duplicates.
5. A cell consists of its faces; its centre is the centroid of its vertices.

**Inputs** (coordinates before normalisation):

| Object | Vertices | Normals |
|---|---|---|
| 5-cell | (1,1,1,−1/√5), (1,−1,−1,−1/√5), (−1,1,−1,−1/√5), (−1,−1,1,−1/√5), (0,0,0,4/√5) | −vertices |
| Tesseract | (±1, ±1, ±1, ±1) | ±e_i |
| 16-cell | permutations of (±1, 0, 0, 0) | (±1, ±1, ±1, ±1) |
| 24-cell | permutations of (±1, ±1, 0, 0) | ±e_i and (±½, ±½, ±½, ±½) |
| 600-cell | permutations of (±1,0,0,0); (±½,±½,±½,±½); **even** permutations of ½(±φ, ±1, ±1/φ, 0), φ = golden ratio | normalised cell centres, see below |
| 120-cell | normalised cell centres of the 600-cell | vertices of the 600-cell |
| Duoprism p×q | (cos 2πi/p, sin 2πi/p, cos 2πj/q, sin 2πj/q) | (cos 2π(i+½)/p, sin 2π(i+½)/p, 0, 0) and (0, 0, cos 2π(j+½)/q, sin 2π(j+½)/q) |

**Bootstrapping the 600- and 120-cell** (avoids a list of 600 coordinates):
1. The edges of the 600-cell are the vertex pairs at minimal distance.
2. Its cells (tetrahedra) are the 4-cliques in this edge graph.
3. The normalised centroids of these cells give its normals and, at the same time, the vertices of
   the 120-cell.

The count checks in 6.8 guard all of this.

### 6.7 Surfaces and curves

- **Parametric surface:** grid n_u × n_v including the closing row. Gluing the edges is
  unnecessary; duplicate seam points do not affect the display. UV is passed along; edges are
  every k-th grid line.
- **Klein bottle in ℝ⁴** (without self-intersection):
  `f(u,v) = ((R + r cos v) cos u, (R + r cos v) sin u, r sin v cos(u/2), r sin v sin(u/2))` with
  u, v ∈ [0, 2π], R = 1, r = 0.5, then normalised. It satisfies f(u + 2π, v) = f(u, −v).
- **Clifford torus:** `(cos u, sin u, cos v, sin v) / √2`
- **Hopf fibration:** the fibre over the point (θ, φ) of S² (θ is the polar angle) is
  `t ↦ (cos(θ/2) cos t, cos(θ/2) sin t, sin(θ/2) cos(t + φ), sin(θ/2) sin(t + φ))` with t ∈ [0, 2π].
  Initial choice: 3 latitude circles with 16 base points each. That gives nested tori made of
  linked circles. The colour key is the base point.

### 6.8 Tests (Core4D, `swift test`, Swift Testing)

- **f-vectors** (vertices, edges, faces, cells):

  | Object | f-vector |
  |---|---|
  | 5-cell | (5, 10, 10, 5) |
  | Tesseract | (16, 32, 24, 8) |
  | 16-cell | (8, 24, 32, 16) |
  | 24-cell | (24, 96, 96, 24) |
  | 600-cell | (120, 720, 1200, 600) |
  | 120-cell | (600, 1200, 720, 120) |
  | Duoprism p×q | (pq, 2pq, pq + p + q, p + q) |

- **Euler characteristic:** vertices − edges + faces − cells = 0
- **Structure:** every face belongs to exactly 2 cells. Every edge of a cell lies in exactly 2 of
  its faces. In regular polytopes all edges have the same length.
- **Rotation:**
  - RᵀR = I and det R = 1 after 10⁶ steps
  - A full turn of 2π gives I.
  - G(XY) and G(ZW) commute.
- **Projection:**
  - κ = 0 returns (x, y, z).
  - At κ = 1 on S³: the south pole maps to the origin, the equator (w = 0) to the unit sphere, and
    great circles to circles or straight lines.
- **Gesture:** dragging by Δ = (L, 0, 0) gives a rotation in the XW plane by k·L.
- **Surfaces and curves:** the Clifford torus and the Hopf fibres lie on S³. The Hopf fibres are
  pairwise disjoint. The Klein bottle satisfies the seam condition.
- **App-side logic** (pure functions in the app target, e.g. presets and the mapping from gesture to
  Ω) goes into Core4D or a small testable layer wherever possible.

### 6.9 Spikes, testability and acceptance

**Snapshot mode for headless verification:** the app reads launch arguments as `UserDefaults`, e.g.
`-object tesseract -projection perspective -display glass -time 1.5`. They set `ViewState` and
freeze time at a fixed t. Together with `xcrun simctl io booted screenshot`, every state can be
checked without clicking. The Developer section offers the same.

**Spikes in M0.** Each spike ends with a short entry in section 8 that records the chosen approach.

| Spike | Question | Acceptance |
|---|---|---|
| S1 Transparency | Which approach from 6.5? | Tesseract and 24-cell rotate in the Glass preset without visible flicker, also while walking around (device). All three methods switchable |
| S2 Mesh update | Can `LowLevelMesh` handle 250,000 triangles per frame at 90 Hz? | Performance overlay with frame time and triangle count. Simulator gives a rough value, the device the real one |
| S3 Gestures | Does `DragGesture` on an entity in a volume deliver a 3D translation? Do `RotateGesture3D` and `MagnifyGesture` work with two hands? How do the `ManipulationComponent` events behave (variant C)? | Gesture test scene in the Developer section that shows the raw values |
| S4 Floor shadow | A directional light with shadow in a volume | Shadow visible on the floor disc |

**Milestone acceptance.** "Device" means the user checks it on the Vision Pro.

| Milestone | Acceptance |
|---|---|
| M1 | all Core4D tests green |
| M2 | Simulator screenshots: tesseract with edges and faces in the 3 projection presets; switching between 4 polytopes. Device: smooth |
| M3 | screenshots of all display presets and colour sources. Device: Glass without flicker, floor shadow visible |
| M4 | simulator: mouse drag rotates in 4D. Device: throw and catch work, two hands rotate in 3D and scale. The user rates the feel; then tune k and the sign |
| M5 | screenshots of the 120- and 600-cell, stereographic. Device: 90 Hz |
| M6 | screenshots of the Klein bottle, Clifford torus and Hopf fibration with their colour sources |

## 7. Decision log

| # | Date | Decision | Rationale |
|---|---|---|---|
| D1 | 2026-11-08 | Native Swift app instead of WebXR | best gestures, a real app |
| D2 | 2026-11-08 | Test with a free Apple ID for now | Developer Program later if needed |
| D3 | 2026-11-08 | Gestures: build variant A, test variant C in spike S3 | standard gestures are robust; C is more elegant but unproven |
| D4 | 2026-11-08 | v1 = M0–M6 | the app is usable from M2 on |
| D5 | 2026-11-08 | v1 shows the volumetric window; the immersive space is prepared as far as possible (3.5) | keeps v1 focused without blocking room scale |
| D6 | 2026-11-08 | Project generated with XcodeGen from `project.yml` | the project file can be versioned and reviewed as text |
| D7 | 2026-11-08 | Deployment target visionOS 27.0 (newest) | the user updates the device |
| D8 | 2026-11-08 | Everything in English, including UI, code and docs; open source under Apache 2.0, © Andreas Keese; git local first, moved to GitHub later | |
| D9 | 2026-11-08 | Projection as two controls κ, s with presets | one formula covers orthographic, perspective and stereographic, and allows morphing |
| D10 | 2026-11-08 | Display as layers with presets; volumes are cells with explode; colour per cell forces a minimum explode | fewer modes, orthogonal controls |
| D11 | 2026-11-08 | Core4D (`unsafeFlags` in `Package.swift`) and the app target (`SWIFT_OPTIMIZATION_LEVEL` for Debug in `project.yml`) are compiled with `-O` in every configuration; debug info stays | the per-frame pipeline is ~40× slower unoptimised; a normal Run from Xcode should show the real speed. Revert when stepping through code in the debugger |
| D12 | 2026-11-08 | Double-sided faces are emitted in both windings with back-face culling | same look as `faceCulling = .none`; keeps lit and shadow paths uniform (night run, S4) |
| D13 | 2026-11-08 | Leaving the *Cells* display preset resets explode to 0 and the colour source to *by W* | otherwise every other preset would still look exploded; easy to change in `DisplayPreset.apply` |
| D14 | 2026-11-08 | Subdivision only when s > 0; levels by size (n = 8/6/5, m = 3/2/2) | the projection maps lines to lines; large polytopes stay within budget |
| D15 | 2026-11-08 | Automatic size: the 90th-percentile vertex radius, over 32 fixed orientations, fills 75 % of the box's smallest side (first 80 %, which let the tesseract touch the floor disc); the user's size is a factor on top; edge thickness is relative to the fitted radius | every object and projection fills the volume; stereographic outliers do not shrink the rest; no pumping while rotating |
| D16 | 2026-11-08 | Every face triangle has a front copy (normal follows the winding) and a back copy (reversed winding, negated normal); no more "normals turned towards +z" | lit styles are correct from every side without a viewer position; costs twice the face vertices (small next to the tubes) |
| D17 | 2026-11-08 | The window sorts towards the viewer's side of the volume (`onVolumeViewpointChange`, 4 sides); ARKit head pose only in the immersive space, later | the shared space gives no head pose; four sides are much better than a fixed +z |
| D18 | 2026-11-08 | Start and reset orientation is a 3D tilt (35° XZ, 25° YZ) instead of the identity | the tesseract starts as the classic cube inside a cube, seen obliquely; axis-aligned views hide edges behind each other |
| D19 | 2026-11-08 | The window is a 1 m box by default (was 0.8 m) and user-resizable (`windowResizability(.contentMinSize)`, at least 0.5 m); its measured size is the host's bounds, so size fit, floor disc and input target follow | 0.8 m looked small on the device; resizing is the standard visionOS way to make it bigger |
| D21 | 2026-11-08 | With a size factor above 1 the object rises by `0.5 · fill · side · (factor − 1)`, so the bottom of its fitted radius stays where it is at factor 1 | enlarged objects sank into the floor disc; rotation-independent, so it does not bob. The top is cut by the volume instead; to see more, resize the window (D19) |
| D22 | 2026-11-08 | Help: a "?" mode in the tab row, in which tapping any control explains it in the help panel instead of using it; explaining an object also shows it in the volume; an About page (version, date, author, usage guide); *Reset all* with a second tap to confirm | explains the app inside the app; the volume is the best picture of an object; two taps instead of a dialog, which might not work in the ornament |
| D23 | 2026-11-08 | Control panel in an ornament *left* of the volume, help and About in an ornament *right* of it; no second window | a panel below the volume hid the system's window bar and resize corners (on the device and in the simulator); a separate help window made visionOS push the volume back and dim it, and was restored at launch. Ornaments show no 3D content, so the help has no live preview |
| D24 | 2026-11-08 | Experimental *Surface* tab: three more materials (metal, ceramic, frosted glass) as `PhysicallyBasedMaterial` settings; image patterns (grid, marble, wood, drawn in code) on fixed per-face coordinates (polygon plane in ℝ⁴, 0.25 units per repeat; surfaces: u, v × 8) that *replace* the colour source on the faces; thick faces by moving the front and back copies along their normals (±½ thickness) | the user asked to try all three. RealityKit's standard materials ignore vertex colours (tested), so colour and pattern cannot share a face without a custom shader; a pattern fixed in 4D shows the projection's distortion. Additive transparency washes light patterns out, so a pattern switches it to sorted |
| D20 | 2026-11-08 | Optional *Axes* layer: the object's four 4D axes (−eᵢ…+eᵢ), rotated and projected like its points, coloured x red, y green, z blue, w yellow, labelled at the + end | shows how the four directions map into the shadow; w starts as a point (it is the projected-away direction) and grows as the object turns into w. Lines stay straight under every κ; the ends are unit vectors, so they meet the object also when spherized |
| D25 | 2026-11-08 | Controls and Info are separate `Window`s (supersedes D23's ornaments): controls placed `.leading(volume)`, Info as `.utilityPanel`; neither launches nor is restored by the system; the volume opens the controls on appear, opens/closes Info with `showsHelp`, closes both when it closes; a *Controls* ornament on the volume brings closed controls back | the user wants to move the panels; ornaments cannot be moved apart from their window. D23's push-back came from a window at the default spot in front of the volume; these placements avoid it. A second window placed beside the volume opened out of view in the simulator, so Info uses the utility-panel spot. Trade-off: the panels no longer follow when the volume moves |
| D26 | 2026-11-08 | Drag gain k = 10 rad/m, a full 4D turn per 0.63 m of drag (was 2π per 0.3 m); Developer slider 2…18 rad/m with the default in the middle | the user found the drag rotation too sensitive, tried 2π per 0.6 m and then chose 10 on the device |
| D27 | 2026-11-08 | The volume requests clipping margins of 0.5 m on every side (`preferredWindowClippingMargins`); the granted margins are logged | the user dislikes the clipping at the volume's walls; margins keep the window but let enlarged or stereographic shadows reach out of it. The system may grant less. A full immersive space would remove all limits but hides other apps' windows; decide after the device check |
| D28 | 2026-11-08 | Edge and face thickness keep their size in metres when the object is zoomed (Size, pinch) or the window resized: relative to the fitted radius at size factor 1 in a reference box (window 1 m, room 2 m), `SizeFit.fixedLength` | the user: "when I zoom or pinch in, the edges should not scale". Face thickness follows, so edges still cover the rims of thick faces |
| D29 | 2026-11-08 | Settings are kept between launches: `SavedSettings` (every `ViewState` stage except the orientation, plus the drag mapping) as JSON in the user defaults, saved 0.5 s after the last change and when the volume leaves the foreground; each part decodes on its own and falls back to its default; numbers are clamped. Any recognised launch argument means snapshot mode: start from the defaults, save nothing | the user wants the settings kept. The orientation always starts at the start tilt (D18). Per-part decoding keeps most settings when an update changes one stage's fields |
| D30 | 2026-11-08 | Room (immersive space): the content is placed once 2 m in front of the viewer's head (`AnchorEntity(.head, trackingMode: .once)`), 15 cm below eye level, in a 2 m box (object ≈ 1.5 m); the volume shows nothing while the room is open; opening logs its result and shows a reason if it fails | the button seemed to do nothing on the device; in the simulator the room opened, but its fixed position (2.8 m from the space origin) was off to the side. A head-tilted start tilts the content [verify on device] |
| D31 | 2026-11-08 | Per-cell entities (S1) only with explode and at most 48 cells; the 120- and 600-cell use sorted instead | the device crashed on the exploded 600-cell. Simulator with per-cell entities: 600-cell 5 Hz (631 ms CPU per frame), 120-cell 40 Hz (24 ms); with the fallback 120 Hz (1 ms). Additive and the Cells display preset were fine (1.3 ms), fine subdivision heavy but running (504k triangles, 6.7 ms) |
| D32 | 2026-11-08 | Gesture input target in the window: a sphere filling the volume (radius ½ of its smallest side), centred and never lifted; in the room it follows the object's size and lift. The gestures target only entities with `ShadowInputComponent` | on the device an enlarged object stopped reacting until Reset all: the input sphere was lifted with the object (D21) and left the volume, where touches are not delivered. Targeting by component keeps other touchable entities (the room's disc) from rotating the object |
| D33 | 2026-11-08 | Room: the floor disc is a handle. It redirects the system's manipulation (`ManipulationComponent.HitTarget`) to the room's root, translation only, so dragging the disc moves object, disc and light through the room; the disc stays visible without the floor shadow | the user asked to move the room object by grabbing the disc; the system's manipulation needs no own gesture maths under the head anchor |
| D34 | 2026-11-08 | Closing the volume or the controls closes the app: both set `isClosing`, and every window (and the room) then closes itself. The "Controls" button to reopen closed controls is gone | the user wants one close to end the app; a window that is going away may no longer be able to close the others [verify on device] |

## 8. Findings (continued during implementation)

- **2026-11-08, environment:**
  - Xcode 27.1 (27A9275) with the visionOS 27.0 SDK; Swift 6.4; Apple Silicon.
  - `xcode-select` points to the Command Line Tools, so commands need
    `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
  - XcodeGen 2.46.0 installed via Homebrew.
  - visionOS 27.0 simulator runtime (24M362) installed via `xcodebuild -downloadPlatform visionOS`
    (7.5 GB). Simulator device: "Apple Vision Pro".
  - Smoke test: `xcodegen generate`, then `swift test` and `xcodebuild` for
    `generic/platform=visionOS Simulator` with the template from 6.1. **BUILD SUCCEEDED**, tests
    green.
  - Visual loop verified: boot, install, launch with launch arguments, and
    `simctl io … screenshot` work. The volumetric window appears in the simulator's virtual living
    room. A 0.2 m box in a 0.6 m volume looks small in the screenshot, so snapshot mode should use
    a larger scale.
  - Installing right after boot fails with `IXErrorDomain code=3 "Failed to locate promise"`.
    It works after `bootstatus -b` plus about 20 s.
  - The project permissions for unattended runs are in `setup/claude-settings.json`. The user
    copies them to `.claude/settings.json`; Claude is not allowed to change its own permissions.
- **2026-11-08, SDK check (visionOS 27.0):** these declarations exist, but their behaviour is
  **not** tested:
  - RealityKit: `LowLevelMesh`, `LowLevelTexture`, `ModelSortGroupComponent`,
    `ManipulationComponent` with `ManipulationEvents`, `GroundingShadowComponent`,
    `DynamicLightShadowComponent`, `DirectionalLightComponent`, `ShaderGraphMaterial`
  - materials: `faceCulling`, `writesDepth`, `readsDepth`, blend modes `.alpha` and `.add`
  - SwiftUI: `RotateGesture3D`, `MagnifyGesture`, `SpatialEventGesture`, `manipulable`
- **2026-11-08, sandbox:** `xcrun`, `swift`, `xcodebuild` and `simctl` fail inside Claude Code's
  sandbox. They cannot create the xcrun cache under `/var/folders`, and CoreSimulator is
  unreachable. They must run outside the sandbox (`sandbox.excludedCommands` in
  `.claude/settings.json`). Commands containing `cd`, pipes, redirects or `$(...)` stay sandboxed
  even then.
- **2026-11-08, night run (M0–M2):**
  - XcodeGen enumerates source files at generate time: after adding a Swift file, run
    `xcodegen generate` again, otherwise the build fails with "cannot find … in scope".
  - `UnlitMaterial.Blending` and `PhysicallyBasedMaterial.Blending` are the same type.
    `UnlitMaterial.Program(descriptor:)` / `PhysicallyBasedMaterial.Program(descriptor:)` are
    `async`; the `.add` programs are created once at start-up, and until they are ready the
    additive method falls back to alpha blending.
  - simd has no `simd_float4x4(simd_double4x4)` initializer; Core4D has `Rotation4D.float(_:)`.
  - `LowLevelMesh` with one interleaved buffer (position @0, normal @16, uv0 @32, stride 48,
    `SIMD3<Float>` padding) works; parts are replaced every frame with the new index count and
    bounds.
  - The projection maps lines to lines, so subdivision is only needed when s > 0
    (`TessellationOptions.recommended`); at s = 0 every edge is one segment and every polygon a
    plain fan.
  - Faces are double-sided; normals are turned towards the viewer (+z of the box) per polygon
    (polytopes) or per vertex (surfaces), so lit styles look right from the front.
  - Tubes have flat caps (fans over the end rings) so their open ends never show.
  - Simulator: the app launches in about 3–5 s; a screenshot taken right after `simctl launch`
    shows the system's loading placeholder. The simulator renders at 120 Hz; the debug build
    needs about 1.5 ms CPU per frame for the 24-cell (2,200 triangles).
  - In the simulator's living room, a 0.8 m volume with 0.2 m per object unit still looks small;
    snapshots use `-scale 1.3…1.6`.
- **2026-11-08, night run (M3–M5):**
  - **Performance:** unoptimised Swift is about 40× slower for the per-frame pipeline: the
    stereographic 120-cell (81k triangles) took 34.7 ms CPU per frame in a Debug build and 0.8 ms
    in Release (simulator on the Mac). Core4D is therefore compiled with `-O` even in Debug
    (`unsafeFlags` in `Package.swift`; accepted for a local package). The 600-cell then needs
    1.4 ms in a Debug build of the app.
  - **S1 transparency:** all three methods work in the simulator. *Additive* gives the glowing
    glass look; *sorted* (alpha, matte) gives clean glass with no visible sorting errors for the
    24-cell; *per-cell entities* (one `ModelSortGroup` per cell, back faces order 0, front faces
    order 1, cell entities positioned at their centroids) layers exploded cells correctly.
    Flicker while walking around can only be judged on the device.
  - **S4 floor shadow:** `DirectionalLightComponent` + `Shadow` casts clear shadows of the edge
    tubes onto the disc. Face shadows appeared only in some runs (Cells preset, uniform 16-cell),
    not for the solid 24-cell, also not after drawing faces with both windings and back-face
    culling. A `.fixed` orthographic shadow projection showed no shadow at all. With
    `GroundingShadowComponent` the disc only got darker overall. Default stays the directional
    light; the Developer section switches methods [verify on device].
  - Faces are now drawn as both windings with back-face culling (visually identical to
    `faceCulling = .none`); this was a hypothesis for S4 and is harmless.
  - **S2 mesh update (simulator, Debug app with optimised Core4D):** stress test 120-cell,
    stereographic, Cells preset, fine subdivision (n = 8, m = 3): 503k triangles, 239k vertices,
    13.4 ms CPU per frame (65 Hz), of which only 2.3 ms is the FrameBuilder pipeline; the rest is
    copying ~17 MB per frame into the `LowLevelMesh` buffers. Normal settings stay at about 1 ms
    (120-cell 81k triangles, 600-cell 69k triangles). Extrapolated: 250k triangles ≈ 6–7 ms in the
    simulator. The device must give the real number; if the upload is too slow there, the next
    steps are a packed 32-byte vertex format and writing straight into the mesh buffers, before
    considering Metal (ask first).
- **2026-11-08, night run (M6 and wrap-up):**
  - Surfaces share their grid points, so normals are smooth; normals are turned towards the
    viewer per vertex, which also handles the non-orientable Klein bottle. The checkerboard shows
    the Klein bottle's seam flip directly.
  - Hopf fibres are closed polylines (last index = first); tubes get caps at the closing point.
  - The String Catalog (`Localizable.xcstrings`) is in the target and all UI strings are
    `LocalizedStringKey`s, but `xcodebuild` does not write the extracted keys back into the
    catalog; Xcode does that on the first build in the IDE.
  - S3: `ManipulationComponent.configureEntity(_:collisionShapes:)` plus `ManipulationEvents`
    subscriptions via `RealityViewContent.subscribe(to:)` compile; the probe sphere sits at the
    front-right corner of the volume, outside the main input target, so the two do not compete.
    Behaviour of all gestures is untested (simulator CLI cannot inject gestures).
  - When the stress-test meshes (~240k vertices) are created, RealityKit logs "Hang detected while
    waiting for renderer to free resources" once; the app then runs normally. Recreating very
    large `LowLevelMesh`es is a visible hitch, so meshes are reused when their capacity suffices.
- **2026-11-08, after v0.9 (D11 extended, D15–D18):**
  - App target with `-O` in Debug: the S2 stress test gave 18–23 ms CPU in the simulator (build
    2.0–3.0 ms) against 13.4 ms during the night run. The FrameBuilder part is unchanged; the rest
    is the copy into `LowLevelMesh`, a plain memory copy inside RealityKit that compiler flags do
    not touch. The difference is simulator load, not the flag; only the device gives a reliable
    number.
  - Automatic size (D15): tesseract, 24-cell, Klein bottle and the stereographic 120-cell fill the
    volume; the 120-cell's outermost cells are cut by the volume, as intended. At 80 % fill the
    tesseract's lowest corner almost touched the floor disc, so the fill is now 75 %.
  - Flipped faces (D16): lit styles (Solid 24-cell, glossy Klein bottle) look right from the front
    in the simulator; the back and sides can only be checked on the device. The overlay's triangle
    count includes both copies of every face triangle.
  - Per-cell entities now use two meshes per cell (front copies, back copies), both with back-face
    culling, instead of one mesh drawn with front and back culling.
  - `onVolumeViewpointChange(updateStrategy: .all)` compiles. Whether it fires in a volume, and
    whether `.right` means the viewer stands at +x, can only be checked on the device; the
    Developer section shows the current side, and `-viewpoint` fixes it for snapshots.
- **2026-11-08, first device run (D19, D20):**
  - Installing from Xcode with the visionOS 27.0 SDK onto a headset running visionOS 27.2 worked;
    the first "Preparing device" took several minutes over Wi‑Fi.
  - The segmented `Picker` for the panel tabs highlighted on look but did not react to taps,
    while the `SelectButton`s in the same ornament did. Cause unknown (the ornament API is the new
    3D one with `Alignment3D`). All segmented pickers are now rows of `SelectButton`s. Sliders,
    toggles and menu pickers were not reachable yet and still need a device check.
  - The 0.8 m window looked small; now 1 m and resizable (D19). Axes layer added (D20).
- **2026-11-08, second device round (D21, D22):**
  - On the device there was no window bar and no resize corner. In the simulator the system's
    window bar sits right below the volume while the app loads, exactly where the panel's top edge
    was; once the panel appears, the bar is no longer there, so visionOS presumably moves it below
    the panel [verify on device]. The panel now starts 90 pt below the volume, which also keeps
    the volume's bottom corners (resize handles) uncovered.
  - Tabs and the Axes switch work on the device, so toggles (UIKit-backed) are fine; only the
    segmented picker failed.
  - `Info.plist` had a fixed version 1.0; it now takes `MARKETING_VERSION` (0.10.0) and
    `CURRENT_PROJECT_VERSION`.
  - Once in the simulator, with `-scale 1.4 -help about`, the volume's object appeared about 3×
    too large and unclipped. It did not happen again with either argument alone or in a second
    run. Unexplained; watch for it on the device.
- **2026-11-08, third device round (D23):**
  - Still no window bar and no resize corner on the device. Experiment in the simulator: with the
    panel on the volume's left side, the bar stays visible below the volume after loading; with
    the panel below, it disappears. So a bottom ornament hides the window controls.
  - "Sometimes dark and far away" with help open: reproduced in the simulator. visionOS restored
    the help `Window` at launch, placed it in front of the volume and pushed the volume back and
    dimmed it. The 3× object above was most likely the same rearrangement. The help is now an
    ornament, so there is only one window.
  - A `RealityView` inside an ornament shows nothing, so the live preview is gone; explaining an
    object shows it in the volume instead.
  - The volume's size is restored between launches (once 1360 × 1000 × 1360 pt, i.e.
    1 × 0.74 × 1 m); `defaultSize` only applies to a new window.
- **2026-11-08, Surface tab (D24):**
  - A `.color` vertex attribute in the `LowLevelMesh` has no effect on `PhysicallyBasedMaterial`
    (tested with normals as colours: the faces stayed uniform). Combining a colour source with a
    pattern would need a `ShaderGraphMaterial`.
  - Grid on a translucent tesseract: with additive blending the layers add up to white and the
    grid disappears; sorted shows it on every cell, with visible perspective foreshortening.
  - Marble reads as stone on the Klein bottle; wood still looks like corrugated cardboard (too
    much waviness for the repeat size). Metal reflects the room; thick faces turn cells into plates.
  - Thick faces have open rims; edges at least half the face thickness cover them. The Klein
    bottle's seam (orientation reversal) shows as a step in thick mode.
  - Colour × pattern with standard materials, second try: pattern as the ambient-occlusion map of
    `PhysicallyBasedMaterial`, pattern coordinates in a `.uv1` attribute. The map works (grid lines
    darken the faces) but reads `uv0`, not `uv1`, so it cannot be combined with the colour lookup
    in `uv0`. Reverted. Only a `ShaderGraphMaterial` (texture(uv0) × texture(uv1)) can combine both.
- **2026-11-08, panel windows (D25):**
  - Device: with the panel on the left the window bar and resize corners work; moving and
    resizing the volume confirmed by the user.
  - Simulator: `.leading(volume)` places the controls left of the volume, facing the viewer. A
    second window placed beside the volume (`.trailing`, or `.leading` when the controls took
    `.trailing`) was created (scene log) but not visible in the simulator's view. `.utilityPanel`
    shows the Info panel low in front of the viewer; the volume is not pushed back or dimmed.
  - Opening both windows in the same `onAppear` works.
- **2026-11-08, clipping margins (D27):** the simulator granted 47 cm on every side for the
  requested 50 cm (the first report is 0, before layout). A tesseract at Size 2 is drawn whole,
  far beyond the 1 m volume; at Size 4 it is cut at the margins.
- **2026-11-08, room, persistence, 600-cell (D28–D31):**
  - Room in the simulator: `openImmersiveSpace` returns `opened`; with the head anchor the object
    stands in front of the viewer with its floor disc, the volume is empty. Why the device button
    seemed to do nothing is still unknown; the result is now logged and shown.
  - Per-cell entities cost about 1 ms per cell per frame for the 600-cell (two `LowLevelMesh`
    updates per cell), so it stalled; see D31 for the numbers.
  - Saved settings load (a 24-cell at Size 0.8 written to the defaults came back without launch
    arguments). Saving after a change was not driven in the simulator.
- **2026-11-08, device round (D32–D34):** room opens and works; settings, 600-cell with explode
  fine. Exploded 600-cell in Metal is slow on the device but runs at 119 Hz with 1.2 ms CPU in the
  simulator, so the device's GPU is the limit (many overlapping reflective, translucent layers;
  explode doubles the faces and makes five times the edges). Not yet addressed; needs the
  device's overlay numbers.

## 9. Glossary

- **Cell:** a 3D boundary body of a 4D polytope. The tesseract has 8 cubes, the 120-cell 120
  dodecahedra.
- **Rotation plane:** in 4D you rotate in planes, not around axes. There are 6: XY, XZ, YZ, XW, YW,
  ZW.
- **Isoclinic (Clifford) rotation:** simultaneous rotation at equal speed in two perpendicular
  planes, e.g. XY and ZW. Every point moves on a great circle.
- **S³ (3-sphere):** the set of points in ℝ⁴ at distance 1 from the origin.
- **Stereographic projection:** projection of S³ from the north pole into 3D space. It preserves
  circles and angles.
- **Schlegel diagram:** a perspective image of a polytope in which one cell becomes the outer hull
  ("cube within a cube").
- **Duoprism p×q:** the product of a p-gon and a q-gon. The 4×4 duoprism is the tesseract.
- **Clifford torus:** a flat torus on S³. Projected stereographically it appears as an ordinary
  torus.
- **Hopf fibration:** a decomposition of S³ into great circles (fibres), any two of which are
  linked.
