import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// Writes the bit-coded values of a DWG, the reverse of `BitReader`, for tests that need an
/// object no sample drawing has.
struct BitWriter {
    private(set) var bytes: [UInt8] = []
    private(set) var count = 0

    mutating func bit(_ value: Bool) {
        if count & 7 == 0 { bytes.append(0) }
        if value { bytes[count >> 3] |= 0x80 >> UInt8(count & 7) }
        count += 1
    }

    mutating func bits(_ value: UInt64, _ width: Int) {
        for shift in stride(from: width - 1, through: 0, by: -1) {
            bit((value >> UInt64(shift)) & 1 == 1)
        }
    }

    mutating func append(_ other: BitWriter) {
        for index in 0..<other.count {
            bit((other.bytes[index >> 3] >> UInt8(7 - (index & 7))) & 1 == 1)
        }
    }

    mutating func byte(_ value: UInt8) { bits(UInt64(value), 8) }

    private mutating func littleEndian(_ value: UInt64, size: Int) {
        for index in 0..<size { byte(UInt8(truncatingIfNeeded: value >> UInt64(8 * index))) }
    }

    mutating func rawShort(_ value: Int16) {
        littleEndian(UInt64(UInt16(bitPattern: value)), size: 2)
    }
    mutating func rawLong(_ value: Int32) {
        littleEndian(UInt64(UInt32(bitPattern: value)), size: 4)
    }
    mutating func rawDouble(_ value: Double) { littleEndian(value.bitPattern, size: 8) }

    /// Writes `value` over the 32 bits at `offset`, which must already be written.
    mutating func overwriteRawLong(atBit offset: Int, _ value: Int32) {
        let pattern = UInt32(bitPattern: value)
        for index in 0..<4 {
            for shift in 0..<8 {
                let position = offset + index * 8 + shift
                let mask: UInt8 = 0x80 >> UInt8(position & 7)
                if (pattern >> UInt32(8 * index)) >> UInt32(7 - shift) & 1 == 1 {
                    bytes[position >> 3] |= mask
                } else {
                    bytes[position >> 3] &= ~mask
                }
            }
        }
    }

    mutating func bitShort(_ value: Int16) {
        switch value {
        case 0: bits(2, 2)
        case 256: bits(3, 2)
        case 1...255:
            bits(1, 2)
            byte(UInt8(value))
        default:
            bits(0, 2)
            rawShort(value)
        }
    }

    mutating func bitLong(_ value: Int32) {
        switch value {
        case 0: bits(2, 2)
        case 1...255:
            bits(1, 2)
            byte(UInt8(value))
        default:
            bits(0, 2)
            rawLong(value)
        }
    }

    mutating func bitDouble(_ value: Double) {
        if value == 0 {
            bits(2, 2)
        } else if value == 1 {
            bits(1, 2)
        } else {
            bits(0, 2)
            rawDouble(value)
        }
    }

    /// A double coded against a default: two bits when it is the default, else the raw double.
    mutating func bitDouble(_ value: Double, default other: Double) {
        if value == other {
            bits(0, 2)
        } else {
            bits(3, 2)
            rawDouble(value)
        }
    }

    mutating func point(_ x: Double, _ y: Double, _ z: Double) {
        bitDouble(x)
        bitDouble(y)
        bitDouble(z)
    }

    /// A handle with the shortest form that holds it.
    mutating func handle(_ value: UInt64, code: UInt8 = 5) {
        var digits: [UInt8] = []
        var rest = value
        while rest != 0 {
            digits.insert(UInt8(rest & 0xFF), at: 0)
            rest >>= 8
        }
        byte(code << 4 | UInt8(digits.count))
        for digit in digits { byte(digit) }
    }

    /// A variable text: a length that counts the terminator, then the characters.
    mutating func text(_ value: String, unicode: Bool) {
        if unicode {
            let units = Array(value.utf16) + [0]
            bitShort(Int16(units.count))
            for unit in units { rawShort(Int16(bitPattern: unit)) }
        } else {
            let characters = Array(value.utf8) + [0]
            bitShort(Int16(characters.count))
            for character in characters { byte(character) }
        }
    }
}

/// One object laid out as an AutoCAD release writes it, for the release `version`.
///
/// It starts with the data every entity has (by default a model space entity on layer 0x10 with
/// default properties), and the test adds the entity's own fields to `main`, `handles` and, from
/// R2007, `strings`. This tests the reading of fields no sample drawing uses. It is written from
/// the same understanding of the format as the reader, so it shows the reader is consistent with
/// it and cannot trap, not that either is right: the oracle tests do that.
struct SyntheticObject {
    let version: DWG.Version
    let type: Int
    var main = BitWriter()
    var handles = BitWriter()
    var strings = BitWriter()
    private var sizeOffset: Int?

    /// Starts an object with the data every entity has.
    ///
    /// - Parameters:
    ///   - version: The release to lay the object out for.
    ///   - type: The object's type code.
    ///   - entityMode: 0 names an owner, 1 is the paper space and 2 the model space.
    ///   - owner: The owner's handle, written when `entityMode` is 0.
    ///   - links: The neighbours in the block's chain, or `nil` for the ones next to the entity.
    init(
        version: DWG.Version, type: Int, entityMode: Int = 2, owner: UInt64 = 0,
        links: (previous: UInt64, next: UInt64)? = nil
    ) {
        self.version = version
        self.type = type
        if version >= .ac1015 && version < .ac1024 {
            sizeOffset = main.count
            main.rawLong(0)
        }
        main.handle(0x1000, code: 0)  // the object's own handle
        main.bitShort(0)  // no extended data
        main.bit(false)  // no graphic
        if version <= .ac1014 {
            sizeOffset = main.count
            main.rawLong(0)
        }
        main.bits(UInt64(entityMode), 2)
        if entityMode == 0 { handles.handle(owner) }
        main.bitLong(0)  // no reactors
        if version >= .ac1018 {
            main.bit(true)  // no extension dictionary
        } else {
            handles.handle(0x20)  // the extension dictionary
        }
        if version >= .ac1027 { main.bit(false) }
        if version <= .ac1014 {
            handles.handle(0x10)  // layer
            main.bit(true)  // line type by layer
        }
        if version < .ac1018 {
            if let links {
                main.bit(false)
                handles.handle(links.previous)
                handles.handle(links.next)
            } else {
                main.bit(true)  // neighbours implied
            }
        }
        main.bitShort(version >= .ac1018 ? 0 : 256)  // colour
        main.bitDouble(1.0)  // line type scale
        guard version >= .ac1015 else {
            main.bitShort(0)  // not invisible
            return
        }
        handles.handle(0x10)  // layer
        main.bits(0, 2)  // line type by layer
        if version >= .ac1021 {
            main.bits(0, 2)  // no material
            main.byte(0)  // shadow flags
        }
        main.bits(0, 2)  // no plot style
        if version >= .ac1024 { main.bits(0, 3) }  // no visual styles
        main.bitShort(0)  // visible
        main.byte(0)  // line weight
    }

    /// Writes a text where this release keeps it.
    mutating func string(_ value: String) {
        if version >= .ac1021 {
            strings.text(value, unicode: true)
        } else {
            main.text(value, unicode: false)
        }
    }

    /// The object as bytes, to be read at offset 0.
    func bytes() -> [UInt8] {
        var head = BitWriter()
        if version >= .ac1024 {
            head.bits(0, 2)
            head.byte(UInt8(type))
        } else {
            head.bitShort(Int16(type))
        }

        var tail = BitWriter()
        if version >= .ac1021 {
            if strings.count > 0 {
                tail.append(strings)
                tail.rawShort(Int16(strings.count))
                tail.bit(true)
            } else {
                tail.bit(false)
            }
        }
        var body = main
        // The object ends on a byte, and from R2007 the string stream and its flag sit just
        // before the handles, so the padding goes before them.
        let total = head.count + body.count + tail.count + handles.count
        if version >= .ac1021 { body.bits(0, (8 - total % 8) % 8) }

        var all = head
        all.append(body)
        all.append(tail)
        let handleStart = all.count
        all.append(handles)
        if version < .ac1021 { all.bits(0, (8 - all.count % 8) % 8) }
        if let sizeOffset {
            all.overwriteRawLong(atBit: head.count + sizeOffset, Int32(handleStart))
        }

        func modularShort(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
        var out = modularShort(all.bytes.count)
        if version >= .ac1024 {
            var size = handles.count
            repeat {
                let more = size > 0x7F
                out.append(UInt8(size & 0x7F) | (more ? 0x80 : 0))
                size >>= 7
            } while size > 0
        }
        return out + all.bytes
    }

    func reader() throws -> ObjectReader {
        try ObjectReader(
            objects: bytes(), offset: 0, version: version, textEncoding: .windowsCP1252)
    }
}

/// Builds the entities this file tests.
enum SyntheticEntities {
    struct Text {
        var flags: UInt8 = 0
        var elevation = 2.5
        var insertion = (x: 10.0, y: 20.0)
        var alignment = (x: 10.0, y: 22.0)
        var extrusion = (x: 0.0, y: 0.0, z: 1.0)
        var thickness = 0.5
        var oblique = 0.25
        var rotation = 0.75
        var height = 3.0
        var widthFactor = 0.8
        var value = "Hi there"
        var generation: Int16 = 2
        var horizontal: Int16 = 1
        var vertical: Int16 = 2
        var style: UInt64 = 0x31
    }

    static func text(_ spec: Text, version: DWG.Version) -> SyntheticObject {
        var object = SyntheticObject(version: version, type: ObjectType.text)
        let isDefaultNormal = spec.extrusion == (0, 0, 1)
        if version <= .ac1014 {
            object.main.bitDouble(spec.elevation)
            object.main.rawDouble(spec.insertion.x)
            object.main.rawDouble(spec.insertion.y)
            object.main.rawDouble(spec.alignment.x)
            object.main.rawDouble(spec.alignment.y)
            object.main.point(spec.extrusion.x, spec.extrusion.y, spec.extrusion.z)
            object.main.bitDouble(spec.thickness)
            object.main.bitDouble(spec.oblique)
            object.main.bitDouble(spec.rotation)
            object.main.bitDouble(spec.height)
            object.main.bitDouble(spec.widthFactor)
            object.string(spec.value)
            object.main.bitShort(spec.generation)
            object.main.bitShort(spec.horizontal)
            object.main.bitShort(spec.vertical)
            object.handles.handle(spec.style)
            return object
        }
        let flags = spec.flags
        object.main.byte(flags)
        if flags & 0x01 == 0 { object.main.rawDouble(spec.elevation) }
        object.main.rawDouble(spec.insertion.x)
        object.main.rawDouble(spec.insertion.y)
        if flags & 0x02 == 0 {
            object.main.bitDouble(spec.alignment.x, default: spec.insertion.x)
            object.main.bitDouble(spec.alignment.y, default: spec.insertion.y)
        }
        object.main.bit(isDefaultNormal)
        if !isDefaultNormal {
            object.main.point(spec.extrusion.x, spec.extrusion.y, spec.extrusion.z)
        }
        object.main.bit(spec.thickness == 0)
        if spec.thickness != 0 { object.main.bitDouble(spec.thickness) }
        if flags & 0x04 == 0 { object.main.rawDouble(spec.oblique) }
        if flags & 0x08 == 0 { object.main.rawDouble(spec.rotation) }
        object.main.rawDouble(spec.height)
        if flags & 0x10 == 0 { object.main.rawDouble(spec.widthFactor) }
        object.string(spec.value)
        if flags & 0x20 == 0 { object.main.bitShort(spec.generation) }
        if flags & 0x40 == 0 { object.main.bitShort(spec.horizontal) }
        if flags & 0x80 == 0 { object.main.bitShort(spec.vertical) }
        object.handles.handle(spec.style)
        return object
    }

    struct MText {
        var fill = false
        var colorFlags: UInt8 = 0
        var colorWord: UInt32 = 0xC200_0000 | 0x00AB_CDEF
        var annotative = false
        var columnType: Int16 = 2
        var autoHeight = false
        var heightCount: Int32 = 2
    }

    static func mtext(_ spec: MText, version: DWG.Version) -> SyntheticObject {
        var object = SyntheticObject(version: version, type: ObjectType.mtext)
        object.main.point(1, 2, 3)
        object.main.point(0, 0, 1)
        object.main.point(0, 1, 0)
        object.main.bitDouble(40.5)  // rectangle width
        if version >= .ac1021 { object.main.bitDouble(7.5) }  // rectangle height
        object.main.bitDouble(2.5)  // height
        object.main.bitShort(5)  // attachment
        object.main.bitShort(3)  // direction
        object.main.bitDouble(6.5)  // extents height
        object.main.bitDouble(30.5)  // extents width
        object.string("one\\Ptwo")
        object.handles.handle(0x31)
        if version >= .ac1015 {
            object.main.bitShort(2)
            object.main.bitDouble(1.5)
            object.main.bit(false)
        }
        if version >= .ac1018 {
            object.main.bitLong(spec.fill ? 3 : 0)
            if spec.fill {
                object.main.bitDouble(1.25)
                object.main.bitShort(0)
                object.main.bitLong(Int32(bitPattern: spec.colorWord))
                object.main.byte(spec.colorFlags)
                if spec.colorFlags & 1 != 0 { object.string("name") }
                if spec.colorFlags & 2 != 0 { object.string("book") }
                object.main.bitLong(25)
            }
        }
        if version >= .ac1032 {
            object.main.bit(!spec.annotative)
            if !spec.annotative {
                object.main.bitShort(0)
                object.main.bit(true)
                object.handles.handle(0x55)
                object.main.bitLong(5)
                object.main.point(0, 1, 0)
                object.main.point(1, 2, 3)
                for value in [40.5, 7.5, 30.5, 6.5] { object.main.bitDouble(value) }
                object.main.bitShort(spec.columnType)
                if spec.columnType != 0 {
                    object.main.bitLong(spec.heightCount)
                    object.main.bitDouble(12.5)
                    object.main.bitDouble(2.5)
                    object.main.bit(spec.autoHeight)
                    object.main.bit(true)
                    if !spec.autoHeight, spec.columnType == 2 {
                        // A count that is a lie has only two heights behind it.
                        for index in 0..<min(2, max(0, Int(spec.heightCount))) {
                            object.main.bitDouble(Double(index) + 9.5)
                        }
                    }
                }
            }
        }
        return object
    }

    struct Insert {
        var scaleCase = 0
        var scale = (x: 2.0, y: 3.0, z: 4.0)
        var attributes: [UInt64] = []
        var hasAttributes = false
        var ownedCount: Int32?
        var grid: (columns: Int16, rows: Int16, columnSpacing: Double, rowSpacing: Double)?
    }

    static func insert(_ spec: Insert, version: DWG.Version) -> SyntheticObject {
        var object = SyntheticObject(
            version: version, type: spec.grid == nil ? ObjectType.insert : ObjectType.minsert)
        object.main.point(5, 6, 7)
        if version <= .ac1014 {
            object.main.bitDouble(spec.scale.x)
            object.main.bitDouble(spec.scale.y)
            object.main.bitDouble(spec.scale.z)
        } else {
            object.main.bits(UInt64(spec.scaleCase), 2)
            switch spec.scaleCase {
            case 0:
                object.main.rawDouble(spec.scale.x)
                object.main.bitDouble(spec.scale.y, default: spec.scale.x)
                object.main.bitDouble(spec.scale.z, default: spec.scale.x)
            case 1:
                object.main.bitDouble(spec.scale.y, default: 1.0)
                object.main.bitDouble(spec.scale.z, default: 1.0)
            case 2:
                object.main.rawDouble(spec.scale.x)
            default: break
            }
        }
        object.main.bitDouble(0.5)  // rotation
        object.main.point(0, 0, 1)
        object.main.bit(spec.hasAttributes)
        if version >= .ac1018, spec.hasAttributes {
            object.main.bitLong(spec.ownedCount ?? Int32(spec.attributes.count))
        }
        if let grid = spec.grid {
            object.main.bitShort(grid.columns)
            object.main.bitShort(grid.rows)
            object.main.bitDouble(grid.columnSpacing)
            object.main.bitDouble(grid.rowSpacing)
        }
        object.handles.handle(0x77)  // block record
        if spec.hasAttributes {
            if version <= .ac1015 {
                object.handles.handle(spec.attributes.first ?? 0)
                object.handles.handle(spec.attributes.last ?? 0)
            } else {
                for attribute in spec.attributes { object.handles.handle(attribute) }
            }
            object.handles.handle(0x99)  // SEQEND
        }
        return object
    }
}

@Suite("TEXT, MTEXT, INSERT and MINSERT from constructed objects")
struct SyntheticTextTests {
    /// The releases whose layout the object framework reads and the container does not yet.
    static let versions: [DWG.Version] = [.ac1015, .ac1018, .ac1021, .ac1024, .ac1032]

    @Test("a TEXT with every field present reads back in every release")
    func textWithEveryField() throws {
        var spec = SyntheticEntities.Text()
        spec.extrusion = (0, 1, 0)
        for version in Self.versions + [.ac1014] {
            var reader = try SyntheticEntities.text(spec, version: version).reader()
            guard case .text(let text)? = try reader.readEntity()?.geometry else {
                Issue.record("\(version) did not read a TEXT")
                continue
            }
            #expect(text.insertion == DXF.Point(10, 20, 2.5), "\(version)")
            #expect(text.alignmentPoint == DXF.Point(10, 22, 2.5), "\(version)")
            #expect(text.extrusion == DXF.Point(0, 1, 0), "\(version)")
            #expect(text.thickness == 0.5 && text.obliqueAngle == 0.25, "\(version)")
            #expect(text.rotation == 0.75 && text.height == 3, "\(version)")
            #expect(text.widthFactor == 0.8 && text.value == "Hi there", "\(version)")
            #expect(text.generation == 2 && text.horizontalAlignment == 1, "\(version)")
            #expect(text.verticalAlignment == 2 && text.style == 0x31, "\(version)")
        }
    }

    @Test("a TEXT whose flags leave every field out gets the defaults")
    func textWithNoOptionalField() throws {
        var spec = SyntheticEntities.Text()
        spec.flags = 0xFF
        spec.thickness = 0
        for version in Self.versions {
            var reader = try SyntheticEntities.text(spec, version: version).reader()
            guard case .text(let text)? = try reader.readEntity()?.geometry else {
                Issue.record("\(version) did not read a TEXT")
                continue
            }
            #expect(text.insertion == DXF.Point(10, 20, 0), "\(version)")
            #expect(text.alignmentPoint == nil, "\(version)")
            #expect(text.extrusion == DXF.Point(0, 0, 1) && text.thickness == 0, "\(version)")
            #expect(text.obliqueAngle == 0 && text.rotation == 0, "\(version)")
            #expect(text.widthFactor == 1.0 && text.height == 3, "\(version)")
            #expect(text.generation == 0 && text.horizontalAlignment == 0, "\(version)")
            #expect(text.verticalAlignment == 0 && text.value == "Hi there", "\(version)")
        }
    }

    @Test("each flag of a TEXT controls only its own field")
    func textFlagsOneByOne() throws {
        for bit in 0..<8 {
            var spec = SyntheticEntities.Text()
            spec.flags = UInt8(1 << bit)
            var reader = try SyntheticEntities.text(spec, version: .ac1018).reader()
            guard case .text(let text)? = try reader.readEntity()?.geometry else {
                Issue.record("bit \(bit) did not read a TEXT")
                continue
            }
            #expect((text.insertion.z == 0) == (bit == 0), "bit \(bit)")
            #expect((text.alignmentPoint == nil) == (bit == 1), "bit \(bit)")
            #expect((text.obliqueAngle == 0) == (bit == 2), "bit \(bit)")
            #expect((text.rotation == 0) == (bit == 3), "bit \(bit)")
            #expect((text.widthFactor == 1) == (bit == 4), "bit \(bit)")
            #expect((text.generation == 0) == (bit == 5), "bit \(bit)")
            #expect((text.horizontalAlignment == 0) == (bit == 6), "bit \(bit)")
            #expect((text.verticalAlignment == 0) == (bit == 7), "bit \(bit)")
            #expect(text.value == "Hi there" && text.style == 0x31, "bit \(bit)")
        }
    }

    @Test("an MTEXT reads back in every release, with what each release adds")
    func mtext() throws {
        var spec = SyntheticEntities.MText()
        spec.fill = true
        for version in Self.versions {
            var reader = try SyntheticEntities.mtext(spec, version: version).reader()
            guard case .mtext(let text)? = try reader.readEntity()?.geometry else {
                Issue.record("\(version) did not read an MTEXT")
                continue
            }
            #expect(text.insertion == DXF.Point(1, 2, 3), "\(version)")
            #expect(text.xAxisDirection == DXF.Point(0, 1, 0), "\(version)")
            #expect(text.rectangleWidth == 40.5 && text.height == 2.5, "\(version)")
            #expect(text.rectangleHeight == (version >= .ac1021 ? 7.5 : 0), "\(version)")
            #expect(text.attachment == 5 && text.drawingDirection == 3, "\(version)")
            #expect(text.extentsHeight == 6.5 && text.extentsWidth == 30.5, "\(version)")
            #expect(text.value == "one\\Ptwo" && text.style == 0x31, "\(version)")
            #expect(text.lineSpacingStyle == (version >= .ac1015 ? 2 : 1), "\(version)")
            #expect(text.lineSpacingFactor == (version >= .ac1015 ? 1.5 : 1), "\(version)")
            if version >= .ac1018 {
                #expect(text.backgroundFillFlags == 3 && text.backgroundScale == 1.25, "\(version)")
                #expect(
                    text.backgroundColor == .rgb(red: 0xAB, green: 0xCD, blue: 0xEF), "\(version)")
                #expect(text.backgroundTransparency == 25, "\(version)")
            } else {
                #expect(text.backgroundFillFlags == 0 && text.backgroundScale == 1.5, "\(version)")
            }
            if version >= .ac1032 {
                #expect(!text.isAnnotative, "\(version)")
                #expect(
                    text.columns
                        == MTextData.Columns(
                            type: 2, width: 12.5, gutter: 2.5, autoHeight: false,
                            flowReversed: true, heights: [9.5, 10.5]), "\(version)")
            } else {
                #expect(text.columns == nil, "\(version)")
            }
        }
    }

    @Test("an annotative MTEXT, and one with no columns, end where the format says")
    func mtextWithoutColumns() throws {
        var spec = SyntheticEntities.MText()
        spec.annotative = true
        var reader = try SyntheticEntities.mtext(spec, version: .ac1032).reader()
        if case .mtext(let text)? = try reader.readEntity()?.geometry {
            #expect(text.isAnnotative && text.columns == nil)
        } else {
            Issue.record("not an MTEXT")
        }

        spec.annotative = false
        spec.columnType = 0
        reader = try SyntheticEntities.mtext(spec, version: .ac1032).reader()
        if case .mtext(let text)? = try reader.readEntity()?.geometry {
            #expect(!text.isAnnotative && text.columns == nil)
        } else {
            Issue.record("not an MTEXT")
        }

        // Static columns and dynamic columns with an automatic height give no heights.
        spec.columnType = 1
        reader = try SyntheticEntities.mtext(spec, version: .ac1032).reader()
        if case .mtext(let text)? = try reader.readEntity()?.geometry {
            #expect(text.columns?.type == 1 && text.columns?.heights == [])
        } else {
            Issue.record("not an MTEXT")
        }
    }

    @Test(
        "the colour names after an MTEXT background colour are read, so the fields after it line up"
    )
    func mtextBackgroundColorNames() throws {
        for flags: UInt8 in [0, 1, 2, 3] {
            for version in [DWG.Version.ac1018, .ac1024, .ac1032] {
                var spec = SyntheticEntities.MText()
                spec.fill = true
                spec.colorFlags = flags
                var reader = try SyntheticEntities.mtext(spec, version: version).reader()
                if case .mtext(let text)? = try reader.readEntity()?.geometry {
                    #expect(text.backgroundTransparency == 25, "\(version) flags \(flags)")
                    #expect(text.backgroundColor == .rgb(red: 0xAB, green: 0xCD, blue: 0xEF))
                } else {
                    Issue.record("not an MTEXT")
                }
            }
        }
    }

    @Test("a colour word is read as by layer, an index or RGB")
    func colorWords() throws {
        let cases: [(UInt32, DWGColor)] = [
            (0xC000_0000, .byLayer), (0xC100_0000, .byBlock), (0xC300_0005, .index(5)),
            (0xC200_1122, .rgb(red: 0, green: 0x11, blue: 0x22)),
        ]
        for (word, expected) in cases {
            var spec = SyntheticEntities.MText()
            spec.fill = true
            spec.colorWord = word
            var reader = try SyntheticEntities.mtext(spec, version: .ac1018).reader()
            if case .mtext(let text)? = try reader.readEntity()?.geometry {
                #expect(text.backgroundColor == expected, "\(String(word, radix: 16))")
            } else {
                Issue.record("not an MTEXT")
            }
        }
    }

    @Test("every scale coding of an INSERT reads back, in each release")
    func insertScales() throws {
        // The coding, and the scale it has to give. Some leave y and z at the default the coding
        // names, which is x for coding 0 and 1.0 for coding 1.
        let cases: [(Int, (x: Double, y: Double, z: Double))] = [
            (0, (2, 3, 4)), (0, (2, 2, 4)), (0, (2, 3, 2)), (0, (2, 2, 2)), (1, (1, 3, 4)),
            (1, (1, 1, 4)),
            (1, (1, 1, 1)), (2, (2, 2, 2)), (3, (1, 1, 1)),
        ]
        for version in Self.versions + [.ac1014] {
            for (scaleCase, scale) in cases {
                // Before R2000 the scale is always three numbers, so one coding stands for all.
                if version <= .ac1014 && scaleCase != 0 { continue }
                var spec = SyntheticEntities.Insert()
                spec.scaleCase = scaleCase
                spec.scale = scale
                var reader = try SyntheticEntities.insert(spec, version: version).reader()
                guard case .insert(let insert)? = try reader.readEntity()?.geometry else {
                    Issue.record("\(version) case \(scaleCase) did not read an INSERT")
                    continue
                }
                #expect(insert.insertion == DXF.Point(5, 6, 7), "\(version) \(scaleCase)")
                #expect(
                    insert.xScale == scale.x && insert.yScale == scale.y
                        && insert.zScale == scale.z, "\(version) \(scaleCase) \(scale)")
                #expect(insert.rotation == 0.5, "\(version) \(scaleCase)")
                #expect(insert.blockHeader == 0x77 && insert.grid == nil, "\(version)")
                #expect(!insert.hasAttributes && insert.seqend == 0, "\(version)")
            }
        }
    }

    @Test("an INSERT with attributes keeps its attribute and SEQEND handles")
    func insertAttributes() throws {
        for version in Self.versions + [.ac1014] {
            var spec = SyntheticEntities.Insert()
            spec.hasAttributes = true
            spec.attributes = [0x80, 0x81, 0x82]
            var reader = try SyntheticEntities.insert(spec, version: version).reader()
            guard case .insert(let insert)? = try reader.readEntity()?.geometry else {
                Issue.record("\(version) did not read an INSERT")
                continue
            }
            #expect(insert.hasAttributes && insert.seqend == 0x99, "\(version)")
            if version <= .ac1015 {
                #expect(insert.firstAttribute == 0x80 && insert.lastAttribute == 0x82, "\(version)")
                #expect(insert.attributes.isEmpty, "\(version)")
            } else {
                #expect(insert.attributes == [0x80, 0x81, 0x82], "\(version)")
                #expect(insert.firstAttribute == 0 && insert.lastAttribute == 0, "\(version)")
            }
        }
    }

    @Test("a MINSERT adds its columns, rows and spacing to what an INSERT has")
    func minsert() throws {
        for version in Self.versions + [.ac1014] {
            var spec = SyntheticEntities.Insert()
            spec.grid = (columns: 4, rows: 3, columnSpacing: 2.5, rowSpacing: 1.5)
            spec.hasAttributes = true
            spec.attributes = [0x80]
            var reader = try SyntheticEntities.insert(spec, version: version).reader()
            guard case .insert(let insert)? = try reader.readEntity()?.geometry else {
                Issue.record("\(version) did not read a MINSERT")
                continue
            }
            #expect(
                insert.grid
                    == InsertData.Grid(
                        columnCount: 4, rowCount: 3, columnSpacing: 2.5, rowSpacing: 1.5),
                "\(version)")
            #expect(insert.blockHeader == 0x77 && insert.seqend == 0x99, "\(version)")
        }
    }

    @Test("a MINSERT with more than 32767 columns reads them as unsigned")
    func minsertUnsignedCounts() throws {
        var spec = SyntheticEntities.Insert()
        spec.grid = (columns: Int16(bitPattern: 40000), rows: 1, columnSpacing: 1, rowSpacing: 1)
        var reader = try SyntheticEntities.insert(spec, version: .ac1018).reader()
        if case .insert(let insert)? = try reader.readEntity()?.geometry {
            #expect(insert.grid?.columnCount == 40000)
        } else {
            Issue.record("not a MINSERT")
        }
    }

    @Test("a count that the data cannot hold is an error, not a loop or a crash")
    func absurdCounts() throws {
        var spec = SyntheticEntities.Insert()
        spec.hasAttributes = true
        spec.attributes = [0x80]
        spec.ownedCount = Int32.max
        for version in [DWG.Version.ac1018, .ac1024, .ac1032] {
            var reader = try SyntheticEntities.insert(spec, version: version).reader()
            #expect(throws: DWG.Error.self, "\(version)") { _ = try reader.readEntity() }
        }
        spec.ownedCount = -1
        var reader = try SyntheticEntities.insert(spec, version: .ac1018).reader()
        #expect(throws: DWG.Error.self) { _ = try reader.readEntity() }

        var mtext = SyntheticEntities.MText()
        mtext.heightCount = Int32.max
        var mreader = try SyntheticEntities.mtext(mtext, version: .ac1032).reader()
        #expect(throws: DWG.Error.self) { _ = try mreader.readEntity() }
    }

    @Test("a count is checked against the negative, the ceiling and the data left")
    func checkedCount() throws {
        #expect(try ObjectReader.checkedCount(3, bitsPerItem: 8, bitsLeft: 24, what: "x") == 3)
        #expect(try ObjectReader.checkedCount(0, bitsPerItem: 8, bitsLeft: 0, what: "x") == 0)
        #expect(throws: DWG.Error.self) {
            _ = try ObjectReader.checkedCount(-1, bitsPerItem: 8, bitsLeft: 100, what: "x")
        }
        #expect(throws: DWG.Error.self) {
            _ = try ObjectReader.checkedCount(4, bitsPerItem: 8, bitsLeft: 24, what: "x")
        }
        #expect(throws: DWG.Error.self) {
            _ = try ObjectReader.checkedCount(
                (1 << 20) + 1, bitsPerItem: 1, bitsLeft: Int.max / 2, what: "x")
        }
    }

    /// One object of each kind and release, for the tests that cut and corrupt them.
    static func objects() -> [(name: String, object: SyntheticObject)] {
        var out: [(String, SyntheticObject)] = []
        var insert = SyntheticEntities.Insert()
        insert.hasAttributes = true
        insert.attributes = [0x80, 0x81]
        var minsert = insert
        minsert.grid = (columns: 2, rows: 2, columnSpacing: 1, rowSpacing: 1)
        var mtext = SyntheticEntities.MText()
        mtext.fill = true
        mtext.colorFlags = 3
        for version in versions + [.ac1014] {
            out.append(("TEXT \(version)", SyntheticEntities.text(.init(), version: version)))
            out.append(("MTEXT \(version)", SyntheticEntities.mtext(mtext, version: version)))
            out.append(("INSERT \(version)", SyntheticEntities.insert(insert, version: version)))
            out.append(("MINSERT \(version)", SyntheticEntities.insert(minsert, version: version)))
        }
        return out
    }

    @Test("an object cut short anywhere throws instead of reading past its end")
    func truncation() throws {
        for (name, object) in Self.objects() {
            var whole = try object.reader()
            let mainStart = whole.main.position
            let handleStart = whole.handles.position
            _ = try #require(try whole.readEntity(), "\(name)")
            let mainUsed = (whole.main.position - 1) / 8
            let handlesUsed = (whole.handles.position - 1) / 8

            // Cutting the data before the last byte that was read must stop the read.
            for length in 0...mainUsed {
                var reader = try object.reader()
                reader.main = BitReader(
                    Array(reader.main.bytes.prefix(length)), version: object.version,
                    position: mainStart)
                #expect(throws: (any Error).self, "\(name) main cut at \(length)") {
                    _ = try reader.readEntity()
                }
            }
            for length in 0...handlesUsed {
                var reader = try object.reader()
                reader.handles = BitReader(
                    Array(reader.handles.bytes.prefix(length)), version: object.version,
                    position: handleStart)
                #expect(throws: (any Error).self, "\(name) handles cut at \(length)") {
                    _ = try reader.readEntity()
                }
            }
        }
    }

    @Test("an object with any byte damaged reads or throws, and never traps or hangs")
    func damage() throws {
        for (_, object) in Self.objects() {
            let size = object.bytes().count
            for index in 0..<size {
                for mask: UInt8 in [0xFF, 0x80, 0x55, 0x01] {
                    var bytes = object.bytes()
                    bytes[index] ^= mask
                    guard
                        var reader = try? ObjectReader(
                            objects: bytes, offset: 0, version: object.version,
                            textEncoding: .windowsCP1252)
                    else { continue }
                    _ = try? reader.readEntity()
                }
            }
        }
    }
}
