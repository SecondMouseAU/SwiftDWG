import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// Writes bit-coded values the way a DWG stores them, so that a test can build an object by hand.
///
/// This is the inverse of `BitReader`, written for the tests. An object built with it shows that
/// the decoders read the fields in the order the test wrote them. It says nothing about AutoCAD:
/// only the oracle tests, against AutoCAD's own DXF, do that.
struct CurveBitWriter {
    var bits: [Bool] = []

    var count: Int { bits.count }

    mutating func bit(_ value: Bool) { bits.append(value) }

    mutating func raw(_ value: UInt64, bits width: Int) {
        for shift in stride(from: width - 1, through: 0, by: -1) {
            bits.append((value >> UInt64(shift)) & 1 == 1)
        }
    }

    mutating func twoBits(_ value: Int) { raw(UInt64(value), bits: 2) }

    mutating func byte(_ value: Int) { raw(UInt64(value & 0xFF), bits: 8) }

    mutating func littleEndian(_ value: UInt64, bytes: Int) {
        for index in 0..<bytes { byte(Int((value >> UInt64(8 * index)) & 0xFF)) }
    }

    mutating func rawDouble(_ value: Double) { littleEndian(value.bitPattern, bytes: 8) }

    mutating func rawLong(_ value: Int) {
        littleEndian(UInt64(UInt32(truncatingIfNeeded: value)), bytes: 4)
    }

    mutating func bitShort(_ value: Int) {
        switch value {
        case 0: twoBits(2)
        case 256: twoBits(3)
        case 1...255:
            twoBits(1)
            byte(value)
        default:
            twoBits(0)
            littleEndian(UInt64(UInt16(truncatingIfNeeded: value)), bytes: 2)
        }
    }

    mutating func bitLong(_ value: Int) {
        switch value {
        case 0: twoBits(2)
        case 1...255:
            twoBits(1)
            byte(value)
        default:
            twoBits(0)
            rawLong(value)
        }
    }

    mutating func bitDouble(_ value: Double) {
        if value == 0 {
            twoBits(2)
        } else if value == 1 {
            twoBits(1)
        } else {
            twoBits(0)
            rawDouble(value)
        }
    }

    /// A bit double with default: the short form when equal to the default, else the full double.
    mutating func bitDouble(_ value: Double, default fallback: Double) {
        if value == fallback {
            twoBits(0)
        } else {
            twoBits(3)
            rawDouble(value)
        }
    }

    mutating func point(_ value: DXF.Point) {
        bitDouble(value.x)
        bitDouble(value.y)
        bitDouble(value.z)
    }

    mutating func point(_ value: DXF.Point, default fallback: DXF.Point) {
        bitDouble(value.x, default: fallback.x)
        bitDouble(value.y, default: fallback.y)
        bitDouble(value.z, default: fallback.z)
    }

    /// An extrusion: one bit for the usual (0, 0, 1) from R2000, else three bit doubles.
    mutating func extrusion(_ value: DXF.Point, _ version: DWG.Version) {
        let usual = value == DXF.Point(0, 0, 1)
        if version >= .ac1015 { bit(usual) }
        if !usual || version < .ac1015 { point(value) }
    }

    /// A thickness: one bit for 0.0 from R2000, else a bit double.
    mutating func thickness(_ value: Double, _ version: DWG.Version) {
        if version >= .ac1015 { bit(value == 0) }
        if value != 0 || version < .ac1015 { bitDouble(value) }
    }

    /// A handle written as an absolute reference of the given code (2 to 5).
    mutating func handle(_ value: UInt64, code: Int = 5) {
        var size = 0
        while size < 8, value >> UInt64(8 * size) != 0 { size += 1 }
        byte(code << 4 | size)
        for index in stride(from: size - 1, through: 0, by: -1) {
            byte(Int((value >> UInt64(8 * index)) & 0xFF))
        }
    }

    /// A handle written as an offset from the object's own handle: code 0xA adds, 0xC subtracts.
    mutating func relativeHandle(code: Int, offset: UInt64) {
        byte(code << 4 | 1)
        byte(Int(offset))
    }

    /// A handle written as the object's own handle plus one (code 6) or minus one (code 8).
    mutating func adjacentHandle(code: Int) { byte(code << 4) }

    mutating func append(_ other: CurveBitWriter) { bits += other.bits }
}

/// An object built by hand.
///
/// It has its common data, the fields a test writes, and the framing a release puts around them.
/// Releases from R13 to R2004 and from R2010 on are written; R2007 is not.
struct CurveObject {
    let version: DWG.Version
    let type: Int
    var handle: UInt64 = 0x3C
    /// The entity's own fields, which follow its common data.
    var main = CurveBitWriter()
    /// The entity's own handles, which follow the layer handle.
    var handles = CurveBitWriter()

    init(_ version: DWG.Version, type: Int) {
        precondition(version != .ac1021 && version >= .ac1012)
        self.version = version
        self.type = type
    }

    /// The common data every entity starts with, with nothing set: model space, no reactors, by
    /// layer, visible.
    private func common() -> (main: CurveBitWriter, handles: CurveBitWriter) {
        var m = CurveBitWriter()
        var h = CurveBitWriter()
        let classic = version <= .ac1018
        if classic {
            m.bitShort(type)
        } else {
            m.twoBits(0)
            m.byte(type)
        }
        if classic && version >= .ac1015 { m.rawLong(0) }  // where the handles start, patched later
        m.handle(handle)
        m.bitShort(0)  // no extended data
        m.bit(false)  // no stored picture
        if version <= .ac1014 { m.rawLong(0) }  // where the handles start, patched later
        m.twoBits(2)  // model space
        m.bitLong(0)  // no reactors
        if version >= .ac1018 { m.bit(true) }  // no extension dictionary
        if version >= .ac1027 { m.bit(false) }
        if version <= .ac1014 {
            h.handle(0)  // the extension dictionary
            h.handle(0x10)  // the layer
            m.bit(true)  // no line type handle
        }
        if version < .ac1018 { m.bit(true) }  // the neighbours are the next and previous handle
        m.bitShort(0)  // colour
        m.bitDouble(1)  // line type scale
        if version <= .ac1014 {
            m.bitShort(0)  // invisible
            return (m, h)
        }
        if version == .ac1015 { h.handle(0) }  // the extension dictionary
        h.handle(0x10)  // the layer
        m.twoBits(0)  // line type by layer
        if version >= .ac1021 {
            m.twoBits(0)  // material by layer
            m.byte(0)  // shadow flags
        }
        m.twoBits(0)  // plot style by layer
        if version >= .ac1024 {
            for _ in 0..<3 { m.bit(false) }  // no visual styles
        }
        m.bitShort(0)  // invisible
        m.byte(0)  // line weight
        return (m, h)
    }

    /// The bytes of the object, framed as the release frames it.
    func bytes() -> [UInt8] {
        var (m, h) = common()
        m.append(main)
        h.append(handles)
        var body = m
        if version <= .ac1018 {
            // The handles start right after the data, at a bit count the data states itself.
            body = patched(m, handlesStart: m.count)
        }
        var all = body
        var handleBits = h
        if version >= .ac1024 {
            // At least one zero bit, so the string stream flag reads clear, then to a byte.
            all.bit(false)
            while (all.count + handleBits.count) % 8 != 0 { all.bit(false) }
        } else {
            while (all.count + handleBits.count) % 8 != 0 { handleBits.bit(false) }
        }
        all.append(handleBits)
        let size = all.count / 8
        var out: [UInt8] = []
        out.append(UInt8(size & 0xFF))
        out.append(UInt8((size >> 8) & 0x7F))
        if version >= .ac1024 {
            // The size of the handles in bits, as a modular char.
            var rest = handleBits.count
            while rest >= 0x80 {
                out.append(UInt8(rest & 0x7F | 0x80))
                rest >>= 7
            }
            out.append(UInt8(rest))
        }
        for index in stride(from: 0, to: all.count, by: 8) {
            var value: UInt8 = 0
            for offset in 0..<8 { value = value << 1 | (all.bits[index + offset] ? 1 : 0) }
            out.append(value)
        }
        return out + [0, 0]
    }

    /// The data with its long of "where the handles start" filled in.
    private func patched(_ writer: CurveBitWriter, handlesStart: Int) -> CurveBitWriter {
        // The long sits after the type code (R2000 to R2004) or after the picture bit (R13, R14).
        var probe = CurveBitWriter()
        probe.bitShort(type)
        var position = probe.count
        if version <= .ac1014 {
            var skipped = CurveBitWriter()
            skipped.handle(handle)
            skipped.bitShort(0)
            skipped.bit(false)
            position += skipped.count
        }
        var bits = writer.bits
        var value = CurveBitWriter()
        value.rawLong(handlesStart)
        for index in 0..<32 { bits[position + index] = value.bits[index] }
        var out = CurveBitWriter()
        out.bits = bits
        return out
    }

    func reader() throws -> ObjectReader {
        try ObjectReader(
            objects: bytes(), offset: 0, version: version, textEncoding: .windowsCP1252)
    }

    /// Reads the entity back with the decoder of its type.
    func decode() throws -> DecodedEntity? {
        var reader = try reader()
        return try reader.readEntity()
    }
}

/// Entities read from objects built by hand.
///
/// They reach the fields and the releases that no sample drawing does. See `CurveBitWriter` for
/// what that does and does not show.
@Suite("Entities read from hand-built objects")
struct HandBuiltObjectTests {
    /// The releases the object builder can frame: R13 and R14, R2000, R2004, and R2010 on.
    static let releases: [DWG.Version] = [
        .ac1012, .ac1014, .ac1015, .ac1018, .ac1024, .ac1027, .ac1032,
    ]

    static let usual = DXF.Point(0, 0, 1)

    /// Whether decoding the object throws `DWG.Error.invalid`, which is how a count or a value the
    /// object cannot hold is refused, and not the `truncated` that reading on past the end gives.
    static func isRefusedAsInvalid(_ object: CurveObject) -> Bool {
        do {
            _ = try object.decode()
            return false
        } catch DWG.Error.invalid {
            return true
        } catch {
            return false
        }
    }

    // MARK: LWPOLYLINE

    @Test("a lightweight polyline with every optional field reads back")
    func lightweightPolyline() throws {
        let points = [(1.0, 2.0), (3.0, 4.0), (3.0, 9.0)]
        for version in Self.releases {
            let hasIDs = version >= .ac1024
            var o = CurveObject(version, type: ObjectType.lwpolyline)
            o.main.bitShort(4 | 8 | 2 | 1 | 0x10 | 0x20 | 0x100 | 0x200 | (hasIDs ? 0x400 : 0))
            o.main.bitDouble(0.5)  // constant width
            o.main.bitDouble(2.25)  // elevation
            o.main.bitDouble(3)  // thickness
            o.main.point(DXF.Point(0, 1, 0))  // extrusion
            o.main.bitLong(3)  // points
            o.main.bitLong(3)  // bulges
            if hasIDs { o.main.bitLong(3) }
            o.main.bitLong(3)  // widths
            if version <= .ac1014 {
                for point in points {
                    o.main.rawDouble(point.0)
                    o.main.rawDouble(point.1)
                }
            } else {
                o.main.rawDouble(points[0].0)
                o.main.rawDouble(points[0].1)
                for index in 1..<3 {
                    o.main.bitDouble(points[index].0, default: points[index - 1].0)
                    o.main.bitDouble(points[index].1, default: points[index - 1].1)
                }
            }
            for bulge in [0.0, 0.5, -1.0] { o.main.bitDouble(bulge) }
            if hasIDs { for id in [10, 20, 30] { o.main.bitLong(id) } }
            for width in [(0.1, 0.2), (0.3, 0.3), (0.0, 0.0)] {
                o.main.bitDouble(width.0)
                o.main.bitDouble(width.1)
            }
            guard let entity = try o.decode(), case .lwpolyline(let p) = entity.geometry else {
                Issue.record("\(version) did not decode to a lightweight polyline")
                continue
            }
            #expect(entity.common.handle == 0x3C, "\(version)")
            #expect(p.isClosed && p.hasLineTypeGeneration, "\(version)")
            #expect(p.constantWidth == 0.5 && p.elevation == 2.25 && p.thickness == 3, "\(version)")
            #expect(p.extrusion == DXF.Point(0, 1, 0), "\(version)")
            #expect(p.points == points.map { DXF.Point2($0.0, $0.1) }, "\(version)")
            #expect(p.bulges == [0.0, 0.5, -1.0], "\(version)")
            #expect(p.vertexIDs == (hasIDs ? [10, 20, 30] : []), "\(version)")
            #expect(
                p.widths.map { [$0.start, $0.end] } == [[0.1, 0.2], [0.3, 0.3], [0.0, 0.0]],
                "\(version)")
        }
    }

    @Test("a lightweight polyline with no optional field has the defaults")
    func plainLightweightPolyline() throws {
        var o = CurveObject(.ac1032, type: ObjectType.lwpolyline)
        o.main.bitShort(0)
        o.main.bitLong(0)
        guard let entity = try o.decode(), case .lwpolyline(let p) = entity.geometry else {
            Issue.record("no lightweight polyline")
            return
        }
        #expect(p.points.isEmpty && p.bulges.isEmpty && p.widths.isEmpty && !p.isClosed)
        #expect(p.extrusion == Self.usual && p.elevation == 0 && p.constantWidth == 0)
    }

    @Test("a lightweight polyline whose counts the object cannot hold is refused")
    func lightweightPolylineCounts() throws {
        // More points than the object has bits for.
        var many = CurveObject(.ac1032, type: ObjectType.lwpolyline)
        many.main.bitShort(0)
        many.main.bitLong(2_000_000_000)
        #expect(Self.isRefusedAsInvalid(many))
        // A negative count.
        var negative = CurveObject(.ac1032, type: ObjectType.lwpolyline)
        negative.main.bitShort(0)
        negative.main.bitLong(-1)
        #expect(Self.isRefusedAsInvalid(negative))
        // More bulges than points.
        var bulges = CurveObject(.ac1032, type: ObjectType.lwpolyline)
        bulges.main.bitShort(0x10)
        bulges.main.bitLong(1)
        bulges.main.bitLong(2)
        bulges.main.rawDouble(0)
        bulges.main.rawDouble(0)
        for _ in 0..<2 { bulges.main.bitDouble(0) }
        #expect(Self.isRefusedAsInvalid(bulges))
    }

    // MARK: POLYLINE, VERTEX

    /// Writes the handles a polyline ends with, and returns the handles they stand for.
    ///
    /// They are the vertices as an owned list (R2004 on) or as the first and last, and the
    /// `SEQEND`, each in a different form against the polyline's own handle 0x3C.
    static func writeVertexHandles(_ o: inout CurveObject) -> (
        list: [UInt64], first: UInt64, last: UInt64, seqend: UInt64
    ) {
        var list: [UInt64] = []
        var first: UInt64 = 0
        var last: UInt64 = 0
        if o.version >= .ac1018 {
            o.main.bitLong(3)
            o.handles.adjacentHandle(code: 6)  // the polyline's handle plus 1
            o.handles.relativeHandle(code: 0xA, offset: 5)  // plus 5
            o.handles.handle(0x1234, code: 4)  // absolute
            list = [0x3D, 0x41, 0x1234]
        } else {
            o.handles.relativeHandle(code: 0xA, offset: 2)
            o.handles.handle(0x99, code: 4)
            first = 0x3E
            last = 0x99
        }
        o.handles.adjacentHandle(code: 8)  // the polyline's handle minus 1
        return (list, first, last, 0x3B)
    }

    @Test("a 2D polyline reads its fields and the handles of its vertices and SEQEND")
    func polyline2D() throws {
        for version in Self.releases {
            var o = CurveObject(version, type: ObjectType.polyline2D)
            o.main.bitShort(1 | 128)  // flags
            o.main.bitShort(6)  // curve type
            o.main.bitDouble(0.25)
            o.main.bitDouble(0.5)
            o.main.thickness(1.5, version)
            o.main.bitDouble(12)  // elevation
            o.main.extrusion(DXF.Point(0, 0, -1), version)
            let expected = Self.writeVertexHandles(&o)
            guard let entity = try o.decode(), case .polyline2D(let p) = entity.geometry else {
                Issue.record("\(version) did not decode to a 2D polyline")
                continue
            }
            #expect(p.flags == 129 && p.curveType == 6 && p.isClosed, "\(version)")
            #expect(p.defaultStartWidth == 0.25 && p.defaultEndWidth == 0.5, "\(version)")
            #expect(p.thickness == 1.5 && p.elevation == 12, "\(version)")
            #expect(p.extrusion == DXF.Point(0, 0, -1), "\(version)")
            #expect(p.vertexHandles == expected.list, "\(version)")
            #expect(p.firstVertex == expected.first && p.lastVertex == expected.last, "\(version)")
            #expect(p.seqend == expected.seqend, "\(version)")
        }
    }

    @Test("a 3D polyline reads its two flag bytes and the handles of its vertices and SEQEND")
    func polyline3D() throws {
        for version in Self.releases {
            var o = CurveObject(version, type: ObjectType.polyline3D)
            o.main.byte(2)  // cubic spline fit
            o.main.byte(1)  // closed
            let expected = Self.writeVertexHandles(&o)
            guard let entity = try o.decode(), case .polyline3D(let p) = entity.geometry else {
                Issue.record("\(version) did not decode to a 3D polyline")
                continue
            }
            #expect(p.isClosed && p.curveType == 6 && p.flags == 1 | 4 | 8, "\(version)")
            #expect(p.vertexHandles == expected.list, "\(version)")
            #expect(p.firstVertex == expected.first && p.lastVertex == expected.last, "\(version)")
            #expect(p.seqend == expected.seqend, "\(version)")
        }
    }

    @Test("a polyline that owns more vertices than the object has bytes for is refused")
    func polylineOwnedCount() throws {
        var o = CurveObject(.ac1032, type: ObjectType.polyline3D)
        o.main.byte(0)
        o.main.byte(0)
        o.main.bitLong(2_000_000_000)
        #expect(Self.isRefusedAsInvalid(o))
    }

    @Test("a 2D vertex reads both forms of its widths, and its id from R2010")
    func vertex2D() throws {
        for version in Self.releases {
            for shortForm in [true, false] {
                var o = CurveObject(version, type: ObjectType.vertex2D)
                o.main.byte(0x10)
                o.main.point(DXF.Point(1, 2, 0))
                if shortForm {
                    o.main.bitDouble(-0.75)  // both widths, and no end width
                } else {
                    o.main.bitDouble(0.25)
                    o.main.bitDouble(0.5)
                }
                o.main.bitDouble(0.5)  // bulge
                if version >= .ac1024 { o.main.bitLong(7) }
                o.main.bitDouble(0.3)  // tangent
                guard let entity = try o.decode(), case .vertex2D(let v) = entity.geometry else {
                    Issue.record("\(version) did not decode to a 2D vertex")
                    continue
                }
                #expect(v.flags == 0x10 && v.location == DXF.Point(1, 2, 0), "\(version)")
                #expect(v.startWidth == (shortForm ? 0.75 : 0.25), "\(version)")
                #expect(v.endWidth == (shortForm ? 0.75 : 0.5), "\(version)")
                #expect(v.bulge == 0.5 && v.curveTangent == 0.3, "\(version)")
                #expect(v.id == (version >= .ac1024 ? 7 : 0), "\(version)")
            }
        }
    }

    // MARK: SPLINE

    /// The fields of the control-point form of a spline, after its scenario and degree.
    static func writeControlPointSpline(_ o: inout CurveObject) {
        o.main.bit(true)  // rational
        o.main.bit(false)  // closed
        o.main.bit(true)  // periodic
        o.main.bitDouble(1e-9)
        o.main.bitDouble(1e-10)
        o.main.bitLong(6)  // knots
        o.main.bitLong(3)  // control points
        o.main.bit(true)  // weights
        for knot in [0.0, 0, 0, 1, 1, 1] { o.main.bitDouble(knot) }
        for (index, point) in [DXF.Point(0, 0, 0), DXF.Point(1, 2, 3), DXF.Point(4, 5, 0)]
            .enumerated()
        {
            o.main.point(point)
            o.main.bitDouble(1.0 + Double(index))
        }
    }

    @Test("a spline in the control-point form reads its knots, points and weights")
    func controlPointSpline() throws {
        for version in Self.releases {
            var o = CurveObject(version, type: ObjectType.spline)
            o.main.bitLong(1)  // scenario
            if version >= .ac1027 {
                o.main.bitLong(0)  // flags
                o.main.bitLong(15)  // custom knots
            }
            o.main.bitLong(2)  // degree
            Self.writeControlPointSpline(&o)
            guard let entity = try o.decode(), case .spline(let s) = entity.geometry else {
                Issue.record("\(version) did not decode to a spline")
                continue
            }
            #expect(s.scenario == 1 && s.degree == 2, "\(version)")
            #expect(s.isRational && !s.isClosed && s.isPeriodic, "\(version)")
            #expect(s.knots == [0, 0, 0, 1, 1, 1], "\(version)")
            #expect(
                s.controlPoints == [DXF.Point(0, 0, 0), DXF.Point(1, 2, 3), DXF.Point(4, 5, 0)])
            #expect(s.weights == [1, 2, 3] && s.fitPoints.isEmpty, "\(version)")
            #expect(s.knotTolerance == 1e-9 && s.controlPointTolerance == 1e-10, "\(version)")
            #expect(s.knotParameter == 15, "\(version)")
        }
    }

    @Test("a spline in the fit-point form reads its points and tangents")
    func fitPointSpline() throws {
        for version in Self.releases {
            var o = CurveObject(version, type: ObjectType.spline)
            o.main.bitLong(2)  // scenario
            if version >= .ac1027 {
                o.main.bitLong(1 | 8)  // fit points, knot parameter in use
                o.main.bitLong(2)  // uniform
            }
            o.main.bitLong(3)  // degree
            o.main.bitDouble(1e-10)  // fit tolerance
            o.main.point(DXF.Point(1, 0, 0))
            o.main.point(DXF.Point(0, -1, 0))
            o.main.bitLong(3)
            let fits = [DXF.Point(0, 0, 0), DXF.Point(5, 5, 1), DXF.Point(9, 0, 0)]
            for fit in fits { o.main.point(fit) }
            guard let entity = try o.decode(), case .spline(let s) = entity.geometry else {
                Issue.record("\(version) did not decode to a spline")
                continue
            }
            #expect(s.scenario == 2 && s.degree == 3 && s.methodFlags & 1 == 1, "\(version)")
            #expect(s.fitPoints == fits && s.knots.isEmpty && s.controlPoints.isEmpty, "\(version)")
            #expect(s.startTangent == DXF.Point(1, 0, 0), "\(version)")
            #expect(s.endTangent == DXF.Point(0, -1, 0), "\(version)")
            #expect(s.fitTolerance == 1e-10 && s.knotParameter == (version >= .ac1027 ? 2 : 0))
        }
    }

    @Test("a spline from R2013 takes its form from the knot parameter, not the scenario it states")
    func splineScenarioFromTheFlags() throws {
        // Flags with the knot parameter in use and a uniform parameter: fit points, whatever the
        // stated scenario.
        var fit = CurveObject(.ac1032, type: ObjectType.spline)
        fit.main.bitLong(1)
        fit.main.bitLong(1 | 8)
        fit.main.bitLong(0)
        fit.main.bitLong(3)
        fit.main.bitDouble(0)
        fit.main.point(DXF.Point(0, 0, 0))
        fit.main.point(DXF.Point(0, 0, 0))
        fit.main.bitLong(0)
        if let entity = try fit.decode(), case .spline(let s) = entity.geometry {
            #expect(s.scenario == 2 && s.knotParameter == 0)
        } else {
            Issue.record("no spline")
        }
        // The same flags with custom knots: the control-point form, closed by the method flags.
        var custom = CurveObject(.ac1032, type: ObjectType.spline)
        custom.main.bitLong(2)
        custom.main.bitLong(4 | 8)
        custom.main.bitLong(15)
        custom.main.bitLong(2)
        custom.main.bit(false)
        custom.main.bit(false)
        custom.main.bit(false)
        custom.main.bitDouble(0)
        custom.main.bitDouble(0)
        custom.main.bitLong(0)
        custom.main.bitLong(0)
        custom.main.bit(false)
        if let entity = try custom.decode(), case .spline(let s) = entity.geometry {
            #expect(s.scenario == 1 && s.isClosed && !s.isClosedFlag)
        } else {
            Issue.record("no spline")
        }
    }

    @Test("a spline with a scenario that is neither form, or counts it cannot hold, is refused")
    func splineBadFields() throws {
        var scenario = CurveObject(.ac1018, type: ObjectType.spline)
        scenario.main.bitLong(7)
        scenario.main.bitLong(3)
        #expect(Self.isRefusedAsInvalid(scenario))

        var knots = CurveObject(.ac1018, type: ObjectType.spline)
        knots.main.bitLong(1)
        knots.main.bitLong(3)
        knots.main.bit(false)
        knots.main.bit(false)
        knots.main.bit(false)
        knots.main.bitDouble(0)
        knots.main.bitDouble(0)
        knots.main.bitLong(2_000_000_000)
        knots.main.bitLong(0)
        knots.main.bit(false)
        #expect(Self.isRefusedAsInvalid(knots))

        var fits = CurveObject(.ac1018, type: ObjectType.spline)
        fits.main.bitLong(2)
        fits.main.bitLong(3)
        fits.main.bitDouble(0)
        fits.main.point(DXF.Point(0, 0, 0))
        fits.main.point(DXF.Point(0, 0, 0))
        fits.main.bitLong(-3)
        #expect(Self.isRefusedAsInvalid(fits))
    }

    // MARK: SOLID, TRACE, 3DFACE

    @Test("a solid and a trace read their corners at the elevation, and say which they are")
    func solidAndTrace() throws {
        let corners = [(0.0, 0.0), (4.0, 0.0), (0.0, 3.0), (4.0, 3.0)]
        for version in Self.releases {
            for type in [ObjectType.solid, ObjectType.trace] {
                var o = CurveObject(version, type: type)
                o.main.thickness(2.5, version)
                o.main.bitDouble(7)  // elevation
                for corner in corners {
                    o.main.rawDouble(corner.0)
                    o.main.rawDouble(corner.1)
                }
                o.main.extrusion(DXF.Point(1, 0, 0), version)
                guard let entity = try o.decode(), case .solid(let s) = entity.geometry else {
                    Issue.record("\(version) did not decode to a solid")
                    continue
                }
                #expect(s.isTrace == (type == ObjectType.trace), "\(version)")
                #expect(s.thickness == 2.5 && s.elevation == 7, "\(version)")
                #expect(s.extrusion == DXF.Point(1, 0, 0), "\(version)")
                #expect(s.corners == corners.map { DXF.Point($0.0, $0.1, 7) }, "\(version)")
            }
        }
    }

    @Test("a 3D face reads its corners and invisible edge flags")
    func face3D() throws {
        let corners = [
            DXF.Point(1, 2, 3), DXF.Point(1, 5, 3), DXF.Point(4, 5, 3), DXF.Point(4, 2, 8),
        ]
        for version in Self.releases {
            for hasFlags in [true, false] {
                var o = CurveObject(version, type: ObjectType.face3D)
                if version <= .ac1014 {
                    for corner in corners { o.main.point(corner) }
                    o.main.bitShort(hasFlags ? 6 : 0)
                } else {
                    o.main.bit(!hasFlags)  // no flags follow
                    o.main.bit(false)  // the first corner's z is not zero
                    o.main.rawDouble(corners[0].x)
                    o.main.rawDouble(corners[0].y)
                    o.main.rawDouble(corners[0].z)
                    for index in 1..<4 { o.main.point(corners[index], default: corners[index - 1]) }
                    if hasFlags { o.main.bitShort(6) }
                }
                guard let entity = try o.decode(), case .face3D(let f) = entity.geometry else {
                    Issue.record("\(version) did not decode to a 3D face")
                    continue
                }
                #expect(f.corners == corners, "\(version)")
                #expect(f.invisibleEdges == (hasFlags ? 6 : 0), "\(version)")
            }
        }
        // A flat first corner has no z in the object.
        var flat = CurveObject(.ac1032, type: ObjectType.face3D)
        flat.main.bit(true)
        flat.main.bit(true)
        flat.main.rawDouble(1)
        flat.main.rawDouble(2)
        for _ in 1..<4 { flat.main.point(DXF.Point(1, 2, 0), default: DXF.Point(1, 2, 0)) }
        if let entity = try flat.decode(), case .face3D(let f) = entity.geometry {
            #expect(f.corners == Array(repeating: DXF.Point(1, 2, 0), count: 4))
        } else {
            Issue.record("no 3D face")
        }
    }

    @Test("an ellipse reads its centre, axis, extrusion, ratio and parameters")
    func ellipse() throws {
        for version in Self.releases {
            var o = CurveObject(version, type: ObjectType.ellipse)
            o.main.point(DXF.Point(1, 2, 3))
            o.main.point(DXF.Point(4, 0, 0))
            o.main.point(DXF.Point(0, 0, 1))
            o.main.bitDouble(0.5)
            o.main.bitDouble(0)
            o.main.bitDouble(.pi)
            guard let entity = try o.decode(), case .ellipse(let e) = entity.geometry else {
                Issue.record("\(version) did not decode to an ellipse")
                continue
            }
            #expect(
                e.center == DXF.Point(1, 2, 3) && e.majorAxis == DXF.Point(4, 0, 0), "\(version)")
            #expect(e.extrusion == Self.usual && e.ratio == 0.5, "\(version)")
            #expect(e.startParameter == 0 && e.endParameter == .pi, "\(version)")
        }
    }

    @Test("a SEQEND reads to the entity with no geometry")
    func seqend() throws {
        for version in Self.releases {
            guard let entity = try CurveObject(version, type: ObjectType.seqend).decode(),
                case .seqend = entity.geometry
            else {
                Issue.record("\(version) did not decode to a SEQEND")
                continue
            }
            #expect(entity.common.handle == 0x3C && entity.common.entityMode == 2, "\(version)")
        }
    }
}

/// Objects cut short, or with a byte overwritten, must be refused with a `DWG.Error`, never trap
/// and never answer a damaged count with a huge allocation.
@Suite("Truncated and damaged objects")
struct DamagedObjectTests {
    enum Outcome {
        case decoded
        case rejected
        case unexpected(String)
    }

    /// Reads the entity in `bytes`, with both of its streams cut to `cut` bytes when it is given.
    static func attempt(_ bytes: [UInt8], _ version: DWG.Version, cut: Int? = nil) -> Outcome {
        do {
            var reader = try ObjectReader(
                objects: bytes, offset: 0, version: version, textEncoding: .windowsCP1252)
            if let cut {
                let kept = Array(bytes.prefix(cut))
                reader.main = BitReader(kept, version: version, position: reader.main.position)
                reader.handles = BitReader(
                    kept, version: version, position: reader.handles.position)
            }
            return try reader.readEntity() == nil ? .rejected : .decoded
        } catch is DWG.Error {
            return .rejected
        } catch {
            return .unexpected("\(error)")
        }
    }

    /// Cuts the object at every byte: the entity decodes from some length on, and before that
    /// every attempt is refused.
    static func checkTruncation(_ bytes: [UInt8], _ version: DWG.Version, _ label: String) {
        var decoded = false
        for cut in 0...bytes.count {
            switch attempt(bytes, version, cut: cut) {
            case .decoded: decoded = true
            case .rejected: #expect(!decoded, "\(label): decoded at a shorter cut, not at \(cut)")
            case .unexpected(let message): Issue.record("\(label) at \(cut): \(message)")
            }
        }
        #expect(decoded, "\(label): never decoded")
        if case .rejected = attempt(bytes, version, cut: 0) {
        } else {
            Issue.record("\(label): decoded from no bytes")
        }
    }

    /// One hand-built object of each kind that has counts or lists in it.
    static func handBuilt(_ version: DWG.Version) -> [(String, CurveObject)] {
        var out: [(String, CurveObject)] = []
        var polyline = CurveObject(version, type: ObjectType.lwpolyline)
        polyline.main.bitShort(0x10 | 0x20 | 0x200)
        polyline.main.bitLong(2)
        polyline.main.bitLong(2)
        polyline.main.bitLong(2)
        polyline.main.rawDouble(1)
        polyline.main.rawDouble(2)
        polyline.main.bitDouble(3, default: 1)
        polyline.main.bitDouble(4, default: 2)
        polyline.main.bitDouble(0.5)
        polyline.main.bitDouble(0)
        for _ in 0..<2 {
            polyline.main.bitDouble(0.1)
            polyline.main.bitDouble(0.2)
        }
        out.append(("lwpolyline", polyline))

        var spline = CurveObject(version, type: ObjectType.spline)
        spline.main.bitLong(1)
        if version >= .ac1027 {
            spline.main.bitLong(0)
            spline.main.bitLong(15)
        }
        spline.main.bitLong(2)
        HandBuiltObjectTests.writeControlPointSpline(&spline)
        out.append(("spline", spline))

        var polyline3D = CurveObject(version, type: ObjectType.polyline3D)
        polyline3D.main.byte(0)
        polyline3D.main.byte(0)
        _ = HandBuiltObjectTests.writeVertexHandles(&polyline3D)
        out.append(("polyline3D", polyline3D))

        var face = CurveObject(version, type: ObjectType.face3D)
        face.main.bit(false)
        face.main.bit(false)
        for _ in 0..<3 { face.main.rawDouble(1) }
        for _ in 1..<4 { face.main.point(DXF.Point(2, 2, 2), default: DXF.Point(1, 1, 1)) }
        face.main.bitShort(3)
        out.append(("face3D", face))
        return out
    }

    @Test("a hand-built object cut at any byte is refused until it is whole")
    func truncatedHandBuilt() {
        for version in [DWG.Version.ac1015, .ac1018, .ac1032] {
            for (label, object) in Self.handBuilt(version) {
                Self.checkTruncation(object.bytes(), version, "\(label) \(version)")
            }
        }
    }

    @Test("objects of the sample drawings, cut at any byte or with a byte overwritten, never trap")
    func damagedSampleObjects() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        let types: Set<Int> = [
            ObjectType.ellipse, ObjectType.spline, ObjectType.lwpolyline, ObjectType.polyline2D,
            ObjectType.polyline3D, ObjectType.vertex2D, ObjectType.vertex3D, ObjectType.seqend,
            ObjectType.solid, ObjectType.trace, ObjectType.face3D,
        ]
        var tried = 0
        for name in Fixtures.corpusNames {
            let data = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
            let store = try ObjectStore(try Container(data))
            let version = store.container.version
            for handle in store.handles {
                guard let reader = try store.reader(for: handle), types.contains(reader.type),
                    let offset = store.map[handle]
                else { continue }
                var head = BitReader(store.objects, version: version, position: offset * 8)
                let size = try head.readModularShort()
                if version >= .ac1024 { _ = try head.readModularChar() }
                let header = head.position / 8 - offset
                let end = min(store.objects.count, offset + header + size + 2)
                let bytes = Array(store.objects[offset..<end])
                tried += 1
                Self.checkTruncation(bytes, version, "\(name) \(CurveOracle.hex(handle))")
                // The type code takes the first ten bits, and is left as it is: a different type
                // is another decoder's to read.
                for index in (header + 2)..<min(bytes.count, header + size) {
                    for value in [UInt8(0xFF), 0x00, 0x80] {
                        var damaged = bytes
                        damaged[index] = value
                        if case .unexpected(let message) = Self.attempt(damaged, version) {
                            Issue.record(
                                "\(name) \(CurveOracle.hex(handle)) byte \(index): \(message)")
                        }
                    }
                }
            }
        }
        #expect(tried == 4 * 51, "51 entities of these types in each of the four drawings")
    }
}
