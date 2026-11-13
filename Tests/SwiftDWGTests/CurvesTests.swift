import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// One drawing and AutoCAD's own DXF export of it, for the curve, polyline and surface oracles.
///
/// The expected values are the raw group codes AutoCAD wrote, read with `DXFGroups`, so nothing
/// here is checked against SwiftDWG's own output.
struct CurveSample {
    let name: String
    let store: ObjectStore
    /// Every record of the DXF that has a handle, by that handle.
    let records: [UInt64: DXFRecord]
    /// The same records in the order the DXF has them, which a polyline's vertices depend on.
    let order: [(type: String, handle: UInt64)]

    /// Every entity of a type that is decoded, by handle, with the ones that are not left out.
    func decoded() throws -> [(handle: UInt64, entity: DecodedEntity)] {
        var out: [(handle: UInt64, entity: DecodedEntity)] = []
        for handle in store.handles {
            do {
                if let entity = try store.entity(handle) { out.append((handle, entity)) }
            } catch is NotDecodedYet {
                continue
            }
        }
        return out
    }
}

/// What a comparison of one entity type found.
struct CurveTally {
    /// How many entities of the type the DWG decoded.
    var decoded = 0
    /// How many records of the type the DXF has.
    var expected = 0
    /// The handles whose values differ from the DXF's, or that have no DXF record of the type.
    var mismatches: [String] = []
}

enum CurveOracle {
    /// The fixture, and with `DWG_CORPUS` also the four AutoCAD samples from R2004 to R2018.
    ///
    /// Read once, since opening a drawing is most of what a test here costs.
    static func samples() throws -> [CurveSample] {
        try loaded.get()
    }

    private static let loaded = Result { try load() }

    private static func load() throws -> [CurveSample] {
        var out = [
            try sample(
                name: "BLOCKPOINTPARAMETER",
                dwg: Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dwg"),
                dxf: Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dxf"))
        ]
        if let corpus = Fixtures.corpus {
            for name in Fixtures.corpusNames {
                out.append(
                    try sample(
                        name: name, dwg: corpus.appendingPathComponent("\(name).dwg"),
                        dxf: corpus.appendingPathComponent("\(name)_ascii.dxf")))
            }
        }
        return out
    }

    static func sample(name: String, dwg: URL, dxf: URL) throws -> CurveSample {
        let store = try ObjectStore(try Container([UInt8](try Data(contentsOf: dwg))))
        return CurveSample(
            name: name, store: store, records: try DXFGroups.records(in: dxf),
            order: try order(of: dxf))
    }

    /// The records of a DXF that have a handle, in file order.
    static func order(of url: URL) throws -> [(type: String, handle: UInt64)] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var out: [(type: String, handle: UInt64)] = []
        var type: String?
        var inHeader = false
        var afterSection = false
        var index = 0
        while index + 1 < lines.count {
            guard let code = Int(lines[index]) else {
                index += 1
                continue
            }
            let value = lines[index + 1]
            index += 2
            if code == 0 {
                type = nil
                afterSection = value == "SECTION"
                if value == "ENDSEC" { inHeader = false }
                if value != "SECTION" && value != "ENDSEC" && value != "EOF" { type = value }
            } else if code == 2 && afterSection {
                inHeader = value == "HEADER"
                afterSection = false
            } else if code == 5, let current = type, !inHeader,
                let handle = UInt64(value, radix: 16)
            {
                out.append((current, handle))
                type = nil
            }
        }
        return out
    }

    /// Decodes every entity of the sample that `pick` takes, and compares it with the DXF record
    /// of the same handle.
    static func tally<T>(
        _ sample: CurveSample, dxfType: String,
        expected isExpected: (DXFRecord) -> Bool = { _ in true },
        pick: (EntityGeometry) -> T?, matches: (T, DXFRecord) -> Bool
    ) throws -> CurveTally {
        var tally = CurveTally()
        for (handle, entity) in try sample.decoded() {
            guard let value = pick(entity.geometry) else { continue }
            tally.decoded += 1
            guard let record = sample.records[handle], record.type == dxfType else {
                tally.mismatches.append("\(hex(handle)): no \(dxfType) in the DXF")
                continue
            }
            if !matches(value, record) { tally.mismatches.append(hex(handle)) }
        }
        tally.expected = sample.records.values.filter { $0.type == dxfType && isExpected($0) }.count
        return tally
    }

    static func hex(_ handle: UInt64) -> String { String(handle, radix: 16, uppercase: true) }

    // MARK: Reading values out of a DXF record

    static func point(_ record: DXFRecord, _ x: Int, _ y: Int, _ z: Int) -> DXF.Point? {
        record.point(x, y, z).map { DXF.Point($0.x, $0.y, $0.z) }
    }

    /// Every point a run of group codes gives, in order: a new one starts at each `x` group.
    static func points(_ record: DXFRecord, _ x: Int, _ y: Int, _ z: Int) -> [DXF.Point] {
        var out: [DXF.Point] = []
        var current: [Double] = []
        func flush() {
            if current.count >= 2 {
                out.append(DXF.Point(current[0], current[1], current.count > 2 ? current[2] : 0))
            }
            current = []
        }
        for (code, value) in record.groups {
            guard let number = Double(value) else { continue }
            if code == x {
                flush()
                current = [number]
            } else if code == y, current.count == 1 {
                current.append(number)
            } else if code == z, current.count == 2 {
                current.append(number)
            }
        }
        flush()
        return out
    }

    static func doubles(_ record: DXFRecord, _ code: Int) -> [Double] {
        record.all(code).compactMap { Double($0) }
    }

    static func near(_ a: Double, _ b: Double?) -> Bool {
        guard let b else { return false }
        return EntityOracle.near(a, b)
    }

    static func near(_ a: DXF.Point, _ b: DXF.Point?) -> Bool {
        guard let b else { return false }
        return EntityOracle.near(a, b)
    }

    static func near(_ a: [DXF.Point], _ b: [DXF.Point]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { EntityOracle.near($0, $1) }
    }

    static func near(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { EntityOracle.near($0, $1) }
    }

    /// Whether two values are equal to a part in 10^12.
    ///
    /// For the tiny tolerances, where the absolute floor of `near` is too forgiving.
    static func close(_ a: Double, _ b: Double?) -> Bool {
        guard let b else { return false }
        return abs(a - b) <= 1e-12 * max(abs(a), abs(b))
    }
}

@Suite("Ellipses and splines against AutoCAD's DXF")
struct CurvesTests {
    @Test("ellipses equal the DXF's, with the same count")
    func ellipses() throws {
        for sample in try CurveOracle.samples() {
            let tally = try CurveOracle.tally(
                sample, dxfType: "ELLIPSE",
                pick: { geometry -> EllipseData? in
                    if case .ellipse(let data) = geometry { return data }
                    return nil
                },
                matches: { e, r in
                    CurveOracle.near(e.center, CurveOracle.point(r, 10, 20, 30))
                        && CurveOracle.near(e.majorAxis, CurveOracle.point(r, 11, 21, 31))
                        && CurveOracle.near(
                            e.extrusion, CurveOracle.point(r, 210, 220, 230) ?? DXF.Point(0, 0, 1))
                        && CurveOracle.near(e.ratio, r.double(40))
                        && CurveOracle.near(e.startParameter, r.double(41))
                        && CurveOracle.near(e.endParameter, r.double(42))
                })
            #expect(tally.mismatches.isEmpty, "\(sample.name)")
            #expect(tally.decoded == tally.expected, "\(sample.name)")
            #expect(
                tally.decoded == (sample.name == "BLOCKPOINTPARAMETER" ? 0 : 1), "\(sample.name)")
        }
    }

    /// Whether a decoded spline agrees with its DXF record.
    ///
    /// A spline that a file keeps as fit points only (R2013 and later, for one made through
    /// points) has no control points or knots in the DWG, but AutoCAD's DXF export has the ones it
    /// worked out. For a cubic through two points, with the end tangents, those are fixed: they
    /// are a single Bezier segment, whose inner control points sit a third of the tangent in from
    /// each end. That relation is the check.
    static func splineMatches(_ s: SplineData, _ r: DXFRecord) -> Bool {
        // The DXF flags also say planar and linear, which a DWG does not store.
        let flags = (s.isClosed ? 1 : 0) | (s.isPeriodic ? 2 : 0) | (s.isRational ? 4 : 0)
        guard (r.int(70) ?? 0) & 7 == flags, s.degree == r.int(71) else { return false }
        let controls = CurveOracle.points(r, 10, 20, 30)
        let fits = CurveOracle.points(r, 11, 21, 31)
        if s.scenario == 1 {
            return s.knots.count == (r.int(72) ?? 0) && s.controlPoints.count == (r.int(73) ?? 0)
                && s.fitPoints.isEmpty && fits.isEmpty
                && CurveOracle.near(s.knots, CurveOracle.doubles(r, 40))
                && CurveOracle.near(s.controlPoints, controls)
                && CurveOracle.near(s.weights, CurveOracle.doubles(r, 41))
                && CurveOracle.close(s.knotTolerance, r.double(42))
                && CurveOracle.close(s.controlPointTolerance, r.double(43))
        }
        guard s.knots.isEmpty, s.controlPoints.isEmpty else { return false }
        if !fits.isEmpty {
            return CurveOracle.near(s.fitPoints, fits) && s.fitPoints.count == (r.int(74) ?? 0)
                && CurveOracle.close(s.fitTolerance, r.double(44))
                && CurveOracle.near(s.startTangent, CurveOracle.point(r, 12, 22, 32))
                && CurveOracle.near(s.endTangent, CurveOracle.point(r, 13, 23, 33))
        }
        guard s.fitPoints.count == 2, s.degree == 3, controls.count == 4,
            CurveOracle.near(CurveOracle.doubles(r, 40), [0, 0, 0, 0, 1, 1, 1, 1])
        else { return false }
        let (first, last) = (s.fitPoints[0], s.fitPoints[1])
        let (t0, t1) = (s.startTangent, s.endTangent)
        let inner = [
            DXF.Point(first.x + t0.x / 3, first.y + t0.y / 3, first.z + t0.z / 3),
            DXF.Point(last.x - t1.x / 3, last.y - t1.y / 3, last.z - t1.z / 3),
        ]
        return CurveOracle.near(controls, [first, inner[0], inner[1], last])
            && CurveOracle.close(s.fitTolerance, 1e-10)
    }

    @Test("splines equal the DXF's, with the same count")
    func splines() throws {
        for sample in try CurveOracle.samples() {
            let tally = try CurveOracle.tally(
                sample, dxfType: "SPLINE",
                pick: { geometry -> SplineData? in
                    if case .spline(let data) = geometry { return data }
                    return nil
                },
                matches: { s, r in CurvesTests.splineMatches(s, r) })
            #expect(tally.mismatches.isEmpty, "\(sample.name)")
            #expect(tally.decoded == tally.expected, "\(sample.name)")
            #expect(
                tally.decoded == (sample.name == "BLOCKPOINTPARAMETER" ? 0 : 2), "\(sample.name)")
        }
    }
}
