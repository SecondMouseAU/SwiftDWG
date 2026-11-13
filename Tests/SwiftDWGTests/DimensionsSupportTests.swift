import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// Bits written the way a DWG codes them, to build objects that no sample has: the edges of a
/// hatch that are not lines, bulges, corrupt counts, and the releases before R2004.
///
/// These check that the decoders read what the field order says and stop at bad counts. They do
/// not check the field order itself, which only AutoCAD's own files can.
struct SyntheticBits {
    private(set) var bits: [Bool] = []

    var count: Int { bits.count }

    mutating func bit(_ value: Bool) { bits.append(value) }

    mutating func raw(_ value: UInt64, bits count: Int) {
        for index in stride(from: count - 1, through: 0, by: -1) {
            bits.append((value >> UInt64(index)) & 1 == 1)
        }
    }

    mutating func byte(_ value: UInt8) { raw(UInt64(value), bits: 8) }

    mutating func rawLong(_ value: Int32) {
        for index in 0..<4 { byte(UInt8(truncatingIfNeeded: value >> Int32(8 * index))) }
    }

    mutating func rawDouble(_ value: Double) {
        for index in 0..<8 {
            byte(UInt8(truncatingIfNeeded: value.bitPattern >> UInt64(8 * index)))
        }
    }

    mutating func point2(_ x: Double, _ y: Double) {
        rawDouble(x)
        rawDouble(y)
    }

    mutating func bitShort(_ value: Int) {
        switch value {
        case 0: raw(2, bits: 2)
        case 256: raw(3, bits: 2)
        case 1...255:
            raw(1, bits: 2)
            byte(UInt8(value))
        default:
            raw(0, bits: 2)
            byte(UInt8(truncatingIfNeeded: value))
            byte(UInt8(truncatingIfNeeded: value >> 8))
        }
    }

    mutating func bitLong(_ value: Int32) {
        switch value {
        case 0: raw(2, bits: 2)
        case 1...255:
            raw(1, bits: 2)
            byte(UInt8(value))
        default:
            raw(0, bits: 2)
            rawLong(value)
        }
    }

    mutating func bitDouble(_ value: Double) {
        if value == 0 {
            raw(2, bits: 2)
        } else if value == 1 {
            raw(1, bits: 2)
        } else {
            raw(0, bits: 2)
            rawDouble(value)
        }
    }

    mutating func bitPoint3(_ x: Double, _ y: Double, _ z: Double) {
        bitDouble(x)
        bitDouble(y)
        bitDouble(z)
    }

    /// A handle written as an absolute reference of code 5.
    mutating func handle(_ value: UInt64) {
        var size = 0
        while size < 8, value >> UInt64(8 * size) != 0 { size += 1 }
        byte(UInt8(0x50 | size))
        for index in stride(from: size - 1, through: 0, by: -1) {
            byte(UInt8(truncatingIfNeeded: value >> UInt64(8 * index)))
        }
    }

    /// A text of up to 255 ASCII characters, as releases before R2007 keep it.
    mutating func text(_ value: String) {
        let characters = Array(value.utf8)
        bitShort(characters.count)
        for character in characters { byte(character) }
    }

    func bytes() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for (index, bit) in bits.enumerated() where bit {
            out[index >> 3] |= UInt8(0x80 >> (index & 7))
        }
        return out
    }

    mutating func patch(at position: Int, rawLong value: Int32) {
        for index in 0..<32 {
            let byteIndex = index / 8
            let shift = 7 - index % 8
            let byte = UInt8(truncatingIfNeeded: value >> Int32(8 * byteIndex))
            bits[position + index] = (byte >> UInt8(shift)) & 1 == 1
        }
    }
}

/// An object of R2000, R2004 or R2010 laid out as a file does.
///
/// The data every entity starts with is already written. The entity's own fields are written to
/// `main` and `handles`.
struct DimensionObject {
    let version: DWG.Version
    var main = SyntheticBits()
    var handles = SyntheticBits()
    private var sizePosition = 0

    init(version: DWG.Version, type: Int) {
        self.version = version
        if version >= .ac1024 {
            main.raw(0, bits: 2)
            main.byte(UInt8(type))
        } else {
            main.bitShort(type)
            sizePosition = main.count
            main.rawLong(0)  // the size of the main data, patched when the object is finished
        }
        main.byte(0x00)  // the object's own handle: code 0, no bytes
        main.bitShort(0)  // no extended data
        main.bit(false)  // no picture
        main.raw(2, bits: 2)  // in model space
        main.bitLong(0)  // no reactors
        if version >= .ac1018 {
            main.bit(true)  // no extension dictionary
        } else {
            handles.handle(0x30)  // the extension dictionary, which R2000 always names
            main.bit(true)  // the neighbours are the usual ones
        }
        main.bitShort(version >= .ac1018 ? 0 : 256)  // colour
        main.bitDouble(1)  // line type scale
        handles.handle(0x10)  // layer
        main.raw(0, bits: 2)  // line type by layer
        if version >= .ac1021 {
            main.raw(0, bits: 2)  // no material
            main.byte(0)  // shadow flags
        }
        main.raw(0, bits: 2)  // plot style by layer
        if version >= .ac1024 { main.raw(0, bits: 3) }  // no visual style handles
        main.bitShort(0)  // visible
        main.byte(0)  // line weight
    }

    /// The object as the objects section holds it, with no CRC.
    func bytes() -> [UInt8] {
        var data = main
        let tail = handles
        if version >= .ac1024 {
            // The last bit of the main data says whether a string stream is there, and the handles
            // end the object.
            let total = data.count + 1 + tail.count
            let size = (total + 7) / 8
            for _ in 0..<(size * 8 - total) { data.bit(false) }
            data.bit(false)
            for index in 0..<tail.count { data.bit(tail.bits[index]) }
            var head = SyntheticBits()
            head.byte(UInt8(size & 0xFF))
            head.byte(UInt8(size >> 8))
            // The size of the handle stream in bits, as a modular char.
            var handleBits = tail.count
            repeat {
                var chunk = UInt8(handleBits & 0x7F)
                handleBits >>= 7
                if handleBits > 0 { chunk |= 0x80 }
                head.byte(chunk)
            } while handleBits > 0
            return head.bytes() + data.bytes()
        }
        data.patch(at: sizePosition, rawLong: Int32(data.count))
        for index in 0..<tail.count { data.bit(tail.bits[index]) }
        let size = data.bytes().count
        return [UInt8(size & 0xFF), UInt8(size >> 8)] + data.bytes()
    }

    func reader() throws -> ObjectReader {
        try ObjectReader(
            objects: bytes(), offset: 0, version: version, textEncoding: .windowsCP1252)
    }
}

@Suite("Hand-made objects")
struct DimensionsSupportTests {
    static let versions: [DWG.Version] = [.ac1015, .ac1018, .ac1024]

    // MARK: Hatches

    /// Writes the fields of a hatch that has a polyline path with bulges and an edge path with one
    /// edge of each kind, and returns the handle of its one boundary source.
    static func hatch(version: DWG.Version) -> DimensionObject {
        var o = DimensionObject(version: version, type: ObjectType.hatch)
        if version >= .ac1018 {
            o.main.bitLong(1)  // a gradient fill
            o.main.bitLong(0)
            o.main.bitDouble(0.5)  // angle
            o.main.bitDouble(0.25)  // shift
            o.main.bitLong(1)  // one colour
            o.main.bitDouble(0.75)  // tint
            o.main.bitLong(1)  // one colour stop
            o.main.bitDouble(1)
            o.main.bitShort(0)  // the colour as index, always 0
            o.main.bitLong(Int32(bitPattern: 0xC200_00FF))  // true colour, blue
            o.main.byte(0)
            if version < .ac1021 { o.main.text("GRADIENT") }
        }
        o.main.bitDouble(2.5)  // elevation
        o.main.bitPoint3(0, 0, 1)
        if version < .ac1021 { o.main.text("ANSI31") }
        o.main.bit(false)  // not solid
        o.main.bit(true)  // associative
        o.main.bitLong(2)  // two paths

        // A polyline path with bulges.
        o.main.bitLong(3)  // external and polyline
        o.main.bit(true)
        o.main.bit(true)
        o.main.bitLong(3)
        for (x, y, bulge) in [(0.0, 0.0, 0.5), (4.0, 0.0, 0.0), (4.0, 3.0, -1.0)] {
            o.main.point2(x, y)
            o.main.bitDouble(bulge)
        }
        o.main.bitLong(1)
        o.handles.handle(0x2A0)

        // An edge path with a line, an arc, an ellipse and a rational spline.
        o.main.bitLong(1)
        o.main.bitLong(4)
        o.main.byte(1)
        o.main.point2(1, 2)
        o.main.point2(3, 4)
        o.main.byte(2)
        o.main.point2(5, 6)
        o.main.bitDouble(7)
        o.main.bitDouble(0.25)
        o.main.bitDouble(1.5)
        o.main.bit(true)
        o.main.byte(3)
        o.main.point2(8, 9)
        o.main.point2(2, 1)
        o.main.bitDouble(0.5)
        o.main.bitDouble(0)
        o.main.bitDouble(3.25)
        o.main.bit(false)
        o.main.byte(4)
        o.main.bitLong(3)  // degree
        o.main.bit(true)  // rational
        o.main.bit(false)  // not periodic
        o.main.bitLong(4)  // knots
        o.main.bitLong(2)  // control points
        for knot in [0.0, 0.0, 1.0, 1.0] { o.main.bitDouble(knot) }
        o.main.point2(10, 11)
        o.main.bitDouble(0.5)
        o.main.point2(12, 13)
        o.main.bitDouble(2)
        if version >= .ac1024 {
            o.main.bitLong(2)  // fit points
            o.main.point2(10, 11)
            o.main.point2(12, 13)
            o.main.point2(1, 0)  // start tangent
            o.main.point2(0, 1)  // end tangent
        }
        o.main.bitLong(0)  // no source objects

        o.main.bitShort(1)  // style
        o.main.bitShort(2)  // pattern type
        o.main.bitDouble(0.5)  // pattern angle
        o.main.bitDouble(2)  // scale
        o.main.bit(true)  // double
        o.main.bitShort(1)  // one pattern line
        o.main.bitDouble(0.75)
        o.main.bitDouble(1)
        o.main.bitDouble(2)
        o.main.bitDouble(3)
        o.main.bitDouble(4)
        o.main.bitShort(2)
        o.main.bitDouble(0.5)
        o.main.bitDouble(-0.25)
        o.main.bitLong(2)  // seeds
        o.main.point2(0.5, 0.5)
        o.main.point2(1.5, 1.5)
        return o
    }

    /// Checks that a read stops at a count the object cannot hold, and not later when it runs out
    /// of data.
    static func expectInvalid(
        _ body: () throws -> Void, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        do {
            try body()
            Issue.record("the read did not throw", sourceLocation: sourceLocation)
        } catch let error as DWG.Error {
            if case .invalid = error { return }
            Issue.record("\(error) is not an invalid count", sourceLocation: sourceLocation)
        } catch {
            Issue.record("\(error)", sourceLocation: sourceLocation)
        }
    }

    static func read(hatch object: DimensionObject) throws -> DecodedEntity {
        var reader = try object.reader()
        return try reader.readHatch()
    }

    static func read(leader object: DimensionObject) throws -> DecodedEntity {
        var reader = try object.reader()
        return try reader.readLeader()
    }

    @Test("a hatch with every kind of edge and with bulges reads as it was written")
    func syntheticHatch() throws {
        for version in Self.versions {
            var reader = try Self.hatch(version: version).reader()
            let entity = try reader.readHatch()
            guard case .hatch(let hatch) = entity.geometry else {
                Issue.record("not a hatch")
                continue
            }
            let label = "\(version)"
            #expect(hatch.elevation == 2.5, "\(label)")
            #expect(hatch.isSolid == false && hatch.isAssociative, "\(label)")
            #expect(hatch.style == 1 && hatch.patternType == 2, "\(label)")
            #expect(hatch.patternAngle == 0.5 && hatch.patternScale == 2 && hatch.isDouble)
            #expect(hatch.seedPoints == [DXF.Point2(0.5, 0.5), DXF.Point2(1.5, 1.5)])
            #expect(hatch.pixelSize == nil)
            if version >= .ac1018 {
                let gradient = try #require(hatch.gradient)
                #expect(gradient.isEnabled && gradient.isSingleColor)
                #expect(gradient.angle == 0.5 && gradient.shift == 0.25 && gradient.tint == 0.75)
                #expect(gradient.colors.count == 1)
                if let stop = gradient.colors.first {
                    #expect(stop.position == 1)
                    #expect(stop.color == .rgb(red: 0, green: 0, blue: 255))
                }
                #expect(gradient.name == (version < .ac1021 ? "GRADIENT" : ""))
            } else {
                #expect(hatch.gradient == nil)
            }
            #expect(hatch.patternName == (version < .ac1021 ? "ANSI31" : ""))

            #expect(hatch.patternLines.count == 1)
            if let line = hatch.patternLines.first {
                #expect(line.angle == 0.75)
                #expect(line.basePoint == DXF.Point2(1, 2) && line.offset == DXF.Point2(3, 4))
                #expect(line.dashLengths == [0.5, -0.25])
            }

            #expect(hatch.paths.count == 2)
            guard hatch.paths.count == 2 else { continue }
            #expect(hatch.paths[0].flags == 3 && hatch.paths[0].isPolyline)
            #expect(hatch.paths[0].sourceBoundaries == [0x2A0])
            if case .polyline(let vertices, let isClosed, let hasBulges) = hatch.paths[0].shape {
                #expect(isClosed && hasBulges)
                #expect(
                    vertices.map(\.point) == [
                        DXF.Point2(0, 0), DXF.Point2(4, 0), DXF.Point2(4, 3),
                    ])
                #expect(vertices.map(\.bulge) == [0.5, 0, -1])
            } else {
                Issue.record("the first path is not a polyline")
            }

            #expect(hatch.paths[1].flags == 1 && hatch.paths[1].sourceBoundaries.isEmpty)
            guard case .edges(let edges) = hatch.paths[1].shape, edges.count == 4 else {
                Issue.record("the second path does not have four edges")
                continue
            }
            if case .line(let start, let end) = edges[0] {
                #expect(start == DXF.Point2(1, 2) && end == DXF.Point2(3, 4))
            } else {
                Issue.record("edge 0 is not a line")
            }
            if case .circularArc(let center, let radius, let start, let end, let ccw) = edges[1] {
                #expect(center == DXF.Point2(5, 6) && radius == 7)
                #expect(start == 0.25 && end == 1.5 && ccw)
            } else {
                Issue.record("edge 1 is not an arc")
            }
            if case .ellipticArc(let center, let axis, let ratio, let start, let end, let ccw) =
                edges[2]
            {
                #expect(center == DXF.Point2(8, 9) && axis == DXF.Point2(2, 1) && ratio == 0.5)
                #expect(start == 0 && end == 3.25 && !ccw)
            } else {
                Issue.record("edge 2 is not an ellipse")
            }
            if case .spline(let spline) = edges[3] {
                #expect(spline.degree == 3 && spline.isRational && !spline.isPeriodic)
                #expect(spline.knots == [0, 0, 1, 1])
                #expect(spline.controlPoints == [DXF.Point2(10, 11), DXF.Point2(12, 13)])
                #expect(spline.weights == [0.5, 2])
                if version >= .ac1024 {
                    #expect(spline.fitPoints == [DXF.Point2(10, 11), DXF.Point2(12, 13)])
                    #expect(spline.startTangent == DXF.Point2(1, 0))
                    #expect(spline.endTangent == DXF.Point2(0, 1))
                } else {
                    #expect(spline.fitPoints.isEmpty && spline.startTangent == nil)
                }
            } else {
                Issue.record("edge 3 is not a spline")
            }
        }
    }

    @Test("a hand-made hatch cut anywhere throws or reads, and does not trap")
    func syntheticHatchTruncation() throws {
        for version in Self.versions {
            let whole = Self.hatch(version: version).bytes()
            for length in 0..<whole.count {
                var reader = try? ObjectReader(
                    objects: Array(whole.prefix(length)), offset: 0, version: version,
                    textEncoding: .windowsCP1252)
                _ = try? reader?.readHatch()
            }
        }
    }

    /// A hatch that stops after one corrupt count, so the count is the only thing that can fail.
    static func hatchWithCount(
        version: DWG.Version, after fields: (inout DimensionObject) -> Void,
        count: Int32 = 0x7FFF_FFFF
    ) -> DimensionObject {
        var o = DimensionObject(version: version, type: ObjectType.hatch)
        if version >= .ac1018 {
            for _ in 0..<2 { o.main.bitLong(0) }
            o.main.bitDouble(0)
            o.main.bitDouble(0)
            o.main.bitLong(0)
            o.main.bitDouble(0)
            o.main.bitLong(0)
            if version < .ac1021 { o.main.text("") }
        }
        o.main.bitDouble(0)
        o.main.bitPoint3(0, 0, 1)
        if version < .ac1021 { o.main.text("") }
        o.main.bit(false)
        o.main.bit(false)
        fields(&o)
        o.main.bitLong(count)
        return o
    }

    @Test("a corrupt count in a hatch is refused as soon as it is read")
    func hatchCounts() throws {
        for version in Self.versions {
            for count in [Int32.max, 1_000_000, -1, Int32.min] {
                // The number of paths.
                let paths = Self.hatchWithCount(version: version, after: { _ in }, count: count)
                Self.expectInvalid { _ = try Self.read(hatch: paths) }
                // The number of vertices of a polyline path.
                let vertices = Self.hatchWithCount(
                    version: version,
                    after: {
                        $0.main.bitLong(1)
                        $0.main.bitLong(2)
                        $0.main.bit(false)
                        $0.main.bit(true)
                    }, count: count)
                Self.expectInvalid { _ = try Self.read(hatch: vertices) }
                // The number of edges of an edge path.
                let edges = Self.hatchWithCount(
                    version: version,
                    after: {
                        $0.main.bitLong(1)
                        $0.main.bitLong(1)
                    }, count: count)
                Self.expectInvalid { _ = try Self.read(hatch: edges) }
                // The number of boundary handles of a path with no edges.
                let sources = Self.hatchWithCount(
                    version: version,
                    after: {
                        $0.main.bitLong(1)
                        $0.main.bitLong(1)
                        $0.main.bitLong(0)
                    }, count: count)
                Self.expectInvalid { _ = try Self.read(hatch: sources) }
                // The number of knots of a spline edge.
                let knots = Self.hatchWithCount(
                    version: version,
                    after: {
                        $0.main.bitLong(1)
                        $0.main.bitLong(1)
                        $0.main.bitLong(1)
                        $0.main.byte(4)
                        $0.main.bitLong(3)
                        $0.main.bit(false)
                        $0.main.bit(false)
                    }, count: count)
                Self.expectInvalid { _ = try Self.read(hatch: knots) }
            }
            // The number of pattern lines, and of dashes in a line.
            let lines = Self.hatchWithCount(
                version: version,
                after: {
                    $0.main.bitLong(0)
                    $0.main.bitShort(1)
                    $0.main.bitShort(1)
                    $0.main.bitDouble(0)
                    $0.main.bitDouble(1)
                    $0.main.bit(false)
                    $0.main.bitShort(32767)
                }, count: 0)
            Self.expectInvalid { _ = try Self.read(hatch: lines) }
            let dashes = Self.hatchWithCount(
                version: version,
                after: {
                    $0.main.bitLong(0)
                    $0.main.bitShort(1)
                    $0.main.bitShort(1)
                    $0.main.bitDouble(0)
                    $0.main.bitDouble(1)
                    $0.main.bit(false)
                    $0.main.bitShort(1)
                    $0.main.bitDouble(0)
                    $0.main.bitDouble(0)
                    $0.main.bitDouble(0)
                    $0.main.bitDouble(0)
                    $0.main.bitDouble(0)
                    $0.main.bitShort(32767)
                }, count: 0)
            Self.expectInvalid { _ = try Self.read(hatch: dashes) }
            // The number of seed points, after a hatch with no paths and no pattern lines.
            for count in [Int32.max, -1] {
                let seeds = Self.hatchWithCount(
                    version: version,
                    after: {
                        $0.main.bitLong(0)
                        $0.main.bitShort(1)
                        $0.main.bitShort(1)
                        $0.main.bitDouble(0)
                        $0.main.bitDouble(1)
                        $0.main.bit(false)
                        $0.main.bitShort(0)
                    }, count: count)
                Self.expectInvalid { _ = try Self.read(hatch: seeds) }
            }
        }
    }

    // MARK: Dimensions

    /// A linear dimension with a value in every field, for releases from R2000.
    static func linearDimension(version: DWG.Version) -> DimensionObject {
        var o = DimensionObject(version: version, type: ObjectType.dimensionLinear)
        if version >= .ac1024 { o.main.byte(0) }
        o.main.bitPoint3(0, 0, 1)  // extrusion
        o.main.point2(11, 12)  // text mid point
        o.main.bitDouble(5)  // elevation
        o.main.byte(0b10)  // text at its default place, and an anonymous block
        if version < .ac1021 { o.main.text("4.5") }
        o.main.bitDouble(0.1)  // text rotation
        o.main.bitDouble(0.2)  // horizontal direction
        o.main.bitDouble(2)  // insertion scale
        o.main.bitDouble(3)
        o.main.bitDouble(4)
        o.main.bitDouble(0.3)  // insertion rotation
        o.main.bitShort(2)  // attachment point
        o.main.bitShort(1)  // line spacing style
        o.main.bitDouble(1.5)  // line spacing factor
        o.main.bitDouble(42)  // measurement
        if version >= .ac1021 {
            o.main.bit(false)  // not understood
            o.main.bit(true)  // first arrow flipped
            o.main.bit(false)
        }
        o.main.point2(21, 22)  // insertion point
        o.main.bitPoint3(1, 2, 3)  // first point
        o.main.bitPoint3(4, 5, 6)  // second point
        o.main.bitPoint3(7, 8, 9)  // definition point
        o.main.bitDouble(0.4)  // extension line rotation
        o.main.bitDouble(0.6)  // rotation
        o.handles.handle(0x3A)  // dimension style
        o.handles.handle(0x1F4)  // block
        return o
    }

    @Test("a linear dimension of R2000 and later reads as it was written")
    func syntheticLinearDimension() throws {
        for version in Self.versions {
            var reader = try Self.linearDimension(version: version).reader()
            let entity = try reader.readDimension()
            guard case .dimension(let dimension) = entity.geometry else {
                Issue.record("not a dimension")
                continue
            }
            #expect(dimension.kind == .linear)
            // The flag byte has bit 1 set, which is 32, and bit 0 clear, which is 128.
            #expect(dimension.typeFlags == 32 | 128)
            #expect(dimension.isTextUserDefinedLocation)
            #expect(dimension.formatVersion == (version >= .ac1024 ? 0 : nil))
            #expect(dimension.textMidPoint == DXF.Point(11, 12, 5))
            #expect(dimension.insertionPoint == DXF.Point(21, 22, 5))
            #expect(dimension.text == (version < .ac1021 ? "4.5" : ""))
            #expect(dimension.textRotation == 0.1 && dimension.horizontalDirection == 0.2)
            #expect(dimension.insertionScale == DXF.Point(2, 3, 4))
            #expect(dimension.insertionRotation == 0.3)
            #expect(dimension.attachmentPoint == 2 && dimension.lineSpacingStyle == 1)
            #expect(dimension.lineSpacingFactor == 1.5 && dimension.measurement == 42)
            #expect(dimension.flipArrow1 == (version >= .ac1021) && !dimension.flipArrow2)
            #expect(dimension.firstPoint == DXF.Point(1, 2, 3))
            #expect(dimension.secondPoint == DXF.Point(4, 5, 6))
            #expect(dimension.definitionPoint == DXF.Point(7, 8, 9))
            #expect(dimension.extLineRotation == 0.4 && dimension.rotation == 0.6)
            #expect(dimension.style == 0x3A && dimension.block == 0x1F4)
        }
    }

    @Test("a hand-made dimension cut anywhere throws or reads, and does not trap")
    func syntheticDimensionTruncation() throws {
        for version in Self.versions {
            let whole = Self.linearDimension(version: version).bytes()
            for length in 0..<whole.count {
                var reader = try? ObjectReader(
                    objects: Array(whole.prefix(length)), offset: 0, version: version,
                    textEncoding: .windowsCP1252)
                _ = try? reader?.readDimension()
            }
        }
    }

    // MARK: Leaders

    static func leader(version: DWG.Version, vertexCount: Int32 = 2) -> DimensionObject {
        var o = DimensionObject(version: version, type: ObjectType.leader)
        o.main.bit(false)
        o.main.bitShort(0)  // text annotation
        o.main.bitShort(1)  // spline
        o.main.bitLong(vertexCount)
        for index in 0..<max(0, min(Int(vertexCount), 2)) {
            o.main.bitPoint3(Double(index), Double(index) * 2, 0)
        }
        o.main.bitPoint3(0, 0, 0)  // origin
        o.main.bitPoint3(0, 0, 1)  // extrusion
        o.main.bitPoint3(1, 0, 0)  // horizontal direction
        o.main.bitPoint3(0, 0, 0)  // block offset
        o.main.bitPoint3(0, 0, 0)  // annotation offset
        if version <= .ac1021 {
            o.main.bitDouble(1.25)  // text height
            o.main.bitDouble(8.5)  // text width
        }
        o.main.bit(true)  // hook line on the horizontal direction
        o.main.bit(true)  // arrow head
        o.main.bitShort(0)
        o.main.bit(false)
        o.main.bit(false)
        o.handles.handle(0x201)  // annotation
        o.handles.handle(0x3A)  // dimension style
        return o
    }

    @Test("a leader of R2000 and later reads as it was written")
    func syntheticLeader() throws {
        for version in Self.versions {
            var reader = try Self.leader(version: version).reader()
            let entity = try reader.readLeader()
            guard case .leader(let leader) = entity.geometry else {
                Issue.record("not a leader")
                continue
            }
            #expect(leader.annotationType == 0 && leader.pathType == 1)
            #expect(leader.vertices == [DXF.Point(0, 0, 0), DXF.Point(1, 2, 0)])
            #expect(leader.hookLineOnHorizontalDirection && leader.hasArrowHead)
            #expect(leader.annotation == 0x201 && leader.style == 0x3A)
            if version <= .ac1021 {
                #expect(leader.textHeight == 1.25 && leader.textWidth == 8.5)
            } else {
                #expect(leader.textHeight == nil && leader.textWidth == nil)
            }
        }
    }

    @Test("a corrupt vertex count in a leader is refused as soon as it is read")
    func leaderCounts() throws {
        for version in Self.versions {
            for count in [Int32.max, 1_000_000, -1] {
                let object = Self.leader(version: version, vertexCount: count)
                Self.expectInvalid { _ = try Self.read(leader: object) }
            }
        }
    }

    @Test("a hand-made leader cut anywhere throws or reads, and does not trap")
    func syntheticLeaderTruncation() throws {
        for version in Self.versions {
            let whole = Self.leader(version: version).bytes()
            for length in 0..<whole.count {
                var reader = try? ObjectReader(
                    objects: Array(whole.prefix(length)), offset: 0, version: version,
                    textEncoding: .windowsCP1252)
                _ = try? reader?.readLeader()
            }
        }
    }

    // MARK: The count guard

    @Test("the count guard admits what fits and refuses the rest")
    func boundedCount() throws {
        var reader = try Self.leader(version: .ac1018).reader()
        _ = try reader.readEntityCommon()
        // The reader is at the start of the leader's own fields, with a few dozen bits left.
        #expect(try DimensionsSupport.boundedCount(0, bitsEach: 8, in: reader, what: "x") == 0)
        #expect(try DimensionsSupport.boundedCount(3, bitsEach: 8, in: reader, what: "x") == 3)
        #expect(throws: DWG.Error.self) {
            _ = try DimensionsSupport.boundedCount(-1, bitsEach: 8, in: reader, what: "x")
        }
        #expect(throws: DWG.Error.self) {
            _ = try DimensionsSupport.boundedCount(
                Int32.max, bitsEach: 1, in: reader, what: "x")
        }
        #expect(throws: DWG.Error.self) {
            _ = try DimensionsSupport.boundedCount(
                100_000, bitsEach: 8, stream: .handles, in: reader, what: "x")
        }
    }
}
