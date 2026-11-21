// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgObjectReader.cs
// (readAttribute, readAttributeDefinition, readCommonAttData, readCommonTextData). See NOTICE.md.
// The field order is the format's own, from the Open Design Specification for .dwg files.

/// The fields of an ATTRIB or an ATTDEF entity, in the file's own terms: the angles in radians, the
/// points and the extrusion in the entity's own coordinate system.
///
/// An attribute is a TEXT with a tag and some flags, so the text fields are kept as `TextData`.
struct AttributeData: Equatable {
    /// Whether this is an ATTDEF, the definition a block holds, and not an ATTRIB, the value an
    /// insert carries.
    var isDefinition = false
    /// The fields it shares with TEXT: the value (DXF 1), the point (10), the height (40) and the
    /// rest.
    var text = TextData()
    /// The name that says which attribute it is (DXF 2).
    var tag = ""
    /// What the user is asked when the block is inserted (DXF 3), for an ATTDEF; empty for an
    /// ATTRIB.
    var prompt = ""
    /// Bit 1 hidden, 2 constant, 4 verify, 8 preset (DXF 70).
    var flags = 0
    /// The field length the format keeps and does not use (DXF 73).
    var fieldLength = 0
    /// Whether the position is locked in the block (DXF 280), from R2007; 0 before.
    var isPositionLocked = false
    /// The version byte of the entity (DXF 280, the first), from R2010; 0 before.
    var version = 0
    /// 1 for single-line text, 2 for multi-line text, 4 for multi-line constant text (DXF 71),
    /// which only R2018 and later files say; 1 before.
    var type = 1
    /// The text of a multi-line attribute, which R2018 and later files keep as an embedded MTEXT,
    /// or `nil` for a single-line one.
    var multiLineText: MTextData?
}

extension ObjectReader {
    mutating func readAttribute() throws -> DecodedEntity {
        try readAttributeEntity(isDefinition: false)
    }

    mutating func readAttributeDefinition() throws -> DecodedEntity {
        try readAttributeEntity(isDefinition: true)
    }

    private mutating func readAttributeEntity(isDefinition: Bool) throws -> DecodedEntity {
        let common = try readEntityCommon()
        var data = AttributeData()
        data.isDefinition = isDefinition
        data.text = try readTextFields()
        try readAttributeFields(into: &data)
        if isDefinition {
            // R2010 and later repeat the version byte before the prompt.
            if version >= .ac1024 { _ = try main.readByte() }
            data.prompt = try readText()
        }
        return DecodedEntity(common: common, geometry: .attribute(data))
    }

    /// Reads what ATTRIB and ATTDEF share after their text fields: the version, the type and the
    /// embedded multi-line text where the release has them, then the tag, the flags and the lock.
    private mutating func readAttributeFields(into data: inout AttributeData) throws {
        if version >= .ac1024 { data.version = Int(try main.readByte()) }
        if version >= .ac1032 { data.type = Int(try main.readByte()) }
        if data.type == 2 || data.type == 4 { data.multiLineText = try readEmbeddedMText() }

        data.tag = try readText()
        data.fieldLength = Int(try main.readBitShort())
        data.flags = Int(try main.readByte())
        if version >= .ac1021 { data.isPositionLocked = try main.readBit() }
    }

    /// Reads the MTEXT a multi-line attribute embeds.
    ///
    /// It is written as an entity without its handle and extended data, so it starts at its entity
    /// mode and has the entity properties of its own, which are read and dropped: the attribute's
    /// are the ones that count. Annotation data that may follow is read and dropped too.
    private mutating func readEmbeddedMText() throws -> MTextData {
        var embedded = EntityCommon()
        try readEntityMode(into: &embedded)
        try readEntityProperties(into: &embedded)
        let text = try readMTextFields()

        let annotationSize = Int(try main.readBitShort())
        if annotationSize > 0 {
            _ = try main.readBytes(annotationSize)
            _ = try readOwnHandle()  // the application that owns it
            _ = try main.readBitShort()  // a value the format does not explain
        }
        return text
    }
}
