// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import SwiftUI

/// Everything the help window can explain (D22): the About page, each tab, and each control.
/// All texts go through the String Catalog.
enum HelpTopic: Hashable {
    case about
    case tab(PanelTab)
    case object(ObjectID)
    case duoprismParameters
    case projectionPreset(ProjectionPreset)
    case kappa, spherize
    case displayPreset(DisplayPreset)
    case edges, floorShadow, axes, edgeThickness, faceOpacity, colorSource, faceStyle, explode, size
    case pattern, faceThickness
    case motionPreset(MotionPreset)
    case stop, reset, friction, planeSpeed
    case transparency, floorShadowMethod, dragMapping, performanceOverlay, gestureTest, freezeTime
    case fineSubdivision, viewerSide, room
    case resetAll

    /// The `-help` launch argument: `about`, a tab (`projection`) or an object (`tesseract`).
    init?(launchValue: String) {
        if launchValue == "about" {
            self = .about
        } else if let tab = PanelTab(rawValue: launchValue) {
            self = .tab(tab)
        } else if let id = ObjectID(rawValue: launchValue) {
            self = .object(id)
        } else {
            return nil
        }
    }

    /// The object this topic explains, if any; it is shown in the volume while explained.
    var explainedObject: ObjectID? {
        if case .object(let id) = self { return id }
        return nil
    }

    var title: LocalizedStringKey {
        switch self {
        case .about: "About Shadow43"
        case .tab(let tab): tab.label
        case .object(let id): id.label
        case .duoprismParameters: "p and q"
        case .projectionPreset(let p): p.label
        case .kappa: "Perspective κ"
        case .spherize: "Spherize s"
        case .displayPreset(let p): p.label
        case .edges: "Edges"
        case .floorShadow: "Floor shadow"
        case .axes: "Axes"
        case .edgeThickness: "Edge thickness"
        case .faceOpacity: "Face opacity"
        case .colorSource: "Colour"
        case .faceStyle: "Material"
        case .pattern: "Pattern"
        case .faceThickness: "Thickness"
        case .explode: "Explode"
        case .size: "Size"
        case .motionPreset(let p): p.label
        case .stop: "Stop"
        case .reset: "Reset"
        case .friction: "Friction"
        case .planeSpeed: "Speed per plane"
        case .transparency: "Transparency (S1)"
        case .floorShadowMethod: "Floor shadow (S4)"
        case .dragMapping: "Drag k and Invert drag"
        case .performanceOverlay: "Performance overlay (S2)"
        case .gestureTest: "Gesture test (S3)"
        case .freezeTime: "Freeze time"
        case .fineSubdivision: "Fine subdivision"
        case .viewerSide: "Viewer side"
        case .room: "Open in room"
        case .resetAll: "Reset all"
        }
    }

    // Texts use inline Markdown (bold, italic); paragraphs are separated by blank lines.
    var text: LocalizedStringKey {
        switch self {
        case .about:
            ""
        case .tab(.object):
            "Choose what to look at. *Polytopes* are the 4D relatives of the Platonic solids, built from 3D cells. *Surfaces* are 2D sheets that live in 4D. *Curves* are families of circles in 4D.\n\nEvery object is centred and scaled to radius 1, and the app sizes it to fill the window."
        case .tab(.projection):
            "A 4D object cannot be shown directly; the app shows its 3D shadow. The projection decides how the fourth coordinate, w, is turned into 3D.\n\nThe three presets are points in the space of the two sliders, so you can morph smoothly from one to another."
        case .tab(.display):
            "How the shadow is drawn: edges, faces, colours, cells, and extras such as the floor shadow and the axes. A preset sets several of these at once; you can change each one afterwards.\n\n*Open in room* shows the object at room size."
        case .tab(.surface):
            "How the faces themselves look: their material, an image pattern on them, and their thickness. These looks are experimental."
        case .tab(.motion):
            "In 4D an object turns in planes, not around axes, and there are six of them. XY, XZ and YZ turn the shadow like an ordinary 3D object. XW, YW and ZW turn the object into the fourth dimension: the shadow changes its shape.\n\nThe presets set the speeds, the sliders set each plane's speed, and you can also throw the object with your hand."
        case .tab(.developer):
            "Tools for testing and tuning: rendering methods and measurements. These settings may change or disappear in later versions."
        case .object(.fiveCell):
            "**5-cell** (pentachoron, 4-simplex)\n\nThe simplest 4D polytope and the 4D relative of the tetrahedron: 5 vertices, each joined to all the others. 10 edges, 10 triangles, 5 tetrahedral cells.\n\nIts shadow often looks like a tetrahedron with a fifth point inside. As it turns in 4D, that point moves out and another vertex moves in."
        case .object(.tesseract):
            "**Tesseract** (8-cell, hypercube)\n\nThe 4D cube: 16 vertices, 32 edges, 24 squares and 8 cubic cells. A cube is two squares joined at their corners; a tesseract is two cubes joined at their corners.\n\nIn perspective you see the famous cube inside a cube: the large cube is the cell nearer to the eye in w, the small one the cell farther away, and the six cells in between look like truncated pyramids. Rotate in XW, YW or ZW and the cubes turn inside out through each other."
        case .object(.sixteenCell):
            "**16-cell** (hyperoctahedron)\n\nThe 4D relative of the octahedron: 8 vertices, two on each axis. Every vertex is joined to all others except its opposite: 24 edges, 32 triangles, 16 tetrahedral cells.\n\nIt is the dual of the tesseract: its vertices point to the centres of the tesseract's cells."
        case .object(.twentyFourCell):
            "**24-cell**\n\nA regular polytope with no 3D counterpart: 24 vertices, 96 edges, 96 triangles and 24 octahedral cells. It is its own dual, and copies of it fill 4D space without gaps, as cubes fill 3D space."
        case .object(.oneTwentyCell):
            "**120-cell**\n\nThe 4D relative of the dodecahedron: 120 dodecahedral cells, 720 pentagons, 1200 edges and 600 vertices.\n\nIn the stereographic projection it becomes a foam of soap bubbles: every bubble is one of its dodecahedral cells."
        case .object(.sixHundredCell):
            "**600-cell**\n\nThe 4D relative of the icosahedron: 600 tetrahedral cells, 1200 triangles, 720 edges and 120 vertices. It is the dual of the 120-cell."
        case .object(.duoprism):
            "**Duoprism p × q**\n\nThe product of a p-gon and a q-gon: a p-gon in the xy-plane and a q-gon in the zw-plane, every point of one combined with every point of the other. It has p·q vertices and p + q cells: p prisms over the q-gon and q prisms over the p-gon, arranged in two rings that pass through each other.\n\nThe 4 × 4 duoprism is the tesseract. For large p and q it approaches the duocylinder. Set p and q below the object buttons."
        case .object(.kleinBottle):
            "**Klein bottle**\n\nA closed surface with only one side: there is no inside and no outside. In 3D a Klein bottle must pass through itself. In 4D it does not: where its shadow seems to cut through itself, the two sheets are at different w and pass each other.\n\nColour *By W* shows this: at a crossing, the two sheets have different colours."
        case .object(.cliffordTorus):
            "**Clifford torus**\n\nThe points (cos u, sin u, cos v, sin v) / √2: a torus on the 3-sphere, all of whose points are equally far from the centre. It is completely flat: it can be made from a sheet of paper without stretching, which is impossible in 3D.\n\nRotations in XY and ZW map it onto itself, so under the *Double* and *Isoclinic* motions it slides along itself and its shadow keeps its shape. In the stereographic projection it looks like an ordinary ring."
        case .object(.hopfFibration):
            "**Hopf fibration**\n\nThe 3-sphere, the set of points at distance 1 from the centre in 4D, can be filled completely with great circles that never meet, and any two of them are linked like chain links. These circles are the fibres of the Hopf fibration; each one belongs to one point of the ordinary 2-sphere.\n\nThe app shows a selection of fibres. In the stereographic projection they become linked circles lying on nested tori. Colour *Per fibre* gives each circle its own colour."
        case .duoprismParameters:
            "The number of sides of the two polygons whose product is the duoprism. p = q = 4 gives the tesseract; larger values look more and more like the duocylinder."
        case .projectionPreset(.orthographic):
            "κ = 0, s = 0.\n\nThe simplest shadow: the w coordinate is just dropped, like a shadow cast by the sun. Parallel edges stay parallel, and nothing is enlarged or shrunk."
        case .projectionPreset(.perspective):
            "κ = 0.6, s = 0.\n\nLike a photograph taken from a point in 4D: parts nearer the eye along w look bigger, parts farther away smaller. This gives the classic cube inside a cube."
        case .projectionPreset(.stereographic):
            "κ = 1, s = 1.\n\nThe object is first inflated onto the 3-sphere, then projected from a point on that sphere. Angles are kept, edges become circular arcs, and cells near the projection point grow huge. The 120-cell becomes the soap-bubble picture."
        case .kappa:
            "How strongly w turns into size: a point is shown at (x, y, z) / (1 − κ·w). κ = 0 is orthographic; κ = 1 puts the eye on the unit sphere.\n\nPoints with w = 0 never move, so the picture does not jump while you drag. Parts at or behind the eye are left out."
        case .spherize:
            "Blends each point between its flat position (s = 0) and its position pushed out onto the 3-sphere (s = 1); straight edges bulge into arcs. Together with κ = 1 this gives the stereographic projection."
        case .displayPreset(.wireframe):
            "Edges only, no faces. Best for following single edges and vertices."
        case .displayPreset(.glass):
            "Edges plus transparent, softly glowing faces. Shows inside and outside at once."
        case .displayPreset(.solid):
            "Opaque faces with thin edges, lit by your room. You only see the outermost cells."
        case .displayPreset(.cells):
            "Every cell shrinks a little towards its centre and gets its own colour, so the cells come apart. Polytopes only."
        case .edges:
            "Shows the edges as thin tubes. *Same as faces* colours them like the faces; *Plain light* draws all of them in one light colour."
        case .floorShadow:
            "A light above the object casts the shadow of the 3D shadow onto the disc below: 4D → 3D → 2D in one picture."
        case .axes:
            "The object's own four axes from −1 to +1: x red, y green, z blue, w yellow. They rotate and are projected together with the object.\n\nAt the start, w is only a point at the centre: it is the direction the projection removes. Turn the object into w (drag sideways, or the *Simple* motion) and the w axis grows while another axis shrinks."
        case .edgeThickness:
            "Radius of the edge tubes, relative to the object's size."
        case .faceOpacity:
            "0 % hides the faces, 100 % makes them opaque. In between you can see through them."
        case .colorSource:
            "• *Uniform*: one colour.\n• *By W*: blue where w is negative, red where it is positive. The most helpful aid of all: it shows what lies \"in front\" in 4D.\n• *Per cell*: every cell its own colour (polytopes; opens a small gap between the cells).\n• *Surface parameter*: a checkerboard in the surface's own coordinates.\n• *Per fibre*: every Hopf circle its own colour."
        case .faceStyle:
            "How the faces look. *Matte* and *Glossy* are lit by your room; glossy adds highlights. *Glowing* ignores the light and shines in its own colour, which suits transparent faces.\n\nExperimental: *Metal* reflects your room, *Ceramic* is a glazed surface, *Frosted glass* is rough and half transparent (it sets the face opacity to 50 % if the faces were opaque)."
        case .pattern:
            "An image on every face: *Grid*, *Marble* or *Wood*. It is fixed to the face in 4D, so the projection distorts it — in the perspective and stereographic views you can see how each face is stretched.\n\nOn polytopes a grid square is a quarter of a tesseract edge; on surfaces the pattern follows the surface's own coordinates. For now a pattern replaces the colour on the faces; the edges keep it."
        case .faceThickness:
            "Gives every face a real thickness, so thin films become slabs and the surfaces become solid sheets. The thickness is relative to the object's size.\n\nWith thick faces, turn on the edges and make them at least as thick as half the face thickness, so the open rims are covered."
        case .explode:
            "Shrinks every cell towards its own centre, so gaps open between the cells. Polytopes only."
        case .size:
            "A factor on top of the automatic size, which fills about three quarters of the window. Pinching with both hands does the same. Enlarged objects rise so they do not sink into the floor disc.\n\nTo see more, make the window itself bigger: drag one of its bottom corners."
        case .motionPreset(.simple):
            "One rotation in the XW plane. The object turns into the fourth dimension and back, and its shadow turns inside out again and again."
        case .motionPreset(.double):
            "XY and ZW at different speeds: two independent rotations at once. That is only possible in 4D, because the two planes share no axis."
        case .motionPreset(.isoclinic):
            "XY and ZW at the same speed, a Clifford rotation. Every point of the object moves on a great circle at the same speed; no point stays still. Nothing like it exists in 3D."
        case .motionPreset(.drift):
            "All six planes, slow and at different speeds, so the view keeps changing."
        case .stop:
            "Sets all speeds to zero. Pinching and holding the object does the same."
        case .reset:
            "Turns the object back to its start position, a slight 3D tilt. A double tap on the object does the same. The speeds stay."
        case .friction:
            "Slows the rotation down until it stops. 0 keeps it turning forever."
        case .planeSpeed:
            "Speed in each rotation plane, in radians per second. XY, XZ and YZ turn the shadow like a 3D object. XW, YW and ZW turn the object into the fourth dimension and change the shadow's shape. A throw with your hand sets these speeds too."
        case .transparency:
            "How see-through faces are drawn. *Additive* adds the colours up: no sorting, but it can look washed out. *Sorted* sorts all triangles from back to front, seen from the side of the window you are on. *Per-cell entities* gives every cell its own entity and lets RealityKit sort them; it needs Explode above 0 and is used only up to 48 cells; the 120-cell and the 600-cell use Sorted instead, because so many entities stall the app."
        case .floorShadowMethod:
            "*Directional light* casts a real shadow from a light above. *Grounding shadow* is the system's soft contact shadow."
        case .dragMapping:
            "How far a hand drag turns the object in 4D, in radians per metre of hand movement, and in which direction."
        case .performanceOverlay:
            "Shows frame time, CPU time per frame and the number of triangles above the window."
        case .gestureTest:
            "Shows the raw values of the hand gestures beside the window, for tuning."
        case .freezeTime:
            "Stops the clock: the object holds still but keeps its speeds."
        case .fineSubdivision:
            "Draws many more triangles than needed, to test the frame rate under load."
        case .viewerSide:
            "Which side of the window you are on, as reported by visionOS. *Sorted* transparency sorts towards that side."
        case .room:
            "Shows the object at room size in front of you, in an immersive space; the window stays empty meanwhile. The object stands level, even if you tilt your head while opening the room. To move it through the room, pinch the disc below it and drag. Other apps' windows are hidden while the room is open."
        case .resetAll:
            "Puts every setting back to its default: object, projection, display, motion, size, orientation and the developer settings. Tap it twice to confirm."
        }
    }
}
