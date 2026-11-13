import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

@Suite("Polylines against AutoCAD's DXF")
struct PolylinesTests {
    // MARK: LWPOLYLINE

    /// A vertex of a DXF `LWPOLYLINE`, from the groups after the count.
    struct DXFVertex {
        var x = 0.0
        var y = 0.0
        var startWidth = 0.0
        var endWidth = 0.0
        var bulge = 0.0
        var id = 0
    }

    /// The vertices of a DXF `LWPOLYLINE`: group 10 starts one, and 20, 40, 41, 42 and 91 fill it.
    static func vertices(of record: DXFRecord) -> [DXFVertex] {
        var out: [DXFVertex] = []
        for (code, value) in record.groups {
            if code == 10 { out.append(DXFVertex(x: Double(value) ?? .nan)) }
            guard !out.isEmpty else { continue }
            switch code {
            case 20: out[out.count - 1].y = Double(value) ?? .nan
            case 40: out[out.count - 1].startWidth = Double(value) ?? .nan
            case 41: out[out.count - 1].endWidth = Double(value) ?? .nan
            case 42: out[out.count - 1].bulge = Double(value) ?? .nan
            case 91: out[out.count - 1].id = Int(value) ?? -1
            default: break
            }
        }
        return out
    }

    static func lwMatches(_ p: LWPolylineData, _ r: DXFRecord) -> Bool {
        let flags = (p.isClosed ? 1 : 0) | (p.hasLineTypeGeneration ? 128 : 0)
        let expected = vertices(of: r)
        guard (r.int(70) ?? 0) == flags, p.points.count == r.int(90),
            p.points.count == expected.count,
            CurveOracle.near(p.constantWidth, r.double(43) ?? 0),
            CurveOracle.near(p.elevation, r.double(38) ?? 0),
            CurveOracle.near(p.thickness, r.double(39) ?? 0),
            CurveOracle.near(p.extrusion, CurveOracle.point(r, 210, 220, 230) ?? DXF.Point(0, 0, 1))
        else { return false }
        for (index, vertex) in expected.enumerated() {
            let bulge = index < p.bulges.count ? p.bulges[index] : 0
            let id = index < p.vertexIDs.count ? p.vertexIDs[index] : 0
            let width =
                index < p.widths.count ? p.widths[index] : LWPolylineData.Width(start: 0, end: 0)
            guard CurveOracle.near(p.points[index].x, vertex.x),
                CurveOracle.near(p.points[index].y, vertex.y),
                CurveOracle.near(bulge, vertex.bulge), id == vertex.id,
                CurveOracle.near(width.start, vertex.startWidth),
                CurveOracle.near(width.end, vertex.endWidth)
            else { return false }
        }
        return true
    }

    @Test("lightweight polylines equal the DXF's, with the same count")
    func lightweightPolylines() throws {
        for sample in try CurveOracle.samples() {
            let tally = try CurveOracle.tally(
                sample, dxfType: "LWPOLYLINE",
                pick: { geometry -> LWPolylineData? in
                    if case .lwpolyline(let data) = geometry { return data }
                    return nil
                },
                matches: { p, r in PolylinesTests.lwMatches(p, r) })
            #expect(tally.mismatches.isEmpty, "\(sample.name)")
            #expect(tally.decoded == tally.expected, "\(sample.name)")
            #expect(
                tally.decoded == (sample.name == "BLOCKPOINTPARAMETER" ? 0 : 23), "\(sample.name)")
        }
    }

    @Test("lightweight polylines of three more R2018 drawings equal the DXF's")
    func lightweightPolylinesInDynamicBlocks() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        let folder = corpus.appendingPathComponent("dynamic-blocks")
        for (name, count) in [
            ("BLOCKVISIBILITYPARAMETER", 22), ("BLOCKLOOKUPPARAMETER", 21),
            ("BLOCKFLIPPARAMETER", 3),
        ] {
            let sample = try CurveOracle.sample(
                name: name, dwg: folder.appendingPathComponent("\(name).dwg"),
                dxf: folder.appendingPathComponent("\(name).dxf"))
            let tally = try CurveOracle.tally(
                sample, dxfType: "LWPOLYLINE",
                pick: { geometry -> LWPolylineData? in
                    if case .lwpolyline(let data) = geometry { return data }
                    return nil
                },
                matches: { p, r in PolylinesTests.lwMatches(p, r) })
            #expect(tally.mismatches.isEmpty, "\(name)")
            #expect(tally.decoded == tally.expected && tally.decoded == count, "\(name)")
        }
    }

    // MARK: POLYLINE, VERTEX and SEQEND

    /// The handles after a polyline in the DXF: its vertices, and the `SEQEND` that ends them.
    static func run(after handle: UInt64, in sample: CurveSample) -> (
        vertices: [UInt64], seqend: UInt64
    )? {
        guard let start = sample.order.firstIndex(where: { $0.handle == handle }) else {
            return nil
        }
        var vertices: [UInt64] = []
        var index = start + 1
        while index < sample.order.count, sample.order[index].type == "VERTEX" {
            vertices.append(sample.order[index].handle)
            index += 1
        }
        guard index < sample.order.count, sample.order[index].type == "SEQEND" else { return nil }
        return (vertices, sample.order[index].handle)
    }

    /// Whether the vertices and the `SEQEND` a polyline names are the ones after it in the DXF,
    /// and the vertices say it is their owner.
    static func runMatches(
        vertexHandles: [UInt64], first: UInt64, last: UInt64, seqend: UInt64, of handle: UInt64,
        in sample: CurveSample
    ) -> Bool {
        guard let run = run(after: handle, in: sample), run.seqend == seqend,
            sample.records[run.seqend]?.type == "SEQEND",
            run.vertices.allSatisfy({
                sample.records[$0]?.type == "VERTEX"
                    && sample.records[$0]?.first(330).flatMap { UInt64($0, radix: 16) } == handle
            })
        else { return false }
        if sample.store.container.version >= .ac1018 {
            return vertexHandles == run.vertices && first == 0 && last == 0
        }
        return vertexHandles.isEmpty && first == run.vertices.first && last == run.vertices.last
    }

    static func subclass(_ name: String) -> (DXFRecord) -> Bool {
        { $0.all(100).contains(name) }
    }

    @Test("3D polylines equal the DXF's, with the same vertices and SEQEND handles")
    func polylines3D() throws {
        for sample in try CurveOracle.samples() {
            let tally = try CurveOracle.tally(
                sample, dxfType: "POLYLINE", expected: Self.subclass("AcDb3dPolyline"),
                pick: { geometry -> Polyline3DData? in
                    if case .polyline3D(let data) = geometry { return data }
                    return nil
                },
                matches: { p, r in
                    (r.int(70) ?? 0) == p.flags && (r.int(75) ?? 0) == p.curveType
                        && r.all(100).contains("AcDb3dPolyline")
                })
            #expect(tally.mismatches.isEmpty, "\(sample.name)")
            #expect(tally.decoded == tally.expected, "\(sample.name)")
            #expect(
                tally.decoded == (sample.name == "BLOCKPOINTPARAMETER" ? 0 : 1), "\(sample.name)")
            // The handles of the vertices and of the SEQEND, against the order of the DXF.
            var runs = 0
            for (handle, entity) in try sample.decoded() {
                guard case .polyline3D(let p) = entity.geometry else { continue }
                runs += 1
                #expect(
                    Self.runMatches(
                        vertexHandles: p.vertexHandles, first: p.firstVertex, last: p.lastVertex,
                        seqend: p.seqend, of: handle, in: sample),
                    "\(sample.name) \(CurveOracle.hex(handle))")
                #expect(p.vertexHandles.count == 5 || sample.name == "BLOCKPOINTPARAMETER")
            }
            #expect(runs == tally.decoded, "\(sample.name)")
        }
    }

    @Test("3D vertices equal the DXF's, with the same count")
    func vertices3D() throws {
        for sample in try CurveOracle.samples() {
            let tally = try CurveOracle.tally(
                sample, dxfType: "VERTEX", expected: Self.subclass("AcDb3dPolylineVertex"),
                pick: { geometry -> Vertex3DData? in
                    if case .vertex3D(let data) = geometry { return data }
                    return nil
                },
                matches: { v, r in
                    r.all(100).contains("AcDb3dPolylineVertex")
                        && CurveOracle.near(v.location, CurveOracle.point(r, 10, 20, 30))
                        && v.flags == (r.int(70) ?? 0)
                })
            #expect(tally.mismatches.isEmpty, "\(sample.name)")
            #expect(tally.decoded == tally.expected, "\(sample.name)")
            #expect(
                tally.decoded == (sample.name == "BLOCKPOINTPARAMETER" ? 0 : 5), "\(sample.name)")
        }
    }

    @Test("every SEQEND in the DXF is read, and no other")
    func sequenceEnds() throws {
        for sample in try CurveOracle.samples() {
            let tally = try CurveOracle.tally(
                sample, dxfType: "SEQEND",
                pick: { geometry -> Bool? in
                    if case .seqend = geometry { return true }
                    return nil
                },
                matches: { _, _ in true })
            #expect(tally.mismatches.isEmpty, "\(sample.name)")
            #expect(tally.decoded == tally.expected, "\(sample.name)")
            #expect(
                tally.decoded == (sample.name == "BLOCKPOINTPARAMETER" ? 0 : 4), "\(sample.name)")
        }
    }

    /// Compares 2D polylines and their vertices, of which no sample drawing has any yet.
    ///
    /// The counts are 0 on both sides, so this compares nothing today. It is here for the day a
    /// sample has them.
    @Test("2D polylines and vertices equal the DXF's when a sample has them")
    func polylines2D() throws {
        for sample in try CurveOracle.samples() {
            let polylines = try CurveOracle.tally(
                sample, dxfType: "POLYLINE", expected: Self.subclass("AcDb2dPolyline"),
                pick: { geometry -> Polyline2DData? in
                    if case .polyline2D(let data) = geometry { return data }
                    return nil
                },
                matches: { p, r in
                    (r.int(70) ?? 0) == p.flags && (r.int(75) ?? 0) == p.curveType
                        && CurveOracle.near(p.defaultStartWidth, r.double(40) ?? 0)
                        && CurveOracle.near(p.defaultEndWidth, r.double(41) ?? 0)
                        && CurveOracle.near(p.thickness, r.double(39) ?? 0)
                        && CurveOracle.near(p.elevation, r.double(30) ?? 0)
                        && CurveOracle.near(
                            p.extrusion, CurveOracle.point(r, 210, 220, 230) ?? DXF.Point(0, 0, 1))
                })
            #expect(polylines.mismatches.isEmpty, "\(sample.name)")
            #expect(polylines.decoded == polylines.expected, "\(sample.name)")
            #expect(polylines.decoded == 0, "\(sample.name): a sample now has 2D polylines")
            let vertices = try CurveOracle.tally(
                sample, dxfType: "VERTEX", expected: Self.subclass("AcDb2dVertex"),
                pick: { geometry -> Vertex2DData? in
                    if case .vertex2D(let data) = geometry { return data }
                    return nil
                },
                matches: { v, r in
                    (r.int(70) ?? 0) == v.flags
                        && CurveOracle.near(v.location.x, r.double(10))
                        && CurveOracle.near(v.location.y, r.double(20))
                        && CurveOracle.near(v.startWidth, r.double(40) ?? 0)
                        && CurveOracle.near(v.endWidth, r.double(41) ?? 0)
                        && CurveOracle.near(v.bulge, r.double(42) ?? 0)
                        && (r.int(91) ?? 0) == v.id
                        && CurveOracle.near(v.curveTangent * 180 / .pi, r.double(50) ?? 0)
                })
            #expect(vertices.mismatches.isEmpty, "\(sample.name)")
            #expect(vertices.decoded == vertices.expected, "\(sample.name)")
            #expect(vertices.decoded == 0, "\(sample.name): a sample now has 2D vertices")
        }
    }
}
