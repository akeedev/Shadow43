// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Core4D
import SwiftUI

// Display names for the Core4D enums. All UI strings go through the String Catalog
// (Resources/Localizable.xcstrings).

extension ObjectID {
    var label: LocalizedStringKey {
        switch self {
        case .fiveCell: "5-cell"
        case .tesseract: "Tesseract"
        case .sixteenCell: "16-cell"
        case .twentyFourCell: "24-cell"
        case .oneTwentyCell: "120-cell"
        case .sixHundredCell: "600-cell"
        case .duoprism: "Duoprism"
        case .kleinBottle: "Klein bottle"
        case .cliffordTorus: "Clifford torus"
        case .hopfFibration: "Hopf fibration"
        }
    }
}

extension ObjectKind {
    var label: LocalizedStringKey {
        switch self {
        case .polytope: "Polytopes"
        case .surface: "Surfaces"
        case .curves: "Curves"
        }
    }
}

extension ProjectionPreset {
    var label: LocalizedStringKey {
        switch self {
        case .orthographic: "Orthographic"
        case .perspective: "Perspective"
        case .stereographic: "Stereographic"
        }
    }
}

extension DisplayPreset {
    var label: LocalizedStringKey {
        switch self {
        case .wireframe: "Wireframe"
        case .glass: "Glass"
        case .solid: "Solid"
        case .cells: "Cells"
        }
    }
}

extension MotionPreset {
    var label: LocalizedStringKey {
        switch self {
        case .simple: "Simple"
        case .double: "Double"
        case .isoclinic: "Isoclinic"
        case .drift: "Drift"
        }
    }
}

extension ColorSource {
    var label: LocalizedStringKey {
        switch self {
        case .uniform: "Uniform"
        case .byW: "By W"
        case .perCell: "Per cell"
        case .surfaceParameter: "Surface parameter"
        case .perFibre: "Per fibre"
        }
    }
}

extension FaceStyle {
    var label: LocalizedStringKey {
        switch self {
        case .matte: "Matte"
        case .glossy: "Glossy"
        case .glowing: "Glowing"
        case .metal: "Metal"
        case .ceramic: "Ceramic"
        case .frostedGlass: "Frosted glass"
        }
    }
}

extension SurfacePattern {
    var label: LocalizedStringKey {
        switch self {
        case .none: "None"
        case .grid: "Grid"
        case .marble: "Marble"
        case .wood: "Wood"
        }
    }
}

extension EdgeColorMode {
    var label: LocalizedStringKey {
        switch self {
        case .matchFaces: "Same as faces"
        case .light: "Plain light"
        }
    }
}

extension TransparencyMethod {
    var label: LocalizedStringKey {
        switch self {
        case .additive: "Additive"
        case .sorted: "Sorted"
        case .perCellEntities: "Per-cell entities"
        }
    }
}

extension FloorShadowMethod {
    var label: LocalizedStringKey {
        switch self {
        case .directionalLight: "Directional light"
        case .grounding: "Grounding shadow"
        }
    }
}

extension ViewSide {
    var label: LocalizedStringKey {
        switch self {
        case .front: "Front"
        case .right: "Right"
        case .back: "Back"
        case .left: "Left"
        }
    }
}

extension RotationPlane {
    var label: LocalizedStringKey {
        switch self {
        case .xy: "XY"
        case .xz: "XZ"
        case .yz: "YZ"
        case .xw: "XW"
        case .yw: "YW"
        case .zw: "ZW"
        }
    }
}

extension PanelTab {
    var label: LocalizedStringKey {
        switch self {
        case .object: "Object"
        case .projection: "Projection"
        case .display: "Display"
        case .surface: "Surface"
        case .motion: "Motion"
        case .developer: "Developer"
        }
    }
}
