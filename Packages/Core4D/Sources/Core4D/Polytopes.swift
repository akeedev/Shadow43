// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd

/// Inputs for the polytope generator (DESIGN 6.6, table "Inputs").
public enum Polytopes {
    public static let goldenRatio = (1 + sqrt(5.0)) / 2

    /// 5-cell (regular simplex), f-vector (5, 10, 10, 5).
    public static func fiveCell() -> Complex4D {
        let a = 1 / sqrt(5.0)
        let vertices: [SIMD4<Double>] = [
            [1, 1, 1, -a], [1, -1, -1, -a], [-1, 1, -1, -a], [-1, -1, 1, -a], [0, 0, 0, 4 * a],
        ]
        return PolytopeGenerator.complex(vertices: vertices, normals: vertices.map { -$0 })
    }

    /// Tesseract (8-cell), f-vector (16, 32, 24, 8).
    public static func tesseract() -> Complex4D {
        PolytopeGenerator.complex(vertices: signCombinations([1, 1, 1, 1]), normals: unitAxes())
    }

    /// 16-cell, f-vector (8, 24, 32, 16).
    public static func sixteenCell() -> Complex4D {
        PolytopeGenerator.complex(vertices: unitAxes(), normals: signCombinations([1, 1, 1, 1]))
    }

    /// 24-cell, f-vector (24, 96, 96, 24).
    public static func twentyFourCell() -> Complex4D {
        let vertices = uniquePoints(permutations([1, 1, 0, 0]).flatMap { signCombinations($0) })
        let normals = unitAxes() + signCombinations([0.5, 0.5, 0.5, 0.5])
        return PolytopeGenerator.complex(vertices: vertices, normals: normals)
    }

    /// 600-cell, f-vector (120, 720, 1200, 600). Normals come from the bootstrap.
    public static func sixHundredCell() -> Complex4D {
        let vertices = sixHundredCellVertices()
        return PolytopeGenerator.complex(vertices: vertices, normals: sixHundredCellCellCentres(vertices))
    }

    /// 120-cell, f-vector (600, 1200, 720, 120): its vertices are the normalised cell centres of
    /// the 600-cell, its normals the vertices of the 600-cell.
    public static func oneTwentyCell() -> Complex4D {
        let v600 = sixHundredCellVertices()
        return PolytopeGenerator.complex(vertices: sixHundredCellCellCentres(v600), normals: v600)
    }

    /// Duoprism p×q, the product of a p-gon and a q-gon; f-vector (pq, 2pq, pq + p + q, p + q).
    public static func duoprism(p: Int, q: Int) -> Complex4D {
        var vertices: [SIMD4<Double>] = []
        for i in 0..<p {
            for j in 0..<q {
                let a = 2 * Double.pi * Double(i) / Double(p)
                let b = 2 * Double.pi * Double(j) / Double(q)
                vertices.append([cos(a), sin(a), cos(b), sin(b)])
            }
        }
        var normals: [SIMD4<Double>] = []
        for i in 0..<p {
            let a = 2 * Double.pi * (Double(i) + 0.5) / Double(p)
            normals.append([cos(a), sin(a), 0, 0])
        }
        for j in 0..<q {
            let b = 2 * Double.pi * (Double(j) + 0.5) / Double(q)
            normals.append([0, 0, cos(b), sin(b)])
        }
        return PolytopeGenerator.complex(vertices: vertices, normals: normals)
    }

    // MARK: - 600-cell bootstrap

    /// The 120 vertices of the 600-cell: permutations of (±1, 0, 0, 0), (±½, ±½, ±½, ±½) and
    /// the even permutations of ½(±φ, ±1, ±1/φ, 0).
    public static func sixHundredCellVertices() -> [SIMD4<Double>] {
        let phi = goldenRatio
        var points = unitAxes() + signCombinations([0.5, 0.5, 0.5, 0.5])
        let base: [Double] = [phi / 2, 0.5, 1 / (2 * phi), 0]
        for perm in evenPermutations(of: 4) {
            let permuted = SIMD4<Double>(base[perm[0]], base[perm[1]], base[perm[2]], base[perm[3]])
            points += signCombinations(permuted)
        }
        return uniquePoints(points)
    }

    /// The normalised centroids of the 600-cell's tetrahedra: its edges are the vertex pairs at
    /// minimal distance, its cells the 4-cliques of this edge graph.
    public static func sixHundredCellCellCentres(_ vertices: [SIMD4<Double>]) -> [SIMD4<Double>] {
        let n = vertices.count
        var minDistance = Double.infinity
        for i in 0..<n {
            for j in (i + 1)..<n { minDistance = min(minDistance, simd_distance(vertices[i], vertices[j])) }
        }
        var adjacent = [Set<Int>](repeating: [], count: n)
        for i in 0..<n {
            for j in (i + 1)..<n where simd_distance(vertices[i], vertices[j]) < minDistance * (1 + 1e-6) {
                adjacent[i].insert(j)
                adjacent[j].insert(i)
            }
        }
        var centres: [SIMD4<Double>] = []
        for a in 0..<n {
            for b in adjacent[a] where b > a {
                for c in adjacent[a].intersection(adjacent[b]) where c > b {
                    for d in adjacent[a].intersection(adjacent[b]).intersection(adjacent[c]) where d > c {
                        let centroid = (vertices[a] + vertices[b] + vertices[c] + vertices[d]) / 4
                        centres.append(simd_normalize(centroid))
                    }
                }
            }
        }
        return centres
    }

    // MARK: - Helpers

    /// ±e_i.
    static func unitAxes() -> [SIMD4<Double>] {
        (0..<4).flatMap { i -> [SIMD4<Double>] in
            let e = Rotation4D.axis(i)
            return [e, -e]
        }
    }

    /// All sign combinations of the non-zero coordinates.
    static func signCombinations(_ v: SIMD4<Double>) -> [SIMD4<Double>] {
        var result: [SIMD4<Double>] = [v]
        for i in 0..<4 where v[i] != 0 {
            result += result.map { p in
                var q = p
                q[i] = -q[i]
                return q
            }
        }
        return result
    }

    /// All distinct permutations of the coordinates.
    static func permutations(_ v: SIMD4<Double>) -> [SIMD4<Double>] {
        uniquePoints(allPermutations(of: 4).map { SIMD4(v[$0[0]], v[$0[1]], v[$0[2]], v[$0[3]]) })
    }

    static func allPermutations(of n: Int) -> [[Int]] {
        guard n > 1 else { return [[0]] }
        return allPermutations(of: n - 1).flatMap { perm in
            (0...perm.count).map { i in
                var p = perm
                p.insert(n - 1, at: i)
                return p
            }
        }
    }

    static func evenPermutations(of n: Int) -> [[Int]] {
        allPermutations(of: n).filter { perm in
            var inversions = 0
            for i in 0..<perm.count {
                for j in (i + 1)..<perm.count where perm[i] > perm[j] { inversions += 1 }
            }
            return inversions % 2 == 0
        }
    }

    /// Removes duplicates (exact after rounding to 1e-9).
    static func uniquePoints(_ points: [SIMD4<Double>]) -> [SIMD4<Double>] {
        var seen = Set<SIMD4<Int64>>()
        return points.filter { p in
            let key = SIMD4<Int64>((p * 1e9).rounded(.toNearestOrEven))
            return seen.insert(key).inserted
        }
    }
}
