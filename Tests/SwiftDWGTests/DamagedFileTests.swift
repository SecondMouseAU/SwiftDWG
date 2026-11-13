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
        remove(handles, from: try intactStore())
    }

    /// The store with the first bytes of these objects overwritten, so they are there but not
    /// readable.
    private static func store(overwriting handles: [UInt64]) throws -> ObjectStore {
        try overwrite(handles, in: try intactStore())
    }

    /// `whole` with the objects of these handles taken out of its map.
    static func remove(_ handles: [UInt64], from whole: ObjectStore) -> ObjectStore {
        ObjectStore(
            container: whole.container, classes: whole.classes,
            map: whole.map.filter { !handles.contains($0.key) }, objects: whole.objects,
            textEncoding: whole.textEncoding)
    }

    /// `whole` with the first bytes of these objects overwritten.
    static func overwrite(_ handles: [UInt64], in whole: ObjectStore) throws -> ObjectStore {
        var objects = whole.objects
        for handle in handles {
            let offset = try #require(whole.map[handle])
            for index in offset..<(offset + 8) { objects[index] = 0xFF }
        }
        return ObjectStore(
            container: whole.container, classes: whole.classes, map: whole.map, objects: objects,
            textEncoding: whole.textEncoding)
    }

    /// The store with the size of these objects cut to `size` bytes, so that each opens, with its
    /// type readable, and runs out of data when it is decoded.
    private static func store(truncating handles: [UInt64], to size: Int) throws -> ObjectStore {
        let whole = try intactStore()
        var objects = whole.objects
        for handle in handles {
            // The size leads the object, as a modular short.
            let offset = try #require(whole.map[handle])
            objects[offset] = UInt8(size)
            objects[offset + 1] = 0
        }
        return ObjectStore(
            container: whole.container, classes: whole.classes, map: whole.map, objects: objects,
            textEncoding: whole.textEncoding)
    }

    static func dxf(of document: Document) throws -> DXF.Drawing {
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

    /// The entities of a drawing that SwiftDXF models, in model space and in the blocks.
    static func entityCount(_ drawing: DXF.Drawing) -> Int {
        drawing.entities.count + drawing.blocks.reduce(0) { $0 + $1.entities.count }
    }

    /// How many entities of this skipped type SwiftDXF tallied: in model space, which `skipped`
    /// holds, and in each block, which keeps its own count by layer.
    static func skipped(_ type: String, in drawing: DXF.Drawing) -> Int {
        drawing.skipped[type, default: 0]
            + drawing.blocks.reduce(0) { $0 + ($1.skippedByLayer[type]?.values.reduce(0, +) ?? 0) }
    }

    @Test("an entity whose object cannot be opened, or is not in the file, is counted as an object")
    func lostObject() throws {
        let store = try Self.intactStore()
        let intact = try Document(store: store)
        let before = Self.entityCount(try Self.dxf(of: intact))
        let handle = try #require(
            intact.blocks.flatMap(\.entities).first {
                if case .line? = (try? store.entity($0))?.geometry { return true }
                return false
            })

        for damaged in [try Self.store(without: [handle]), try Self.store(overwriting: [handle])] {
            let drawing = try Self.dxf(of: try Document(store: damaged))
            #expect(Self.skipped("UNREADABLE_OBJECT", in: drawing) == 1)
            #expect(Self.entityCount(drawing) == before - 1)
        }
    }

    @Test("a decoded entity that runs out of data is counted by its type")
    func undecodableEntity() throws {
        let store = try Self.intactStore()
        let intact = try Document(store: store)
        let before = Self.entityCount(try Self.dxf(of: intact))
        let handle = try #require(
            intact.blocks.flatMap(\.entities).first {
                if case .line? = (try? store.entity($0))?.geometry { return true }
                return false
            })

        // Five bytes hold the type and not the rest, for the first LINE of this drawing.
        let drawing = try Self.dxf(
            of: try Document(store: try Self.store(truncating: [handle], to: 5)))
        #expect(Self.skipped("UNREADABLE_LINE", in: drawing) == 1)
        #expect(Self.skipped("UNREADABLE_OBJECT", in: drawing) == 0)
        #expect(Self.entityCount(drawing) == before - 1)
    }

    /// How often a record of this type starts in DXF text.
    private static func records(_ type: String, in text: String) -> Int {
        text.components(separatedBy: "\n0\n\(type)\n").count - 1
    }

    @Test("a polyline that has lost a vertex is counted whole, not written short")
    func lostVertex() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        // R2000 names the first vertex and each vertex the next; R2018 lists them.
        for name in ["sample_AC1015", "sample_AC1032"] {
            let bytes = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
            let whole = try ObjectStore(try Container(bytes))
            let intact = try Document(store: whole)

            var vertex: UInt64?
            for handle in intact.blocks.flatMap(\.entities) where vertex == nil {
                switch (try? whole.entity(handle))?.geometry {
                case .polyline2D(let polyline)?:
                    vertex = polyline.vertexHandles.first { $0 != 0 } ?? polyline.firstVertex
                case .polyline3D(let polyline)?:
                    vertex = polyline.vertexHandles.first { $0 != 0 } ?? polyline.firstVertex
                default: break
                }
            }
            let lost = try #require(vertex, "\(name) has a 2D or 3D polyline")
            #expect(lost != 0, "\(name)")

            var intactEmitter = DXFEmitter(intact)
            let before = intactEmitter.text()
            let damaged = ObjectStore(
                container: whole.container, classes: whole.classes,
                map: whole.map.filter { $0.key != lost }, objects: whole.objects,
                textEncoding: whole.textEncoding)
            var damagedEmitter = DXFEmitter(try Document(store: damaged))
            let after = damagedEmitter.text()

            #expect(Self.records("UNREADABLE_POLYLINE", in: after) == 1, "\(name)")
            #expect(
                Self.records("POLYLINE", in: after) == Self.records("POLYLINE", in: before) - 1,
                "\(name)")
            // None of the lost polyline's vertices is written without it.
            #expect(
                Self.records("VERTEX", in: after) < Self.records("VERTEX", in: before), "\(name)")
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
