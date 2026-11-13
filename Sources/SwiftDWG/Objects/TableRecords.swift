// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readObject for the control objects, readDocumentTable, readBlockControlObject,
// readLTypeControlObject, readBlock, readEndBlock, readAppId, readDictionary,
// readCommonDictionary, readXrefDependantBit). See NOTICE.md. The field order is the format's own,
// from the Open Design Specification for .dwg files.
//
// The records of the symbol tables are read in the files next to this one: Tables*.swift.
// Handles are kept as the numbers the file holds. Turning them into names is left to the code that
// assembles a drawing. Releases before R2004 are written from ACadSharp and the specification but
// no sample of them can be opened yet, so those branches are untested.

/// What every table entry has: the data of any object, its name, and the bits that say whether it
/// came from another drawing.
struct TableEntryCommon {
    /// The owner, reactors, extension dictionary and extended data of the entry.
    var object = ObjectReader.ObjectCommon()
    /// The name of the entry.
    var name = ""
    /// The 64 bit of the DXF flags: some entity has used the entry.
    ///
    /// Releases before R2007 only.
    var isReferenced = false
    /// The index of the external reference the entry came from plus one, as stored.
    ///
    /// From R2007 the word also holds the `0x100` bit that `isXrefDependent` reports.
    var xrefIndexPlusOne = 0
    /// The 16 bit of the DXF flags: the entry belongs to an external reference.
    var isXrefDependent = false
}

/// The data of a table control object: the handles of the entries in its table.
struct ControlObjectData {
    /// The owner, reactors and extension dictionary of the control object.
    var object = ObjectReader.ObjectCommon()
    /// The handles of the entries.
    ///
    /// The block table leaves out the model and paper space records and the line type table leaves
    /// out BYLAYER and BYBLOCK, which have their own fields.
    var entries: [UInt64] = []
    /// The block table only: the `*Model_Space` block record.
    var modelSpace: UInt64 = 0
    /// The block table only: the `*Paper_Space` block record.
    var paperSpace: UInt64 = 0
    /// The line type table only: the BYLAYER line type.
    var byLayer: UInt64 = 0
    /// The line type table only: the BYBLOCK line type.
    var byBlock: UInt64 = 0
}

/// The BLOCK entity that starts a block definition.
///
/// The file keeps only the name here. The flags, base point and description of the block are in its
/// block record (`BlockHeaderData`).
struct BlockData {
    /// The name of the block, with the whole name of an anonymous block.
    var name = ""
}

/// An application name registered in the drawing (APPID).
struct AppIDData {
    /// The entry and its name.
    var entry = TableEntryCommon()
    /// A byte the format leaves unexplained, which is not in the DXF.
    var unknown: UInt8 = 0
    /// The block record of the external reference the application came from, if any.
    var externalReference: UInt64 = 0
}

/// One name and what it points at in a dictionary.
struct DictionaryEntry: Equatable {
    var name: String
    var handle: UInt64
}

/// A dictionary: names mapped to objects.
struct DictionaryData {
    /// The owner, reactors and extension dictionary of the dictionary.
    var object = ObjectReader.ObjectCommon()
    /// What happens to the entries when the dictionary is cloned (DXF 281).
    ///
    /// R2000 and later.
    var cloningFlags = 0
    /// Whether the entries are owned by the dictionary (DXF 280).
    ///
    /// R2000 and later.
    var isHardOwner = false
    /// The entries in the order the file lists them, empty names and null handles included.
    var entries: [DictionaryEntry] = []
}

/// An object that is a table entry, a table's control object, a dictionary or a layout.
enum TableRecord {
    /// A control object, with the type code that says which table it controls.
    case control(type: Int, ControlObjectData)
    case blockHeader(BlockHeaderData)
    case layer(LayerData)
    case lineType(LineTypeData)
    case textStyle(TextStyleData)
    case dimensionStyle(DimensionStyleData)
    case appID(AppIDData)
    case dictionary(DictionaryData)
    case layout(LayoutData)

    // The data of one kind of record, or `nil` for another kind.

    var asBlockHeader: BlockHeaderData? {
        if case .blockHeader(let data) = self { return data }
        return nil
    }

    var asLayer: LayerData? {
        if case .layer(let data) = self { return data }
        return nil
    }

    var asLineType: LineTypeData? {
        if case .lineType(let data) = self { return data }
        return nil
    }

    var asTextStyle: TextStyleData? {
        if case .textStyle(let data) = self { return data }
        return nil
    }

    var asDimensionStyle: DimensionStyleData? {
        if case .dimensionStyle(let data) = self { return data }
        return nil
    }
}

extension ObjectReader {
    /// Reads the table record of this object's type, or `nil` for a type that is not one.
    mutating func readTableRecord() throws -> TableRecord? {
        switch type {
        case ObjectType.blockControl, ObjectType.layerControl, ObjectType.styleControl,
            ObjectType.lineTypeControl, ObjectType.viewControl, ObjectType.ucsControl,
            ObjectType.viewportControl, ObjectType.appIDControl, ObjectType.dimensionStyleControl:
            return .control(type: type, try readControlObject())
        case ObjectType.blockHeader: return .blockHeader(try readBlockHeader())
        case ObjectType.layer: return .layer(try readLayer())
        case ObjectType.lineType: return .lineType(try readLineType())
        case ObjectType.style: return .textStyle(try readTextStyle())
        case ObjectType.dimensionStyle: return .dimensionStyle(try readDimensionStyle())
        case ObjectType.appID: return .appID(try readAppID())
        case ObjectType.dictionary: return .dictionary(try readDictionary())
        case ObjectType.layout: return .layout(try readLayout())
        default: return nil
        }
    }

    // MARK: Shared pieces

    /// Reads the common data, the name and the external reference bits that start a table entry.
    mutating func readTableEntryCommon() throws -> TableEntryCommon {
        var entry = TableEntryCommon()
        entry.object = try readObjectCommon()
        entry.name = try readText()
        if version >= .ac1021 {
            // One word: the external reference index plus one, with the "depends on an external
            // reference" flag as its 0x100 bit.
            let word = Int(try main.readBitShort())
            entry.xrefIndexPlusOne = word
            entry.isXrefDependent = word & 0x100 != 0
        } else {
            entry.isReferenced = try main.readBit()
            entry.xrefIndexPlusOne = Int(try main.readBitShort())
            entry.isXrefDependent = try main.readBit()
        }
        return entry
    }

    // MARK: Entities

    /// Reads the BLOCK entity: what every entity has, then the block's name.
    mutating func readBlock() throws -> DecodedEntity {
        let common = try readEntityCommon()
        let name: String = try readText()
        return DecodedEntity(common: common, geometry: .block(BlockData(name: name)))
    }

    /// Reads the ENDBLK entity, which has nothing past what every entity has.
    mutating func readEndBlock() throws -> DecodedEntity {
        DecodedEntity(common: try readEntityCommon(), geometry: .endBlock)
    }

    // MARK: Control objects

    /// Reads a table's control object: its entry handles, then the handles only some tables have.
    mutating func readControlObject() throws -> ControlObjectData {
        var data = ControlObjectData()
        data.object = try readObjectCommon()
        let count = try checkedHandleCount(try main.readBitLong(), "table entries")
        for _ in 0..<count { data.entries.append(try readOwnHandle()) }
        if type == ObjectType.blockControl {
            data.modelSpace = try readOwnHandle()
            data.paperSpace = try readOwnHandle()
        } else if type == ObjectType.lineTypeControl {
            data.byBlock = try readOwnHandle()
            data.byLayer = try readOwnHandle()
        }
        return data
    }

    // MARK: APPID

    mutating func readAppID() throws -> AppIDData {
        var data = AppIDData()
        data.entry = try readTableEntryCommon()
        data.unknown = try main.readByte()
        data.externalReference = try readOwnHandle()
        return data
    }

    // MARK: Dictionaries

    mutating func readDictionary() throws -> DictionaryData {
        var data = DictionaryData()
        data.object = try readObjectCommon()
        let count = try checkedHandleCount(try main.readBitLong(), "dictionary entries")
        if version == .ac1014 { _ = try main.readByte() }  // a byte that has always been zero
        if version >= .ac1015 {
            data.cloningFlags = Int(try main.readBitShort())
            data.isHardOwner = try main.readByte() > 0
        }
        data.entries.reserveCapacity(count)
        for _ in 0..<count {
            let name: String = try readText()
            data.entries.append(DictionaryEntry(name: name, handle: try readOwnHandle()))
        }
        return data
    }
}
