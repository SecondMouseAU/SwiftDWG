// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readLayer) and src/ACadSharp/CadUtils.cs (the line weight index table). See NOTICE.md. The
// field order is the format's own, from the Open Design Specification for .dwg files.

/// A layer.
struct LayerData {
    /// The entry and its name.
    var entry = TableEntryCommon()
    /// Whether the layer is frozen (bit 1 of the DXF flags).
    var isFrozen = false
    /// Whether the layer is turned off (a negative colour in the DXF).
    var isOff = false
    /// Whether the layer is frozen in new viewports (bit 2 of the DXF flags).
    var isFrozenInNewViewports = false
    /// Whether the layer is locked (bit 4 of the DXF flags).
    var isLocked = false
    /// Whether the layer is plotted (DXF 290).
    ///
    /// Before R2000 the file does not say, and it is.
    var isPlotted = true
    /// The line weight as the file codes it, an index into the standard weights or 28 to 31 for the
    /// special values.
    ///
    /// R2000 and later. 31 is the default weight.
    var lineWeightCode = 31
    /// The colour of the layer.
    var color: DWGColor = .index(7)
    /// The layer table's control object.
    var layerControl: UInt64 = 0
    /// The plot style (DXF 390).
    ///
    /// R2000 and later.
    var plotStyle: UInt64 = 0
    /// The material (DXF 347).
    ///
    /// R2007 and later.
    var material: UInt64 = 0
    /// The line type the layer uses (DXF 6, as a name).
    var lineType: UInt64 = 0

    /// The line weights the codes 0 to 23 stand for, in hundredths of a millimetre.
    private static let standardWeights = [
        0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120, 140, 158,
        200, 211,
    ]

    /// The line weight in hundredths of a millimetre, or -1 for by layer, -2 for by block and -3
    /// for the default, as the DXF writes it.
    var lineWeight: Int {
        switch lineWeightCode {
        case 28, 29: return -1
        case 30: return -2
        case 0..<Self.standardWeights.count: return Self.standardWeights[lineWeightCode]
        default: return -3
        }
    }
}

extension ObjectReader {
    mutating func readLayer() throws -> LayerData {
        var data = LayerData()
        data.entry = try readTableEntryCommon()

        if version <= .ac1014 {
            data.isFrozen = try main.readBit()
            data.isOff = try main.readBit()
            data.isFrozenInNewViewports = try main.readBit()
            data.isLocked = try main.readBit()
        }
        if version >= .ac1015 {
            // One word: the four flags, the plot flag and the line weight code.
            let values = Int(try main.readBitShort())
            data.isFrozen = values & 0b1 != 0
            data.isOff = values & 0b10 != 0
            data.isFrozenInNewViewports = values & 0b100 != 0
            data.isLocked = values & 0b1000 != 0
            data.isPlotted = values & 0b1_0000 != 0
            data.lineWeightCode = (values & 0x3E0) >> 5
        }

        data.color = try readCmColor()

        data.layerControl = try readOwnHandle()
        if version >= .ac1015 { data.plotStyle = try readOwnHandle() }
        if version >= .ac1021 { data.material = try readOwnHandle() }
        data.lineType = try readOwnHandle()
        if version >= .ac1027 { _ = try readOwnHandle() }  // a hard pointer that is always null
        return data
    }
}
