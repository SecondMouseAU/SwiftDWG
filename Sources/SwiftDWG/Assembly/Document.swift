import Foundation
import SwiftDXF

/// A DWG put together from its objects: the header, the tables and the blocks, with the names the
/// objects refer to by handle.
///
/// The objects of a DWG point at each other by handle: an entity at its layer, a layer at its line
/// type, an insert at its block. A DXF names them. This resolves the handles, once, into the names
/// that the DXF text is written with.
struct Document {
    let version: DWG.Version
    let store: ObjectStore
    let header: HeaderVariables

    struct Layer {
        var handle: UInt64
        var data: LayerData
    }

    struct LineType {
        var handle: UInt64
        var data: LineTypeData
    }

    struct DimensionStyle {
        var handle: UInt64
        var data: DimensionStyleData
    }

    /// A block definition: its record, its name and the entities it holds, in order.
    struct Block {
        var handle: UInt64
        var record: BlockHeaderData
        /// The name the BLOCK entity gives, which is the full name (`*D12`, not `*D`).
        var name: String
        var blockEntity: DecodedEntity?
        var endBlockEntity: DecodedEntity?
        var entities: [UInt64]
    }

    var layers: [Layer] = []
    var lineTypes: [LineType] = []
    var dimensionStyles: [DimensionStyle] = []
    var textStyleNames: [UInt64: String] = [:]
    var blocks: [Block] = []
    var layerNames: [UInt64: String] = [:]
    var lineTypeNames: [UInt64: String] = [:]
    var dimensionStyleNames: [UInt64: String] = [:]
    var blockNames: [UInt64: String] = [:]
    var modelSpace: UInt64 = 0
    var paperSpace: UInt64 = 0

    /// The name of the application that owns a block of extended data, by its APPID handle.
    func applicationName(_ handle: UInt64) -> String? {
        if case .appID(let data)? = try? store.tableRecord(handle) { return data.entry.name }
        return nil
    }

    /// How many objects could not be read, by what they were.
    var unreadable: [String: Int] = [:]

    init(_ data: [UInt8]) throws {
        let container = try Container(data)
        version = container.version
        store = try ObjectStore(container)
        guard let section = try container.section("AcDb:Header") else {
            throw DWG.Error.invalid("the file has no header section")
        }
        header = try HeaderReader.read(
            section, version: container.version, maintenanceVersion: container.maintenanceVersion,
            codePage: container.codePage)
        try loadTables()
        try loadBlocks()
    }

    // MARK: Tables

    private mutating func loadTables() throws {
        func entries(_ name: String) throws -> [UInt64] {
            guard let handle = header.handles[name],
                case .control(_, let control)? = try? store.tableRecord(handle)
            else { return [] }
            return control.entries.filter { $0 != 0 }
        }

        for handle in try entries("LAYER_CONTROL_OBJECT") {
            if case .layer(let data)? = try? store.tableRecord(handle) {
                layers.append(Layer(handle: handle, data: data))
                layerNames[handle] = data.entry.name
            }
        }
        // BYBLOCK and BYLAYER are line types too, kept by the control object apart from its entries.
        var lineTypeHandles = try entries("LINETYPE_CONTROL_OBJECT")
        if let controlHandle = header.handles["LINETYPE_CONTROL_OBJECT"],
            case .control(_, let control)? = try? store.tableRecord(controlHandle)
        {
            for special in [control.byLayer, control.byBlock]
            where special != 0 && !lineTypeHandles.contains(special) {
                lineTypeHandles.insert(special, at: 0)
            }
        }
        for handle in lineTypeHandles {
            if case .lineType(let data)? = try? store.tableRecord(handle) {
                lineTypes.append(LineType(handle: handle, data: data))
                lineTypeNames[handle] = data.entry.name
            }
        }
        for handle in try entries("STYLE_CONTROL_OBJECT") {
            if case .textStyle(let data)? = try? store.tableRecord(handle) {
                textStyleNames[handle] = data.entry.name
            }
        }
        for handle in try entries("DIMSTYLE_CONTROL_OBJECT") {
            if case .dimensionStyle(let data)? = try? store.tableRecord(handle) {
                dimensionStyles.append(DimensionStyle(handle: handle, data: data))
                dimensionStyleNames[handle] = data.entry.name
            }
        }
        // The line types BYLAYER and BYBLOCK are not in the table's entries; their names are
        // fixed.
        if let handle = header.handles["BLOCK_CONTROL_OBJECT"],
            case .control(_, let control)? = try? store.tableRecord(handle)
        {
            modelSpace = control.modelSpace
            paperSpace = control.paperSpace
        }
    }

    // MARK: Blocks

    private mutating func loadBlocks() throws {
        guard let controlHandle = header.handles["BLOCK_CONTROL_OBJECT"],
            case .control(_, let control)? = try store.tableRecord(controlHandle)
        else { throw DWG.Error.invalid("the file has no block control object") }

        var handles = control.entries.filter { $0 != 0 }
        // The model space and the paper space are not always in the entries.
        for special in [control.modelSpace, control.paperSpace]
        where special != 0 && !handles.contains(special) {
            handles.append(special)
        }
        for handle in handles {
            guard case .blockHeader(let record)? = try? store.tableRecord(handle) else { continue }
            let blockEntity = try? store.entity(record.blockEntity)
            let endBlock = try? store.entity(record.endBlockEntity)
            var name = record.entry.name
            if let blockEntity, case .block(let data) = blockEntity.geometry, !data.name.isEmpty {
                name = data.name
            }
            let entities = chain(of: record)
            blocks.append(
                Block(
                    handle: handle, record: record, name: name, blockEntity: blockEntity,
                    endBlockEntity: endBlock, entities: entities))
            blockNames[handle] = name
        }
    }

    /// The entities of a block, in order.
    ///
    /// From R2004 the record lists them; before, the record names the first and the last and each
    /// entity names the next.
    private func chain(of record: BlockHeaderData) -> [UInt64] {
        if version >= .ac1018 { return record.ownedEntities.filter { $0 != 0 } }
        guard record.firstEntity != 0 else { return [] }
        var out: [UInt64] = []
        var seen = Set<UInt64>()
        var handle = record.firstEntity
        while handle != 0, seen.insert(handle).inserted, out.count < 1 << 24 {
            out.append(handle)
            if handle == record.lastEntity { break }
            guard var reader = try? store.reader(for: handle),
                let entity = try? reader.readEntityCommonForChain()
            else { break }
            // With the links "assumed", an entity is followed by the next handle.
            handle = entity.next != 0 ? entity.next : handle + 1
        }
        return out
    }
}

extension ObjectReader {
    /// Reads only the data every entity starts with, which is all a chain walk needs.
    mutating func readEntityCommonForChain() throws -> EntityCommon {
        try readEntityCommon()
    }
}
