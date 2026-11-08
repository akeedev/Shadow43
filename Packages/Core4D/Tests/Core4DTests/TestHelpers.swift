// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Largest absolute element-wise difference of two 4×4 matrices.
func maxAbsDifference(_ a: simd_double4x4, _ b: simd_double4x4) -> Double {
    var m = 0.0
    for c in 0..<4 {
        for r in 0..<4 { m = max(m, abs(a[c][r] - b[c][r])) }
    }
    return m
}

/// Largest absolute element of a vector.
func maxAbs(_ v: SIMD4<Double>) -> Double {
    max(max(abs(v.x), abs(v.y)), max(abs(v.z), abs(v.w)))
}
