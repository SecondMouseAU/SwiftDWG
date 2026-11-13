import SwiftDXF

/// Writes a `Document` as ASCII DXF text.
///
/// The text has the sections SwiftDXF reads (`HEADER`, `TABLES`, `BLOCKS`, `ENTITIES`) and uses the
/// group codes AutoCAD's own DXF export uses, so that a drawing read from a DWG is the drawing
/// AutoCAD's DXF of it would be read as.
struct DXFEmitter {
    let document: Document
    var writer = DXFWriter()

    /// Where an entity is written, which decides whether it is flagged as paper space.
    enum Space {
        case model
        case paper
        case block
    }

    init(_ document: Document) {
        self.document = document
    }

    var store: ObjectStore { document.store }

    /// The whole DXF text.
    mutating func text() -> String {
        writeHeader()
        writeTables()
        writeBlocks()
        writeEntities()
        return writer.finish()
    }

    // MARK: HEADER

    private mutating func writeHeader() {
        let header = document.header
        writer.beginSection("HEADER")
        writer.group(9, "$ACADVER")
        writer.group(1, document.version.code)
        func integer(_ name: String) {
            guard let value = header.int(name) else { return }
            writer.group(9, name)
            writer.group(70, value)
        }
        func point(_ name: String) {
            guard let value = header.point3(name) else { return }
            writer.group(9, name)
            writer.point(10, DXF.Point(value.x, value.y, value.z))
        }
        integer("$INSUNITS")
        point("$EXTMIN")
        point("$EXTMAX")
        integer("$DIMDEC")
        integer("$DIMZIN")
        if let scale = header.double("$DIMLFAC") {
            writer.group(9, "$DIMLFAC")
            writer.group(40, scale)
        }
        if let post = header.string("$DIMPOST") {
            writer.group(9, "$DIMPOST")
            writer.group(1, post)
        }
        writer.endSection()
    }

    // MARK: TABLES

    private mutating func writeTables() {
        writer.beginSection("TABLES")

        writer.begin("TABLE")
        writer.group(2, "LTYPE")
        writer.group(70, document.lineTypes.count)
        for entry in document.lineTypes {
            let type = entry.data
            writer.begin("LTYPE")
            writer.handle(5, entry.handle)
            writer.group(2, type.entry.name)
            writer.group(70, 0)
            writer.group(3, type.description)
            writer.group(72, 65)
            writer.group(73, type.segments.count)
            writer.group(40, type.patternLength)
            for segment in type.segments { writer.group(49, segment.length) }
        }
        writer.begin("ENDTAB")

        writer.begin("TABLE")
        writer.group(2, "LAYER")
        writer.group(70, document.layers.count)
        for entry in document.layers {
            let layer = entry.data
            writer.begin("LAYER")
            writer.handle(5, entry.handle)
            writer.group(2, layer.entry.name)
            var flags = 0
            if layer.isFrozen { flags |= 1 }
            if layer.isLocked { flags |= 4 }
            writer.group(70, flags)
            var index = 7
            switch layer.color {
            case .index(let value): index = value
            case .rgb(let red, let green, let blue):
                index = ColorIndex.nearest(red: red, green: green, blue: blue)
            case .byLayer, .byBlock: index = 7
            }
            writer.group(62, layer.isOff ? -index : index)
            if case .rgb(let red, let green, let blue) = layer.color {
                writer.group(420, Int(red) << 16 | Int(green) << 8 | Int(blue))
            }
            writer.group(6, document.lineTypeNames[layer.lineType] ?? "Continuous")
            if layer.lineWeight != -3 { writer.group(370, layer.lineWeight) }
            if !layer.isPlotted { writer.group(290, 0) }
        }
        writer.begin("ENDTAB")

        writer.begin("TABLE")
        writer.group(2, "DIMSTYLE")
        writer.group(70, document.dimensionStyles.count)
        for entry in document.dimensionStyles {
            let style = entry.data
            writer.begin("DIMSTYLE")
            writer.handle(105, entry.handle)
            writer.group(2, style.entry.name)
            writer.group(70, 0)
            // Only what differs from the defaults is written, as AutoCAD does, so that a variable
            // the file does not state stays unstated.
            if !style.postfix.isEmpty { writer.group(3, style.postfix) }
            if style.zeroSuppression != 0 { writer.group(78, style.zeroSuppression) }
            if style.linearScale != 1.0 { writer.group(144, style.linearScale) }
            if style.decimals != 4 { writer.group(271, style.decimals) }
        }
        writer.begin("ENDTAB")

        writer.endSection()
    }

    // MARK: BLOCKS and ENTITIES

    private mutating func writeBlocks() {
        writer.beginSection("BLOCKS")
        for block in document.blocks {
            let record = block.record
            writer.begin("BLOCK")
            writer.handle(5, record.blockEntity)
            let layer = block.blockEntity.flatMap { document.layerNames[$0.common.layer] } ?? "0"
            writer.group(8, layer)
            writer.group(2, block.name)
            var flags = 0
            if record.isAnonymous { flags |= 1 }
            if record.hasAttributeDefinitions { flags |= 2 }
            if record.isXRef { flags |= 4 }
            if record.isXRefOverlay { flags |= 8 }
            writer.group(70, flags)
            writer.point(10, record.basePoint)
            writer.group(3, block.name)
            if !record.xrefPath.isEmpty { writer.group(1, record.xrefPath) }
            // The model space and the current paper space are written in ENTITIES.
            if block.handle != document.modelSpace && block.handle != document.paperSpace {
                for handle in block.entities { writeEntity(handle, space: .block) }
            }
            writer.begin("ENDBLK")
            writer.handle(5, record.endBlockEntity)
            writer.group(8, layer)
        }
        writer.endSection()
    }

    private mutating func writeEntities() {
        writer.beginSection("ENTITIES")
        for block in document.blocks where block.handle == document.modelSpace {
            for handle in block.entities { writeEntity(handle, space: .model) }
        }
        for block in document.blocks where block.handle == document.paperSpace {
            for handle in block.entities { writeEntity(handle, space: .paper) }
        }
        // Table records and blocks that could not be read, so that SwiftDXF counts them.
        for lost in document.lostRecords {
            writer.begin("UNREADABLE_\(lost.table)")
            writer.handle(5, lost.handle)
        }
        writer.endSection()
    }

    // MARK: Entities

    private mutating func writeEntity(_ handle: UInt64, space: Space) {
        do {
            if let entity = try store.entity(handle) {
                write(entity, space: space)
            } else {
                writeUndecoded(handle, space: space)
            }
        } catch is NotDecodedYet {
            writeUndecoded(handle, space: space)
        } catch {
            // An entity that cannot be read is left out, and counted by what it was.
            writeUndecoded(handle, space: space, unreadable: true)
        }
    }

    /// Writes a record of the entity's type and nothing else, so that SwiftDXF tallies it among
    /// the entities it does not model, as it does for a DXF.
    ///
    /// An object that cannot be opened at all, or that the file does not hold, has no type to
    /// name, and is written as `UNREADABLE_OBJECT`.
    private mutating func writeUndecoded(
        _ handle: UInt64, space: Space, unreadable: Bool = false
    ) {
        let opened: ObjectReader?
        do {
            opened = try store.reader(for: handle)
        } catch {
            opened = nil
        }
        guard let reader = opened else {
            writeBare("UNREADABLE_OBJECT", handle: handle, space: space)
            return
        }
        // A type this reader decodes has a name only here: it never reaches the other list unless
        // it failed to decode.
        guard let name = typeName(reader.type) ?? (unreadable ? decodedTypeName(reader.type) : nil)
        else {
            // No name, and it failed to read: still counted, by what it is not.
            if unreadable { writeBare("UNREADABLE_OBJECT", handle: handle, space: space) }
            return
        }
        writeBare(unreadable ? "UNREADABLE_\(name)" : name, handle: handle, space: space)
    }

    /// The DXF name of an entity type that `readEntity` decodes.
    private func decodedTypeName(_ type: Int) -> String? {
        switch type {
        case ObjectType.line: return "LINE"
        case ObjectType.circle: return "CIRCLE"
        case ObjectType.arc: return "ARC"
        case ObjectType.point: return "POINT"
        case ObjectType.text: return "TEXT"
        case ObjectType.mtext: return "MTEXT"
        case ObjectType.insert, ObjectType.minsert: return "INSERT"
        case ObjectType.ellipse: return "ELLIPSE"
        case ObjectType.spline: return "SPLINE"
        case ObjectType.lwpolyline: return "LWPOLYLINE"
        case ObjectType.polyline2D, ObjectType.polyline3D: return "POLYLINE"
        case ObjectType.vertex2D, ObjectType.vertex3D: return "VERTEX"
        case ObjectType.seqend: return "SEQEND"
        case ObjectType.solid: return "SOLID"
        case ObjectType.trace: return "TRACE"
        case ObjectType.face3D: return "3DFACE"
        case ObjectType.dimensionOrdinate, ObjectType.dimensionLinear,
            ObjectType.dimensionAligned, ObjectType.dimensionAngular3Point,
            ObjectType.dimensionAngular2Line, ObjectType.dimensionRadius,
            ObjectType.dimensionDiameter:
            return "DIMENSION"
        case ObjectType.leader: return "LEADER"
        case ObjectType.hatch: return "HATCH"
        default: return nil
        }
    }

    /// A record of this type with a handle and nothing else.
    mutating func writeBare(_ type: String, handle: UInt64, space: Space) {
        writer.begin(type)
        writer.handle(5, handle)
        if space == .paper { writer.group(67, 1) }
    }

    /// The DXF name of an object type that is an entity, or `nil` for one that is not.
    private func typeName(_ type: Int) -> String? {
        if type >= ObjectType.firstClass {
            guard let found = store.classes[type], found.itemClassID == 0x1F2 else { return nil }
            return found.dxfName
        }
        switch type {
        case ObjectType.attrib: return "ATTRIB"
        case ObjectType.attdef: return "ATTDEF"
        case ObjectType.vertexMesh, ObjectType.vertexPFace, ObjectType.vertexPFaceFace:
            return "VERTEX"
        case ObjectType.polylinePFace: return "POLYFACE_MESH"
        case ObjectType.polylineMesh: return "POLYGON_MESH"
        case ObjectType.shape: return "SHAPE"
        case ObjectType.viewport: return "VIEWPORT"
        case ObjectType.region: return "REGION"
        case ObjectType.solid3D: return "3DSOLID"
        case ObjectType.body: return "BODY"
        case ObjectType.ray: return "RAY"
        case ObjectType.xline: return "XLINE"
        case ObjectType.oleFrame, ObjectType.ole2Frame: return "OLE2FRAME"
        case ObjectType.tolerance: return "TOLERANCE"
        case ObjectType.mline: return "MLINE"
        default: return nil
        }
    }

    /// The data every entity starts with, as groups.
    mutating func writeCommon(_ common: EntityCommon, space: Space) {
        writer.handle(5, common.handle)
        if space == .paper { writer.group(67, 1) }
        writer.group(8, document.layerNames[common.layer] ?? "0")
        switch common.lineTypeFlags {
        case 1: writer.group(6, "BYBLOCK")
        case 2: writer.group(6, "CONTINUOUS")
        case 3:
            if let name = document.lineTypeNames[common.lineType] { writer.group(6, name) }
        default: break
        }
        switch common.color {
        case .byLayer: break
        case .byBlock: writer.group(62, 0)
        case .index(let value): writer.group(62, value)
        case .rgb(let red, let green, let blue):
            // DXF writes the palette index nearest to a true colour in group 62, and the colour
            // itself in 420.
            if common.trueColorIndex != 0 { writer.group(62, common.trueColorIndex) }
            writer.group(420, Int(red) << 16 | Int(green) << 8 | Int(blue))
        }
        let weight = HeaderReader.Parser.lineWeight(index: common.lineWeight & 0x1F)
        if weight != -1 { writer.group(370, weight) }
        if common.lineTypeScale != 1.0 { writer.group(48, common.lineTypeScale) }
        if common.isInvisible { writer.group(60, 1) }
        if let transparency = common.transparency { writer.group(440, Int(transparency)) }
    }

    /// An extrusion, when it is not the usual one.
    mutating func writeExtrusion(_ extrusion: DXF.Point) {
        if extrusion != DXF.Point(0, 0, 1) { writer.point(210, extrusion) }
    }

    mutating func writeThickness(_ thickness: Double) {
        if thickness != 0 { writer.group(39, thickness) }
    }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
