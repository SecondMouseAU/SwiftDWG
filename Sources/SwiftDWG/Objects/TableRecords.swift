// To be ported from ACadSharp (MIT): DwgObjectReader.cs (readBlock, readEndBlock, the control
// objects, readBlockHeader, readLayer, readLType, readTextStyle, readDimStyle, readAppId,
// readDictionary, readLayout). The header must say so, as in Geometry.swift. See NOTICE.md.

import SwiftDXF

/// The data of a table control object: the handles of the entries in its table.
struct ControlObjectData {}

/// A block record: the name, the BLOCK and ENDBLK entities, and the entities the block holds.
struct BlockHeaderData {}

/// The BLOCK entity that starts a block definition (its name and base point come from here).
struct BlockData {}

struct LayerData {}
struct LineTypeData {}
struct TextStyleData {}
struct DimensionStyleData {}
struct AppIDData {}
struct DictionaryData {}
struct LayoutData {}

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

    mutating func readBlock() throws -> DecodedEntity { throw NotDecodedYet(what: "BLOCK") }
    mutating func readEndBlock() throws -> DecodedEntity { throw NotDecodedYet(what: "ENDBLK") }
    mutating func readControlObject() throws -> ControlObjectData {
        throw NotDecodedYet(what: "control object")
    }
    mutating func readBlockHeader() throws -> BlockHeaderData {
        throw NotDecodedYet(what: "BLOCK_RECORD")
    }
    mutating func readLayer() throws -> LayerData { throw NotDecodedYet(what: "LAYER") }
    mutating func readLineType() throws -> LineTypeData { throw NotDecodedYet(what: "LTYPE") }
    mutating func readTextStyle() throws -> TextStyleData { throw NotDecodedYet(what: "STYLE") }
    mutating func readDimensionStyle() throws -> DimensionStyleData {
        throw NotDecodedYet(what: "DIMSTYLE")
    }
    mutating func readAppID() throws -> AppIDData { throw NotDecodedYet(what: "APPID") }
    mutating func readDictionary() throws -> DictionaryData {
        throw NotDecodedYet(what: "DICTIONARY")
    }
    mutating func readLayout() throws -> LayoutData { throw NotDecodedYet(what: "LAYOUT") }
}
