// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readText, readCommonTextData, readMText). See NOTICE.md. The field order is the format's own,
// from the Open Design Specification for .dwg files.

import SwiftDXF

/// The fields of a TEXT entity, in the file's own terms: angles in radians, points and the
/// extrusion in the entity's own coordinate system.
struct TextData: Equatable {
    /// Where the text is placed (DXF 10, 20, 30), with the elevation as its z.
    var insertion = DXF.Point(0, 0, 0)
    /// The second alignment point (DXF 11, 21, 31), or `nil` when the file gives none.
    var alignmentPoint: DXF.Point?
    /// The normal of the plane the text lies in (DXF 210, 220, 230).
    var extrusion = DXF.Point(0, 0, 1)
    /// The thickness the text is extruded by (DXF 39).
    var thickness = 0.0
    /// The slant of the letters, in radians from the vertical (DXF 51).
    var obliqueAngle = 0.0
    /// The angle of the text line, in radians (DXF 50).
    var rotation = 0.0
    /// The height of the letters (DXF 40).
    var height = 0.0
    /// The width of a letter relative to its height (DXF 41), 1.0 when the file leaves it out.
    var widthFactor = 1.0
    /// The text itself (DXF 1).
    var value = ""
    /// The generation flags: bit 2 mirrors the text backwards, bit 4 upside down (DXF 71).
    var generation = 0
    /// The horizontal alignment: 0 left, 1 centre, 2 right, 3 aligned, 4 middle, 5 fit (DXF 72).
    var horizontalAlignment = 0
    /// The vertical alignment: 0 baseline, 1 bottom, 2 middle, 3 top (DXF 73).
    var verticalAlignment = 0
    /// The handle of the text style (DXF 7 names it).
    var style: UInt64 = 0
}

/// The fields of an MTEXT entity, in the file's own terms: angles in radians, points and the
/// extrusion as the file stores them.
struct MTextData: Equatable {
    /// The column layout of an MTEXT that has columns, which only R2018 and later files carry.
    struct Columns: Equatable {
        /// 1 for columns of a fixed width, 2 for columns that grow with the text.
        var type = 0
        /// The width of one column.
        var width = 0.0
        /// The space between two columns.
        var gutter = 0.0
        /// Whether the column height follows the text instead of being given.
        var autoHeight = false
        /// Whether the text flows from the last column to the first.
        var flowReversed = false
        /// The height of each column, given only for dynamic columns without auto height.
        var heights: [Double] = []
    }

    /// The first picked point (DXF 10, 20, 30); where it sits in the text depends on `attachment`.
    var insertion = DXF.Point(0, 0, 0)
    /// The normal of the plane the text lies in (DXF 210, 220, 230).
    var extrusion = DXF.Point(0, 0, 1)
    /// The direction of the text line, which says how it is rotated (DXF 11, 21, 31).
    var xAxisDirection = DXF.Point(1, 0, 0)
    /// The width of the box the text is wrapped to (DXF 41).
    var rectangleWidth = 0.0
    /// The height of that box (DXF 46), 0 before R2007.
    var rectangleHeight = 0.0
    /// The height of the letters (DXF 40).
    var height = 0.0
    /// Where the insertion point sits in the text box: 1 to 9, top left to bottom right (DXF 71).
    var attachment = 0
    /// The reading direction: 1 left to right, 3 top to bottom, 5 by style (DXF 72).
    var drawingDirection = 0
    /// The height the text takes up, as AutoCAD measured it (DXF 43).
    var extentsHeight = 0.0
    /// The width the text takes up, as AutoCAD measured it (DXF 42).
    var extentsWidth = 0.0
    /// The text with its formatting codes, all in one string (DXF 1 and 3 joined).
    var value = ""
    /// The handle of the text style (DXF 7 names it).
    var style: UInt64 = 0
    /// How line spacing is read: 1 at least, 2 exactly (DXF 73), 1 before R2000.
    var lineSpacingStyle = 1
    /// The line spacing factor (DXF 44), 1.0 before R2000.
    var lineSpacingFactor = 1.0
    /// The background flags: 1 fill, 2 fill with the drawing's colour, 0x10 text frame (DXF 90).
    var backgroundFillFlags = 0
    /// The size of the background relative to the text (DXF 45), 1.5 unless the file gives it.
    var backgroundScale = 1.5
    /// The background colour (DXF 63, 421, 431), given when the background is filled.
    var backgroundColor: DWGColor = .byLayer
    /// The background transparency word as stored (DXF 441), 0 unless the file gives it.
    var backgroundTransparency: Int32 = 0
    /// Whether the text is annotative, which only R2018 and later files say.
    var isAnnotative = false
    /// The columns, or `nil` when the text has none.
    var columns: Columns?
}

extension DXF.Point {
    fileprivate init(_ triple: (x: Double, y: Double, z: Double)) {
        self.init(triple.x, triple.y, triple.z)
    }
}

extension ObjectReader {
    mutating func readTextEntity() throws -> DecodedEntity {
        let common = try readEntityCommon()
        return DecodedEntity(common: common, geometry: .text(try readTextFields()))
    }

    /// Reads the fields of a TEXT that follow the entity's common data.
    ///
    /// ATTRIB and ATTDEF carry the same fields, so a decoder for them can use this too.
    mutating func readTextFields() throws -> TextData {
        var data = TextData()

        if version <= .ac1014 {
            // R13 and R14 give everything outright, with a single elevation for both points.
            let elevation = try main.readBitDouble()
            let insertion = try main.read2RawDouble()
            data.insertion = DXF.Point(insertion.x, insertion.y, elevation)
            let alignment = try main.read2RawDouble()
            data.alignmentPoint = DXF.Point(alignment.x, alignment.y, elevation)
            data.extrusion = DXF.Point(try main.readBitExtrusion())
            data.thickness = try main.readBitThickness()
            data.obliqueAngle = try main.readBitDouble()
            data.rotation = try main.readBitDouble()
            data.height = try main.readBitDouble()
            data.widthFactor = try main.readBitDouble()
            data.value = try readText()
            data.generation = Int(try main.readBitShort())
            data.horizontalAlignment = Int(try main.readBitShort())
            data.verticalAlignment = Int(try main.readBitShort())
            data.style = try readOwnHandle()
            return data
        }

        // From R2000 a flags byte says which fields are left out because they have their default
        // value: a set bit means the field is absent. Bit 0x01 is the elevation, 0x02 the
        // alignment point, 0x04 the oblique angle, 0x08 the rotation, 0x10 the width factor,
        // 0x20 the generation, 0x40 the horizontal alignment and 0x80 the vertical alignment.
        let flags = try main.readByte()
        var elevation = 0.0
        if flags & 0x01 == 0 { elevation = try main.readRawDouble() }
        let insertion = try main.read2RawDouble()
        data.insertion = DXF.Point(insertion.x, insertion.y, elevation)
        if flags & 0x02 == 0 {
            // The alignment point is coded against the insertion point.
            let x = try main.readBitDouble(default: insertion.x)
            let y = try main.readBitDouble(default: insertion.y)
            data.alignmentPoint = DXF.Point(x, y, elevation)
        }
        data.extrusion = DXF.Point(try main.readBitExtrusion())
        data.thickness = try main.readBitThickness()
        if flags & 0x04 == 0 { data.obliqueAngle = try main.readRawDouble() }
        if flags & 0x08 == 0 { data.rotation = try main.readRawDouble() }
        data.height = try main.readRawDouble()
        if flags & 0x10 == 0 { data.widthFactor = try main.readRawDouble() }
        data.value = try readText()
        if flags & 0x20 == 0 { data.generation = Int(try main.readBitShort()) }
        if flags & 0x40 == 0 { data.horizontalAlignment = Int(try main.readBitShort()) }
        if flags & 0x80 == 0 { data.verticalAlignment = Int(try main.readBitShort()) }
        data.style = try readOwnHandle()
        return data
    }

    mutating func readMText() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var data = MTextData()

        data.insertion = DXF.Point(try main.read3BitDouble())
        data.extrusion = DXF.Point(try main.read3BitDouble())
        data.xAxisDirection = DXF.Point(try main.read3BitDouble())
        data.rectangleWidth = try main.readBitDouble()
        if version >= .ac1021 { data.rectangleHeight = try main.readBitDouble() }
        data.height = try main.readBitDouble()
        data.attachment = Int(try main.readBitShort())
        data.drawingDirection = Int(try main.readBitShort())
        data.extentsHeight = try main.readBitDouble()
        data.extentsWidth = try main.readBitDouble()
        data.value = try readText()
        data.style = try readOwnHandle()

        if version >= .ac1015 {
            data.lineSpacingStyle = Int(try main.readBitShort())
            data.lineSpacingFactor = try main.readBitDouble()
            _ = try main.readBit()  // a flag the format does not explain
        }

        if version >= .ac1018 {
            data.backgroundFillFlags = Int(try main.readBitLong())
            // The background colour is there for a filled background, and from R2018 also for a
            // text frame.
            let hasFill = data.backgroundFillFlags & 0x01 != 0
            let hasFrame = version >= .ac1032 && data.backgroundFillFlags & 0x10 != 0
            if hasFill || hasFrame {
                data.backgroundScale = try main.readBitDouble()
                data.backgroundColor = try readCmColor()
                data.backgroundTransparency = try main.readBitLong()
            }
        }

        if version >= .ac1032 { try readMTextAnnotation(into: &data) }
        return DecodedEntity(common: common, geometry: .mtext(data))
    }

    /// Reads what R2018 adds after the background: whether the text is annotative and, when it
    /// is not, a second copy of the box and the column layout.
    private mutating func readMTextAnnotation(into data: inout MTextData) throws {
        // The bit is set for text that is NOT annotative.
        data.isAnnotative = !(try main.readBit())
        guard !data.isAnnotative else { return }

        _ = try main.readBitShort()  // version of this block, 0
        _ = try main.readBit()  // default flag, set
        _ = try readOwnHandle()  // the application that owns it
        // The attachment, the direction, the insertion and the box again, as the file repeats
        // them for annotation scaling. The main fields above are the ones that are used.
        _ = try main.readBitLong()
        _ = try main.read3BitDouble()
        _ = try main.read3BitDouble()
        for _ in 0..<4 { _ = try main.readBitDouble() }

        let type = Int(try main.readBitShort())
        guard type != 0 else { return }
        var columns = MTextData.Columns(type: type)
        let heightCount = try main.readBitLong()
        columns.width = try main.readBitDouble()
        columns.gutter = try main.readBitDouble()
        columns.autoHeight = try main.readBit()
        columns.flowReversed = try main.readBit()
        if !columns.autoHeight, type == 2, heightCount > 0 {
            // A bit double takes at least two bits.
            let count = try Self.checkedCount(
                heightCount, bitsPerItem: 2, bitsLeft: main.bitCount - main.position,
                what: "column heights")
            for _ in 0..<count { columns.heights.append(try main.readBitDouble()) }
        }
        data.columns = columns
    }
}
