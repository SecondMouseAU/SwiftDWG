import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// What a damaged file does: a table's control object that cannot be read stops the read, and a
/// record or block that cannot be read is left out and counted.
///
/// The damage is done to the objects of a drawing that is committed, `BLOCKPOINTPARAMETER.dwg`, by
/// taking an object out of the file's map of them, or by overwriting its first bytes.
@Suite("Damaged files")
struct DamagedFileTests {
    static let controlObjects = [
        "LAYER_CONTROL_OBJECT", "LINETYPE_CONTROL_OBJECT", "STYLE_CONTROL_OBJECT",
        "DIMSTYLE_CONTROL_OBJECT", "BLOCK_CONTROL_OBJECT",
    ]

    private static func intactStore() throws -> ObjectStore {
        try ObjectStore(try Container(try Fixtures.data("BLOCKPOINTPARAMETER.dwg")))
    }

    /// The store with the objects of these handles taken out, as if the file did not hold them.
    private static func store(without handles: [UInt64]) throws -> ObjectStore {
        let whole = try intactStore()
        return ObjectStore(
            container: whole.container, classes: whole.classes,
            map: whole.map.filter { !handles.contains($0.key) }, objects: whole.objects,
            textEncoding: whole.textEncoding)
    }

    /// The store with the first bytes of these objects overwritten, so they are there but not
    /// readable.
    private static func store(overwriting handles: [UInt64]) throws -> ObjectStore {
        let whole = try intactStore()
        var objects = whole.objects
        for handle in handles {
            let offset = try #require(whole.map[handle])
            for index in offset..<(offset + 8) { objects[index] = 0xFF }
        }
        return ObjectStore(
            container: whole.container, classes: whole.classes, map: whole.map, objects: objects,
            textEncoding: whole.textEncoding)
    }

    private static func dxf(of document: Document) throws -> DXF.Drawing {
        var emitter = DXFEmitter(document)
        return try DXF.read(text: emitter.text(), options: .init())
    }

    @Test("a file with all its objects reads with nothing lost")
    func intact() throws {
        let document = try Document(store: try Self.intactStore())
        #expect(document.lostRecords.isEmpty)
        #expect(!document.layers.isEmpty)
        let drawing = try Self.dxf(of: document)
        #expect(drawing.skipped.keys.filter { $0.hasPrefix("UNREADABLE_") }.isEmpty)
    }

    @Test(
        "a control object that is missing from the file stops the read", arguments: controlObjects)
    func missingControlObject(_ name: String) throws {
        let intact = try Document(store: try Self.intactStore())
        let handle = try #require(intact.header.handles[name])
        #expect(handle != 0)
        #expect(throws: DWG.Error.self) {
            _ = try Document(store: try Self.store(without: [handle]))
        }
    }

    @Test("a control object whose bytes are damaged stops the read", arguments: controlObjects)
    func damagedControlObject(_ name: String) throws {
        let intact = try Document(store: try Self.intactStore())
        let handle = try #require(intact.header.handles[name])
        #expect(throws: DWG.Error.self) {
            _ = try Document(store: try Self.store(overwriting: [handle]))
        }
    }

    @Test("a record or a block that cannot be read is left out and counted by its table")
    func lostRecords() throws {
        let intact = try Document(store: try Self.intactStore())
        let layer = try #require(intact.layers.last)
        let lineType = try #require(intact.lineTypes.last)
        let textStyle = try #require(intact.textStyleNames.keys.sorted().last)
        let dimensionStyle = try #require(intact.dimensionStyles.last)
        let block = try #require(
            intact.blocks.last { $0.handle != intact.modelSpace && $0.handle != intact.paperSpace })
        let lost: [(table: String, handle: UInt64)] = [
            ("LAYER", layer.handle), ("LTYPE", lineType.handle), ("STYLE", textStyle),
            ("DIMSTYLE", dimensionStyle.handle), ("BLOCK_RECORD", block.handle),
        ]

        for (table, handle) in lost {
            for store in [try Self.store(without: [handle]), try Self.store(overwriting: [handle])]
            {
                let document = try Document(store: store)
                #expect(
                    document.lostRecords == [Document.LostRecord(table: table, handle: handle)],
                    "\(table)")
                let drawing = try Self.dxf(of: document)
                #expect(drawing.skipped["UNREADABLE_\(table)"] == 1, "\(table) \(drawing.skipped)")
            }
        }

        // The rest of each table is still there.
        let document = try Document(store: try Self.store(without: [layer.handle]))
        #expect(document.layers.count == intact.layers.count - 1)
        #expect(document.blocks.count == intact.blocks.count)
    }
}
