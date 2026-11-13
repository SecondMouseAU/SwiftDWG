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

    /// A table record or a block that could not be read, so is not in the document.
    ///
    /// The DXF text records each as a bare `UNREADABLE_<table>` entity, which SwiftDXF tallies in
    /// `skipped`, so that a loss is counted and not silent.
    struct LostRecord: Equatable {
        /// The DXF name of the table: `LAYER`, `LTYPE`, `STYLE`, `DIMSTYLE` or `BLOCK_RECORD`.
        var table: String
        var handle: UInt64
    }

    var lostRecords: [LostRecord] = []

    init(_ data: [UInt8]) throws {
        try self.init(store: try ObjectStore(try Container(data)))
    }

    init(store: ObjectStore) throws {
        let container = store.container
        version = container.version
        self.store = store
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

    /// The control object of a table, or `nil` when the header names none.
    ///
    /// One the header names that cannot be read is damage to the file's structure: every record of
    /// the table is reached through it, so none could be found.
    private func controlObject(_ name: String) throws -> ControlObjectData? {
        guard let handle = header.handles[name], handle != 0 else { return nil }
        do {
            if case .control(_, let control)? = try store.tableRecord(handle) { return control }
        } catch {
            throw DWG.Error.invalid("the \(name) cannot be read (\(error))")
        }
        throw DWG.Error.invalid("the \(name) is not in the file, or is not a control object")
    }

    /// The handles a control object lists, without the empty ones.
    private func listed(by control: ControlObjectData?) -> [UInt64] {
        control?.entries.filter { $0 != 0 } ?? []
    }

    /// The record of a table with this handle, picked out of what is read by `pick`.
    ///
    /// A record that cannot be read, or is not the kind the table holds, is left out and noted in
    /// `lostRecords`.
    private mutating func loadRecord<Value>(
        _ handle: UInt64, in table: String, _ pick: (TableRecord) -> Value?
    ) -> Value? {
        if let record = try? store.tableRecord(handle), let value = pick(record) { return value }
        lostRecords.append(LostRecord(table: table, handle: handle))
        return nil
    }

    private mutating func loadTables() throws {
        let layerControl = try controlObject("LAYER_CONTROL_OBJECT")
        let lineTypeControl = try controlObject("LINETYPE_CONTROL_OBJECT")
        let styleControl = try controlObject("STYLE_CONTROL_OBJECT")
        let dimensionStyleControl = try controlObject("DIMSTYLE_CONTROL_OBJECT")
        let blockControl = try controlObject("BLOCK_CONTROL_OBJECT")

        for handle in listed(by: layerControl) {
            guard let data = loadRecord(handle, in: "LAYER", \.asLayer) else { continue }
            layers.append(Layer(handle: handle, data: data))
            layerNames[handle] = data.entry.name
        }
        // BYBLOCK and BYLAYER are line types too, kept by the control object apart from its entries.
        var lineTypeHandles = listed(by: lineTypeControl)
        if let lineTypeControl {
            for special in [lineTypeControl.byLayer, lineTypeControl.byBlock]
            where special != 0 && !lineTypeHandles.contains(special) {
                lineTypeHandles.insert(special, at: 0)
            }
        }
        for handle in lineTypeHandles {
            guard let data = loadRecord(handle, in: "LTYPE", \.asLineType) else { continue }
            lineTypes.append(LineType(handle: handle, data: data))
            lineTypeNames[handle] = data.entry.name
        }
        for handle in listed(by: styleControl) {
            guard let data = loadRecord(handle, in: "STYLE", \.asTextStyle) else { continue }
            textStyleNames[handle] = data.entry.name
        }
        for handle in listed(by: dimensionStyleControl) {
            guard let data = loadRecord(handle, in: "DIMSTYLE", \.asDimensionStyle) else {
                continue
            }
            dimensionStyles.append(DimensionStyle(handle: handle, data: data))
            dimensionStyleNames[handle] = data.entry.name
        }
        if let blockControl {
            modelSpace = blockControl.modelSpace
            paperSpace = blockControl.paperSpace
        }
    }

    // MARK: Blocks

    private mutating func loadBlocks() throws {
        guard let control = try controlObject("BLOCK_CONTROL_OBJECT") else {
            throw DWG.Error.invalid("the file has no block control object")
        }

        var handles = control.entries.filter { $0 != 0 }
        // The model space and the paper space are not always in the entries.
        for special in [control.modelSpace, control.paperSpace]
        where special != 0 && !handles.contains(special) {
            handles.append(special)
        }
        for handle in handles {
            guard let record = loadRecord(handle, in: "BLOCK_RECORD", \.asBlockHeader) else {
                continue
            }
            let blockEntity = try? store.entity(record.blockEntity)
            let endBlock = try? store.entity(record.endBlockEntity)
            var name = record.entry.name
            if let blockEntity, case .block(let data) = blockEntity.geometry, !data.name.isEmpty {
                name = data.name
            }
            let entities = chain(of: record, at: handle)
            blocks.append(
                Block(
                    handle: handle, record: record, name: name, blockEntity: blockEntity,
                    endBlockEntity: endBlock, entities: entities))
            blockNames[handle] = name
        }
    }

    /// The entities of a block, in order.
    ///
    /// From R2004 the record lists them. Before, the record names the first and the last and each
    /// entity names the one before and the one after, which ``EntityChain`` walks, and falls back
    /// on the owner of each entity when an entity cannot be read.
    private func chain(of record: BlockHeaderData, at handle: UInt64) -> [UInt64] {
        if version >= .ac1018 { return record.ownedEntities.filter { $0 != 0 } }
        return EntityChain.entities(
            first: record.firstEntity, last: record.lastEntity, record: handle,
            excluding: [record.blockEntity, record.endBlockEntity],
            links: { store.chainLinks(of: $0) },
            owner: { store.block(ofEntity: $0, modelSpace: modelSpace, paperSpace: paperSpace) },
            candidates: { store.handles })
    }
}
