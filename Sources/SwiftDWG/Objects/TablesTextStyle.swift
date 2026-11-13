// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readTextStyle). See NOTICE.md. The field order is the format's own, from the Open Design
// Specification for .dwg files.

/// A text style.
struct TextStyleData {
    /// The entry and its name.
    ///
    /// A style that only names a shape file has an empty name.
    var entry = TableEntryCommon()
    /// Whether the style is a shape file and not a font (bit 1 of the DXF flags).
    var isShapeFile = false
    /// Whether the text runs vertically (bit 4 of the DXF flags).
    var isVertical = false
    /// The fixed text height, or zero when the height is not fixed (DXF 40).
    var fixedHeight = 0.0
    /// The width factor (DXF 41).
    var widthFactor = 1.0
    /// The oblique angle in radians (DXF 50).
    var obliqueAngle = 0.0
    /// The text generation flags: 2 backwards, 4 upside down (DXF 71).
    var generationFlags = 0
    /// The height last used with the style (DXF 42).
    var lastHeight = 0.0
    /// The font file (DXF 3).
    var fontFile = ""
    /// The big font file (DXF 4).
    var bigFontFile = ""
    /// The text style table's control object.
    var styleControl: UInt64 = 0
}

extension ObjectReader {
    mutating func readTextStyle() throws -> TextStyleData {
        var data = TextStyleData()
        data.entry = try readTableEntryCommon()
        data.isShapeFile = try main.readBit()
        data.isVertical = try main.readBit()
        data.fixedHeight = try main.readBitDouble()
        data.widthFactor = try main.readBitDouble()
        data.obliqueAngle = try main.readBitDouble()
        data.generationFlags = Int(try main.readByte())
        data.lastHeight = try main.readBitDouble()
        data.fontFile = try readText()
        data.bigFontFile = try readText()
        data.styleControl = try readOwnHandle()
        return data
    }
}
