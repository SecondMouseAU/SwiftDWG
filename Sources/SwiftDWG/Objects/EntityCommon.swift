// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readCommonEntityData, readEntityMode) and DwgStreamReaderAC18.cs (ReadEnColor). See NOTICE.md.

/// An entity's colour as the file holds it.
enum DWGColor: Equatable {
    case byLayer
    case byBlock
    /// An AutoCAD Color Index, 1 to 255.
    case index(Int)
    case rgb(red: UInt8, green: UInt8, blue: UInt8)
}

/// What every entity holds besides its geometry.
struct EntityCommon {
    var handle: UInt64 = 0
    var extendedData: [ObjectReader.ExtendedData] = []
    /// 0: the owner handle is given; 1: paper space; 2: model space.
    var entityMode = 0
    /// The block record the entity belongs to, when `entityMode` is 0.
    var owner: UInt64 = 0
    var reactors: [UInt64] = []
    var extensionDictionary: UInt64 = 0
    /// The neighbours in the block's chain of entities, before R2004.
    var previous: UInt64 = 0
    var next: UInt64 = 0
    var color: DWGColor = .byLayer
    /// The palette index AutoCAD keeps beside a true colour, the nearest it found, or 0.
    var trueColorIndex = 0
    /// The transparency word as stored, or `nil` when there is none.
    var transparency: Int32?
    var lineTypeScale = 1.0
    var layer: UInt64 = 0
    /// 0 by layer, 1 by block, 2 continuous, 3 a line type handle is given.
    var lineTypeFlags = 0
    var lineType: UInt64 = 0
    var isInvisible = false
    /// The line weight code as stored.
    var lineWeight = 0
}

extension ObjectReader {
    /// Reads the data every entity starts with, as far as the neighbours in its block's chain.
    ///
    /// A walk along a block's chain needs the links and nothing after them, so a field that comes
    /// later and cannot be read does not break the walk. ``readEntityCommon()`` carries on from
    /// where this stops.
    mutating func readEntityCommonThroughLinks() throws -> EntityCommon {
        var common = EntityCommon()
        common.extendedData = try readCommonData()
        common.handle = handle

        // A bit says whether a picture of the entity is stored; skip it.
        if try main.readBit() {
            let size =
                version >= .ac1024 ? Int(try main.readBitLongLong()) : Int(try main.readRawLong())
            guard size >= 0, size <= main.bitCount / 8 else {
                throw DWG.Error.invalid("entity graphic of \(size) bytes")
            }
            _ = try main.readBytes(size)
        }
        if version <= .ac1014 { try updateHandleReader() }

        common.entityMode = try main.read2Bits()
        if common.entityMode == 0 { common.owner = try readOwnHandle() }
        try readReactors(into: &common.reactors, dictionary: &common.extensionDictionary)

        if version <= .ac1014 {
            common.layer = try readHandle()
            if try !main.readBit() { common.lineType = try readHandle() }
        }
        // Before R2004 the neighbours are given unless a bit says they are the next and previous
        // handle; from R2004 the bit is always set.
        if version < .ac1018 {
            if try !main.readBit() {
                common.previous = try readOwnHandle()
                common.next = try readOwnHandle()
            }
        }
        return common
    }

    /// Reads the data every entity starts with, which ends where its own geometry begins.
    mutating func readEntityCommon() throws -> EntityCommon {
        var common = try readEntityCommonThroughLinks()
        var hasBookColor = false
        (common.color, common.transparency, hasBookColor, common.trueColorIndex) =
            try readEntityColor()
        if version >= .ac1018, hasBookColor { _ = try readHandle() }
        common.lineTypeScale = try main.readBitDouble()

        guard version >= .ac1015 else {
            common.isInvisible = try main.readBitShort() & 1 == 1
            return common
        }

        common.layer = try readHandle()
        common.lineTypeFlags = try main.read2Bits()
        if common.lineTypeFlags == 3 { common.lineType = try readHandle() }
        if version >= .ac1021 {
            if try main.read2Bits() == 3 { _ = try readHandle() }  // material
            _ = try main.readByte()  // shadow flags
        }
        if try main.read2Bits() == 3 { _ = try readHandle() }  // plot style
        if version >= .ac1024 {
            // Visual style handles for the full, face and edge styles, each behind a bit.
            for _ in 0..<3 where try main.readBit() { _ = try readHandle() }
        }
        common.isInvisible = try main.readBitShort() & 1 == 1
        common.lineWeight = Int(try main.readByte())
        return common
    }

    /// Reads an entity colour, and the transparency and book colour that can follow it.
    mutating func readEntityColor() throws -> (
        color: DWGColor, transparency: Int32?, hasBookColor: Bool, trueColorIndex: Int
    ) {
        guard version >= .ac1018 else {
            return (Self.indexColor(Int(try main.readBitShort())), nil, false, 0)
        }
        let word = Int(try main.readBitShort())
        guard word != 0 else { return (.byBlock, nil, false, 0) }
        let flags = word & 0xFF00
        var color: DWGColor
        var hasBook = false
        var hint = 0
        if flags & 0x4000 != 0 {
            // A colour from a colour book: the word keeps the palette index nearest to it.
            color = word & 0xFFF != 0 ? Self.indexColor(word & 0xFFF) : .byBlock
            hasBook = true
        } else if flags & 0x8000 != 0 {
            hint = word & 0xFFF
            let rgb = UInt32(bitPattern: try main.readBitLong())
            color = .rgb(
                red: UInt8(truncatingIfNeeded: rgb >> 16),
                green: UInt8(truncatingIfNeeded: rgb >> 8),
                blue: UInt8(truncatingIfNeeded: rgb))
        } else {
            color = Self.indexColor(word & 0xFFF)
        }
        var transparency: Int32?
        if flags & 0x2000 != 0 { transparency = try main.readBitLong() }
        return (color, transparency, hasBook, hint)
    }

    /// A colour index as AutoCAD numbers it: 0 is by block, 256 by layer.
    static func indexColor(_ index: Int) -> DWGColor {
        switch index {
        case 0: return .byBlock
        case 256: return .byLayer
        default: return .index(index)
        }
    }
}
