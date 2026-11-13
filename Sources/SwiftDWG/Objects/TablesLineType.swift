// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readLType, readLineTypeSegmentTexts, readLineTypeTextString). See NOTICE.md. The field order is
// the format's own, from the Open Design Specification for .dwg files.

import Foundation

/// One dash, dot, gap, shape or piece of text in a line type's pattern.
struct LineTypeSegment {
    /// The length of the dash, positive to draw, negative for a gap, zero for a dot (DXF 49).
    var length = 0.0
    /// The number of the shape in the shape file when the flags say a shape (DXF 75).
    ///
    /// For a text segment the file holds the place of the text here, and this is zero.
    var shapeNumber = 0
    /// The offset of a shape or text from the pattern's line, along the line (DXF 44).
    var offsetX = 0.0
    /// The offset of a shape or text across the line (DXF 45).
    var offsetY = 0.0
    /// The scale of a shape or text (DXF 46).
    var scale = 1.0
    /// The rotation of a shape or text in radians (DXF 50).
    var rotation = 0.0
    /// The segment's flags as stored (DXF 74): 1 rotation is absolute, 2 text, 4 shape.
    var flags = 0
    /// The text of a text segment, taken from the line type's text area.
    var text: String?
    /// The text style or shape file the shape or text uses (DXF 340).
    var style: UInt64 = 0

    /// Whether this segment draws text.
    var isText: Bool { flags & 2 != 0 }
}

/// A line type.
struct LineTypeData {
    /// The entry and its name.
    var entry = TableEntryCommon()
    /// The description (DXF 3).
    var description = ""
    /// The length of one repeat of the pattern (DXF 40).
    var patternLength = 0.0
    /// The alignment code, which is always the letter A (DXF 72).
    var alignment: UInt8 = 0
    /// The pattern, in order.
    var segments: [LineTypeSegment] = []
    /// The line type table's control object.
    var lineTypeControl: UInt64 = 0
}

extension ObjectReader {
    mutating func readLineType() throws -> LineTypeData {
        var data = LineTypeData()
        data.entry = try readTableEntryCommon()

        data.description = try readText()
        data.patternLength = try main.readBitDouble()
        data.alignment = try main.readByte()

        let count = Int(try main.readByte())
        var hasText = false
        data.segments.reserveCapacity(count)
        for _ in 0..<count {
            var segment = LineTypeSegment()
            segment.length = try main.readBitDouble()
            segment.shapeNumber = Int(try main.readBitShort())
            segment.offsetX = try main.readRawDouble()
            segment.offsetY = try main.readRawDouble()
            segment.scale = try main.readBitDouble()
            segment.rotation = try main.readBitDouble()
            segment.flags = Int(try main.readBitShort())
            if segment.isText { hasText = true }
            data.segments.append(segment)
        }

        // The text of the text segments sits in an area of its own: 256 bytes up to R2004, and
        // from R2007 512 bytes that are there only when some segment has text.
        var textArea: [UInt8] = []
        if version <= .ac1018 {
            textArea = try main.readBytes(256)
        } else if version >= .ac1021, hasText {
            textArea = try main.readBytes(512)
        }
        if hasText { fillText(of: &data.segments, from: textArea) }

        data.lineTypeControl = try readOwnHandle()
        for index in 0..<count { data.segments[index].style = try readOwnHandle() }
        return data
    }

    /// Sets the text of each text segment from the text area, where its shape number is the place
    /// of the text.
    private func fillText(of segments: inout [LineTypeSegment], from area: [UInt8]) {
        for index in segments.indices where segments[index].isText {
            let offset = segments[index].shapeNumber & 0xFFFF
            segments[index].shapeNumber = 0
            segments[index].text = offset < area.count ? textArea(area, at: offset) : ""
        }
    }

    /// The zero-ended string at `offset` in a text area: UTF-16 from R2007, and before that in the
    /// drawing's code page.
    private func textArea(_ area: [UInt8], at offset: Int) -> String {
        if version >= .ac1021 {
            var units: [UInt16] = []
            var index = offset
            while index + 1 < area.count {
                let unit = UInt16(area[index]) | UInt16(area[index + 1]) << 8
                if unit == 0 { break }
                units.append(unit)
                index += 2
            }
            return String(decoding: units, as: UTF16.self)
        }
        let bytes = area[offset...].prefix { $0 != 0 }
        return String(bytes: bytes, encoding: main.textEncoding)
            ?? String(decoding: bytes, as: UTF8.self)
    }
}
