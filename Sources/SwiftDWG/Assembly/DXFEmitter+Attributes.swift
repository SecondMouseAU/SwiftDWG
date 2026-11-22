extension DXFEmitter {
    /// Writes the attributes an INSERT owns and the SEQEND that ends them.
    ///
    /// In the DXF they follow the INSERT record, which has group 66 set. In the DWG an attribute
    /// is owned by the INSERT and is in no block's list of entities, so this is the only place it
    /// is written. One that cannot be read is written as `UNREADABLE_ATTRIB`, so that it is
    /// counted and the insert is still written.
    mutating func writeAttributes(of insert: InsertData, like common: EntityCommon, space: Space) {
        for handle in attributeHandles(of: insert, handle: common.handle) {
            if let entity = try? store.entity(handle),
                case .attribute(let attribute) = entity.geometry,
                !attribute.isDefinition
            {
                writeAttribute(attribute, common: entity.common, space: space)
                writeExtendedData(entity.common)
            } else {
                // Counted as an attribute, on its layer when that can be read.
                var lost = EntityCommon()
                if var reader = try? store.reader(for: handle) {
                    _ = try? reader.readEntityCommon(into: &lost)
                }
                writeSkipped(
                    .unreadable(type: "ATTRIB"), handle: handle, space: space, layer: lost.layer)
            }
        }
        writeAttributesEnd(insert.seqend, like: common, space: space)
    }

    /// The attributes of the INSERT with this handle, in order.
    ///
    /// From R2004 the INSERT lists them. Before, it names the first and the last and each
    /// attribute names the one before and the one after, as the entities of a block do, so the
    /// links are followed as ``EntityChain`` does, and an attribute that cannot be read is found
    /// by its owner, which is the INSERT. The SEQEND is not one of them.
    private func attributeHandles(of insert: InsertData, handle: UInt64) -> [UInt64] {
        if document.version >= .ac1018 { return insert.attributes.filter { $0 != 0 } }
        return EntityChain.entities(
            first: insert.firstAttribute, last: insert.lastAttribute, record: handle,
            excluding: [insert.seqend],
            links: { store.chainLinks(of: $0) },
            owner: { store.block(ofEntity: $0, modelSpace: 0, paperSpace: 0) },
            candidates: { store.handles })
    }

    /// Writes the SEQEND of an INSERT, with the layer and the other properties it has itself.
    ///
    /// When it cannot be read it takes the INSERT's layer, so that the attributes before it are
    /// still ended.
    private mutating func writeAttributesEnd(
        _ handle: UInt64, like common: EntityCommon, space: Space
    ) {
        if let entity = try? store.entity(handle), case .seqend = entity.geometry {
            writer.begin("SEQEND")
            writeCommon(entity.common, space: space)
            writeExtendedData(entity.common)
            return
        }
        writer.begin("SEQEND")
        if handle != 0 { writer.handle(5, handle) }
        if space == .paper { writer.group(67, 1) }
        writer.group(8, document.layerNames[common.layer] ?? "0")
    }

    /// Writes an ATTRIB or an ATTDEF with the group codes AutoCAD's DXF gives it.
    ///
    /// The groups are those of TEXT, then the ones of the attribute: the version (R2010 and later),
    /// the prompt of an ATTDEF, the tag, the flags, the vertical alignment (74, where TEXT has 73),
    /// the position lock (R2007 and later), and for a multi-line attribute (R2018) its type and
    /// the text it embeds.
    mutating func writeAttribute(_ attribute: AttributeData, common: EntityCommon, space: Space) {
        let text = attribute.text
        writer.begin(attribute.isDefinition ? "ATTDEF" : "ATTRIB")
        writeCommon(common, space: space)
        writeThickness(text.thickness)
        writer.point(10, text.insertion)
        writer.group(40, text.height)
        writer.group(1, text.value)
        if text.rotation != 0 { writer.group(50, Self.degrees(text.rotation)) }
        if text.widthFactor != 1.0 { writer.group(41, text.widthFactor) }
        if text.obliqueAngle != 0 { writer.group(51, Self.degrees(text.obliqueAngle)) }
        writeStyle(text.style)
        if text.generation != 0 { writer.group(71, text.generation) }
        if text.horizontalAlignment != 0 { writer.group(72, text.horizontalAlignment) }
        if let alignment = text.alignmentPoint { writer.point(11, alignment) }
        writeExtrusion(text.extrusion)

        if document.version >= .ac1024 { writer.group(280, attribute.version) }
        if attribute.isDefinition { writer.group(3, attribute.prompt) }
        writer.group(2, attribute.tag)
        writer.group(70, attribute.flags)
        if attribute.fieldLength != 0 { writer.group(73, attribute.fieldLength) }
        if text.verticalAlignment != 0 { writer.group(74, text.verticalAlignment) }
        if document.version >= .ac1021 { writer.group(280, attribute.isPositionLocked ? 1 : 0) }
        if let multiLine = attribute.multiLineText {
            writer.group(71, attribute.type)
            writer.group(72, 0)
            if let alignment = text.alignmentPoint { writer.point(11, alignment) }
            writer.group(101, "Embedded Object")
            writeEmbeddedMText(multiLine)
        }
    }

    /// The text a multi-line attribute embeds, as the groups of an MTEXT without the ones its
    /// attribute already gives (the extrusion, and the direction, which the rotation says).
    private mutating func writeEmbeddedMText(_ text: MTextData) {
        writer.point(10, text.insertion)
        writer.group(40, text.height)
        writer.group(41, text.rectangleWidth)
        writer.group(46, text.rectangleHeight)
        writer.group(71, text.attachment)
        writer.group(72, text.drawingDirection)
        // The text is written in chunks of at most 250 characters: the last in group 1, the others
        // in group 3.
        var rest = Substring(text.value)
        while rest.count > 250 {
            writer.group(3, String(rest.prefix(250)))
            rest = rest.dropFirst(250)
        }
        writer.group(1, String(rest))
        writeStyle(text.style)
        writer.group(73, text.lineSpacingStyle)
        writer.group(44, text.lineSpacingFactor)
    }

    /// The text style, left out for `Standard`, as AutoCAD does.
    private mutating func writeStyle(_ handle: UInt64) {
        if let style = document.textStyleNames[handle], style.lowercased() != "standard" {
            writer.group(7, style)
        }
    }
}
