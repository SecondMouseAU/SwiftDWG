// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readInsert, readMInsert, readInsertCommonData, readInsertCommonHandles). See NOTICE.md. The
// field order is the format's own, from the Open Design Specification for .dwg files.

import SwiftDXF

/// The fields of an INSERT or MINSERT entity, in the file's own terms: the angle in radians, the
/// insertion point and the extrusion in the entity's own coordinate system.
struct InsertData: Equatable {
    /// The rows and columns of a MINSERT, which repeats the block on a grid.
    struct Grid: Equatable {
        /// The number of columns (DXF 70).
        var columnCount = 1
        /// The number of rows (DXF 71).
        var rowCount = 1
        /// The distance between columns (DXF 44).
        var columnSpacing = 0.0
        /// The distance between rows (DXF 45).
        var rowSpacing = 0.0
    }

    /// Where the block is placed (DXF 10, 20, 30).
    var insertion = DXF.Point(0, 0, 0)
    /// The scale along the block's x axis (DXF 41).
    var xScale = 1.0
    /// The scale along the block's y axis (DXF 42).
    var yScale = 1.0
    /// The scale along the block's z axis (DXF 43).
    var zScale = 1.0
    /// The rotation about the extrusion, in radians (DXF 50).
    var rotation = 0.0
    /// The normal of the plane the block is placed in (DXF 210, 220, 230).
    var extrusion = DXF.Point(0, 0, 1)
    /// Whether attributes follow the insert (DXF 66).
    var hasAttributes = false
    /// The handle of the block record that is inserted (DXF 2 names it).
    var blockHeader: UInt64 = 0
    /// The handles of the attributes the insert owns, from R2004; before that see
    /// `firstAttribute` and `lastAttribute`.
    var attributes: [UInt64] = []
    /// The handle of the first attribute, from R13 to R2000, or 0.
    var firstAttribute: UInt64 = 0
    /// The handle of the last attribute, from R13 to R2000, or 0.
    var lastAttribute: UInt64 = 0
    /// The handle of the SEQEND that ends the attributes, or 0 when there are none.
    var seqend: UInt64 = 0
    /// The grid of a MINSERT, or `nil` for a plain INSERT.
    var grid: Grid?
}

extension DXF.Point {
    fileprivate init(_ triple: (x: Double, y: Double, z: Double)) {
        self.init(triple.x, triple.y, triple.z)
    }
}

extension ObjectReader {
    mutating func readInsert() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var (data, ownedCount) = try readInsertFields()
        try readInsertHandles(into: &data, ownedCount: ownedCount)
        return DecodedEntity(common: common, geometry: .insert(data))
    }

    mutating func readMInsert() throws -> DecodedEntity {
        let common = try readEntityCommon()
        var (data, ownedCount) = try readInsertFields()
        var grid = InsertData.Grid()
        grid.columnCount = Int(UInt16(bitPattern: try main.readBitShort()))
        grid.rowCount = Int(UInt16(bitPattern: try main.readBitShort()))
        grid.columnSpacing = try main.readBitDouble()
        grid.rowSpacing = try main.readBitDouble()
        data.grid = grid
        try readInsertHandles(into: &data, ownedCount: ownedCount)
        return DecodedEntity(common: common, geometry: .insert(data))
    }

    /// Reads the fields INSERT and MINSERT share that follow the entity's common data, and the
    /// number of attributes the insert owns (R2004 and later; 0 before).
    private mutating func readInsertFields() throws -> (InsertData, Int32) {
        var data = InsertData()
        data.insertion = DXF.Point(try main.read3BitDouble())

        if version <= .ac1014 {
            data.xScale = try main.readBitDouble()
            data.yScale = try main.readBitDouble()
            data.zScale = try main.readBitDouble()
        } else {
            // From R2000 two bits say how the scale is stored.
            switch try main.read2Bits() {
            case 0:
                // x as a raw double; y and z as doubles coded against x.
                data.xScale = try main.readRawDouble()
                data.yScale = try main.readBitDouble(default: data.xScale)
                data.zScale = try main.readBitDouble(default: data.xScale)
            case 1:
                // x is 1.0; y and z are coded against 1.0.
                data.yScale = try main.readBitDouble(default: 1.0)
                data.zScale = try main.readBitDouble(default: 1.0)
            case 2:
                // One raw double is the scale on every axis.
                let scale = try main.readRawDouble()
                data.xScale = scale
                data.yScale = scale
                data.zScale = scale
            default:
                break  // 1.0 on every axis, nothing stored
            }
        }

        data.rotation = try main.readBitDouble()
        data.extrusion = DXF.Point(try main.read3BitDouble())
        data.hasAttributes = try main.readBit()
        var ownedCount: Int32 = 0
        if version >= .ac1018, data.hasAttributes { ownedCount = try main.readBitLong() }
        return (data, ownedCount)
    }

    /// Reads the handles that end an INSERT or MINSERT: its block record, its attributes and the
    /// SEQEND that closes them.
    private mutating func readInsertHandles(into data: inout InsertData, ownedCount: Int32) throws {
        data.blockHeader = try readOwnHandle()
        guard data.hasAttributes else { return }

        if version <= .ac1015 {
            data.firstAttribute = try readOwnHandle()
            data.lastAttribute = try readOwnHandle()
        } else {
            // A handle takes at least one byte.
            let count = try Self.checkedCount(
                ownedCount, bitsPerItem: 8, bitsLeft: handles.bitCount - handles.position,
                what: "attributes")
            for _ in 0..<count { data.attributes.append(try readOwnHandle()) }
        }
        data.seqend = try readOwnHandle()
    }
}
