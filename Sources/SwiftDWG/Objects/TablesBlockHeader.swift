// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readBlockHeader). See NOTICE.md. The field order is the format's own, from the Open Design
// Specification for .dwg files.

import SwiftDXF

/// A block record: the name, the BLOCK and ENDBLK entities, and the entities the block holds.
struct BlockHeaderData {
    /// The entry and its name.
    ///
    /// The file writes an anonymous block as `*` and a type letter (`*D`, `*U`), and the paper
    /// spaces as `*Paper_Space`, with no number. The BLOCK entity has the whole name, but AutoCAD
    /// numbers anonymous blocks again when it writes a DXF, so the two files can differ in it.
    var entry = TableEntryCommon()
    /// Whether the block is anonymous (bit 1 of the DXF block flags).
    var isAnonymous = false
    /// Whether the block holds attribute definitions (bit 2).
    var hasAttributeDefinitions = false
    /// Whether the block is an external reference (bit 4).
    var isXRef = false
    /// Whether the block is an overlaid external reference (bit 8).
    var isXRefOverlay = false
    /// Whether the external reference is unloaded.
    ///
    /// R2000 and later.
    var isUnloaded = false
    /// The insertion base point of the block.
    var basePoint = DXF.Point(0, 0, 0)
    /// The path of the external reference.
    var xrefPath = ""
    /// The description of the block (DXF 4).
    ///
    /// R2000 and later.
    var description = ""
    /// The thumbnail the block is shown with, as the bytes the file holds.
    ///
    /// R2000 and later.
    var preview: [UInt8] = []
    /// The units the block is inserted in, as a DXF `INSUNITS` value.
    ///
    /// R2007 and later.
    var insertUnits = 0
    /// Whether the block can be exploded (DXF 280).
    ///
    /// R2007 and later.
    var isExplodable = true
    /// Whether the block can be scaled (DXF 281).
    ///
    /// R2007 and later.
    var canScale = true
    /// The BLOCK entity that starts the block.
    var blockEntity: UInt64 = 0
    /// The ENDBLK entity that ends the block.
    var endBlockEntity: UInt64 = 0
    /// The first entity of the block's chain.
    ///
    /// R13 to R2000, not for external references.
    var firstEntity: UInt64 = 0
    /// The last entity of the block's chain.
    ///
    /// R13 to R2000, not for external references.
    var lastEntity: UInt64 = 0
    /// The entities the block owns, in order.
    ///
    /// R2004 and later, not for external references.
    var ownedEntities: [UInt64] = []
    /// The inserts of the block, which the file counts as one byte each.
    ///
    /// R2000 and later.
    var insertCount = 0
    /// The handles of the inserts of the block.
    ///
    /// R2000 and later.
    var inserts: [UInt64] = []
    /// The layout the block is the space of, or zero for a block that is not one.
    ///
    /// R2000 and later.
    var layout: UInt64 = 0
}

extension ObjectReader {
    mutating func readBlockHeader() throws -> BlockHeaderData {
        var data = BlockHeaderData()
        data.entry = try readTableEntryCommon()

        data.isAnonymous = try main.readBit()
        data.hasAttributeDefinitions = try main.readBit()
        data.isXRef = try main.readBit()
        data.isXRefOverlay = try main.readBit()
        if version >= .ac1015 { data.isUnloaded = try main.readBit() }

        var ownedCount: Int32 = 0
        if version >= .ac1018, !data.isXRef, !data.isXRefOverlay {
            ownedCount = try main.readBitLong()
        }

        let base = try main.read3BitDouble()
        data.basePoint = DXF.Point(base.x, base.y, base.z)
        data.xrefPath = try readText()

        if version >= .ac1015 {
            // A run of non-zero bytes ended by a zero: one byte for each insert.
            while try main.readByte() != 0 { data.insertCount += 1 }
            data.description = try readText()
            let previewSize = Int(try main.readBitLong())
            guard previewSize >= 0 else {
                throw DWG.Error.invalid("preview of \(previewSize) bytes")
            }
            data.preview = try main.readBytes(previewSize)
        }
        if version >= .ac1021 {
            data.insertUnits = Int(try main.readBitShort())
            data.isExplodable = try main.readBit()
            data.canScale = try main.readByte() > 0
        }

        _ = try readOwnHandle()  // a null hard pointer
        data.blockEntity = try readOwnHandle()

        if version >= .ac1012, version <= .ac1015, !data.isXRef, !data.isXRefOverlay {
            data.firstEntity = try readOwnHandle()
            data.lastEntity = try readOwnHandle()
        }
        if version >= .ac1018 {
            let count = try checkedHandleCount(ownedCount, "entities in a block")
            data.ownedEntities.reserveCapacity(count)
            for _ in 0..<count { data.ownedEntities.append(try readOwnHandle()) }
        }
        data.endBlockEntity = try readOwnHandle()

        if version >= .ac1015 {
            let count = try checkedHandleCount(Int32(data.insertCount), "inserts of a block")
            data.inserts.reserveCapacity(count)
            for _ in 0..<count { data.inserts.append(try readOwnHandle()) }
            data.layout = try readOwnHandle()
        }
        return data
    }
}
