import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

@Suite("Solids, traces and 3D faces against AutoCAD's DXF")
struct SurfacesTests {
    /// The four corners of a DXF `SOLID`, `TRACE` or `3DFACE`, from groups 10 to 13.
    static func corners(of record: DXFRecord) -> [DXF.Point] {
        [(10, 20, 30), (11, 21, 31), (12, 22, 32), (13, 23, 33)].compactMap {
            CurveOracle.point(record, $0.0, $0.1, $0.2)
        }
    }

    static func solidMatches(_ s: SolidData, _ r: DXFRecord) -> Bool {
        let expected = corners(of: r)
        return expected.count == 4 && CurveOracle.near(s.corners, expected)
            && CurveOracle.near(s.thickness, r.double(39) ?? 0)
            && CurveOracle.near(
                s.extrusion, CurveOracle.point(r, 210, 220, 230) ?? DXF.Point(0, 0, 1))
            && s.corners.allSatisfy { CurveOracle.near($0.z, s.elevation) }
    }

    @Test("solids equal the DXF's, with the same count")
    func solids() throws {
        for sample in try CurveOracle.samples() {
            let tally = try CurveOracle.tally(
                sample, dxfType: "SOLID",
                pick: { geometry -> SolidData? in
                    if case .solid(let data) = geometry, !data.isTrace { return data }
                    return nil
                },
                matches: { s, r in SurfacesTests.solidMatches(s, r) })
            #expect(tally.mismatches.isEmpty, "\(sample.name)")
            #expect(tally.decoded == tally.expected, "\(sample.name)")
            #expect(
                tally.decoded == (sample.name == "BLOCKPOINTPARAMETER" ? 0 : 14), "\(sample.name)")
        }
    }

    /// Compares traces, of which no sample drawing has one yet.
    ///
    /// The counts are 0 on both sides, so this compares nothing today. It is here for the day a
    /// sample has one.
    @Test("traces equal the DXF's when a sample has them")
    func traces() throws {
        for sample in try CurveOracle.samples() {
            let tally = try CurveOracle.tally(
                sample, dxfType: "TRACE",
                pick: { geometry -> SolidData? in
                    if case .solid(let data) = geometry, data.isTrace { return data }
                    return nil
                },
                matches: { s, r in SurfacesTests.solidMatches(s, r) })
            #expect(tally.mismatches.isEmpty, "\(sample.name)")
            #expect(tally.decoded == tally.expected, "\(sample.name)")
            #expect(tally.decoded == 0, "\(sample.name): a sample now has traces")
        }
    }

    @Test("3D faces equal the DXF's, with the same count")
    func faces() throws {
        for sample in try CurveOracle.samples() {
            let tally = try CurveOracle.tally(
                sample, dxfType: "3DFACE",
                pick: { geometry -> Face3DData? in
                    if case .face3D(let data) = geometry { return data }
                    return nil
                },
                matches: { f, r in
                    let expected = SurfacesTests.corners(of: r)
                    return expected.count == 4 && CurveOracle.near(f.corners, expected)
                        && f.invisibleEdges == (r.int(70) ?? 0)
                })
            #expect(tally.mismatches.isEmpty, "\(sample.name)")
            #expect(tally.decoded == tally.expected, "\(sample.name)")
            #expect(
                tally.decoded == (sample.name == "BLOCKPOINTPARAMETER" ? 0 : 1), "\(sample.name)")
        }
    }
}
