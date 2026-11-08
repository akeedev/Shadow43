// Copyright 2026 Andreas Keese. Licensed under the Apache License, Version 2.0.

import Foundation
import simd
import Testing
@testable import Core4D

/// Built once per test process; the 120- and 600-cell take a moment.
enum Fixtures {
    static let fiveCell = Polytopes.fiveCell()
    static let tesseract = Polytopes.tesseract()
    static let sixteenCell = Polytopes.sixteenCell()
    static let twentyFourCell = Polytopes.twentyFourCell()
    static let sixHundredCell = Polytopes.sixHundredCell()
    static let oneTwentyCell = Polytopes.oneTwentyCell()

    static func regular(_ name: String) -> Complex4D {
        switch name {
        case "5-cell": fiveCell
        case "tesseract": tesseract
        case "16-cell": sixteenCell
        case "24-cell": twentyFourCell
        case "600-cell": sixHundredCell
        case "120-cell": oneTwentyCell
        default: fatalError("unknown fixture \(name)")
        }
    }
}

@Suite("Polytope generator")
struct PolytopeTests {
    static let expected: [(String, [Int])] = [
        ("5-cell", [5, 10, 10, 5]),
        ("tesseract", [16, 32, 24, 8]),
        ("16-cell", [8, 24, 32, 16]),
        ("24-cell", [24, 96, 96, 24]),
        ("600-cell", [120, 720, 1200, 600]),
        ("120-cell", [600, 1200, 720, 120]),
    ]
    static let regularNames = expected.map(\.0)

    @Test(arguments: expected)
    func fVector(_ entry: (String, [Int])) {
        #expect(Fixtures.regular(entry.0).fVector == entry.1)
    }

    @Test(arguments: [(3, 3), (3, 4), (4, 4), (5, 7), (3, 12)])
    func duoprismFVector(_ pq: (Int, Int)) {
        let (p, q) = pq
        let c = Polytopes.duoprism(p: p, q: q)
        #expect(c.fVector == [p * q, 2 * p * q, p * q + p + q, p + q])
        #expect(c.eulerCharacteristic == 0)
        checkStructure(c)
    }

    @Test(arguments: regularNames)
    func eulerCharacteristicIsZero(_ name: String) {
        #expect(Fixtures.regular(name).eulerCharacteristic == 0)
    }

    @Test(arguments: regularNames)
    func structure(_ name: String) {
        checkStructure(Fixtures.regular(name))
    }

    @Test(arguments: regularNames)
    func regularPolytopesHaveEqualEdgesAndUnitCircumradius(_ name: String) {
        let c = Fixtures.regular(name)
        let lengths = c.edges.map { simd_distance(c.vertices[$0[0]], c.vertices[$0[1]]) }
        let minL = lengths.min()!, maxL = lengths.max()!
        #expect(maxL - minL < 1e-9, "edge lengths of \(name) vary: \(minL)…\(maxL)")
        for v in c.vertices { #expect(abs(simd_length(v) - 1) < 1e-9) }
    }

    @Test func facesArePlanarAndCyclicallyOrdered() {
        let c = Fixtures.twentyFourCell
        for f in c.faces {
            // Consecutive vertices of a regular polygon are joined by edges of the complex.
            let vs = f.vertices
            let edgeSet = Set(c.edges.map { EdgeKey($0[0], $0[1]) })
            for i in vs.indices {
                #expect(edgeSet.contains(EdgeKey(vs[i], vs[(i + 1) % vs.count])))
            }
            #expect(PolytopeGenerator.affineDimension(vs.map { c.vertices[$0] }, tolerance: 1e-9) == 2)
        }
    }

    @Test func tesseractCellsAreCubes() {
        let c = Fixtures.tesseract
        for i in c.cells.indices {
            #expect(c.cells[i].faces.count == 6)
            #expect(c.vertexIndices(ofCell: i).count == 8)
            #expect(c.edgePairs(ofCell: i).count == 12)
        }
    }

    @Test func sixHundredCellBootstrapGivesSixHundredCentres() {
        let v = Polytopes.sixHundredCellVertices()
        #expect(v.count == 120)
        #expect(Polytopes.sixHundredCellCellCentres(v).count == 600)
    }

    @Test func permutationHelpers() {
        #expect(Polytopes.allPermutations(of: 4).count == 24)
        #expect(Polytopes.evenPermutations(of: 4).count == 12)
        #expect(Polytopes.signCombinations([1, 0, 1, 0]).count == 4)
        #expect(Polytopes.permutations([1, 1, 0, 0]).count == 6)
    }

    @Test func normalizationCentresAndScales() {
        let points: [SIMD4<Double>] = [[2, 2, 2, 2], [4, 2, 2, 2], [3, 3, 2, 2]]
        let n = normalizeToUnitCircumradius(points)
        let centroid = n.reduce(SIMD4<Double>.zero, +) / 3
        #expect(maxAbs(centroid) < 1e-12)
        #expect(abs((n.map { simd_length($0) }.max() ?? 0) - 1) < 1e-12)
    }

    /// Every face belongs to exactly 2 cells; every edge of a cell lies in exactly 2 of its faces.
    func checkStructure(_ c: Complex4D) {
        for f in c.faces {
            #expect(f.cells.count == 2)
            #expect(Set(f.cells).count == 2)
        }
        var cellsPerFace = [Int](repeating: 0, count: c.faces.count)
        for cell in c.cells {
            for f in cell.faces { cellsPerFace[f] += 1 }
        }
        #expect(cellsPerFace.allSatisfy { $0 == 2 })
        for ci in c.cells.indices {
            var count: [EdgeKey: Int] = [:]
            for f in c.cells[ci].faces {
                let vs = c.faces[f].vertices
                for i in vs.indices { count[EdgeKey(vs[i], vs[(i + 1) % vs.count]), default: 0] += 1 }
            }
            #expect(count.values.allSatisfy { $0 == 2 }, "cell \(ci) has an edge not in exactly 2 faces")
        }
    }
}
