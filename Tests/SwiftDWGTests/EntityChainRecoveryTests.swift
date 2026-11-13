import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// Damaged entities in an R2000 drawing, where a block's entities are a chain of links: the
/// block keeps all of its entities, and the drawing counts the damaged ones and no others.
///
/// The drawing is `sample_AC1015`, which needs `DWG_CORPUS`; the tests are skipped without it. The
/// chain's own logic is tested without a file in `EntityChainTests`.
@Suite("Entity chain recovery in an R2000 drawing")
struct EntityChainRecoveryTests {
    /// The intact drawing: its store, its document and what its DXF holds.
    struct Sample {
        var store: ObjectStore
        var document: Document
        var total: Int

        var modelSpace: Document.Block {
            document.blocks.first { $0.handle == document.modelSpace } ?? document.blocks[0]
        }
    }

    static func sample(_ corpus: URL) throws -> Sample {
        let file = corpus.appendingPathComponent("sample_AC1015.dwg")
        let bytes = [UInt8](try Data(contentsOf: file))
        let store = try ObjectStore(try Container(bytes))
        let document = try Document(store: store)
        return Sample(
            store: store, document: document,
            total: counted(try DamagedFileTests.dxf(of: document)))
    }

    /// Every entity of a drawing, modelled or skipped, in model space and in the blocks.
    static func counted(_ drawing: DXF.Drawing) -> Int {
        let skipped = drawing.skipped.values.reduce(0, +)
        let inBlocks = drawing.blocks.reduce(0) { total, block in
            total + block.skippedByLayer.values.reduce(0) { $0 + $1.values.reduce(0, +) }
        }
        return DamagedFileTests.entityCount(drawing) + skipped + inBlocks
    }

    /// How many entities were counted as unreadable, by the name they were counted under.
    static func unreadable(_ drawing: DXF.Drawing) -> [String: Int] {
        var out: [String: Int] = [:]
        for type in Set(drawing.skipped.keys).union(drawing.blocks.flatMap(\.skippedByLayer.keys))
        where type.hasPrefix("UNREADABLE_") {
            out[type] = DamagedFileTests.skipped(type, in: drawing)
        }
        return out
    }

    /// Reads the damaged file and checks that every block has the entities it has when intact,
    /// the unreadable ones among them.
    ///
    /// With `names`, it also checks that the drawing counts the unreadable entities under these
    /// names and no others, and that it has as many entities, modelled or skipped, as the intact
    /// drawing, each damaged entity being counted in the place of the entity it was. That does
    /// not hold for an INSERT, which is a block reference and not one of the drawing's entities.
    static func expectNoneLost(
        _ damaged: ObjectStore, counted names: [String: Int]? = nil, in sample: Sample,
        _ label: String
    ) throws {
        let document = try Document(store: damaged)
        #expect(document.lostRecords == sample.document.lostRecords, "\(label)")
        #expect(
            document.blocks.map(\.entities) == sample.document.blocks.map(\.entities), "\(label)")
        guard let names else { return }

        let drawing = try DamagedFileTests.dxf(of: document)
        #expect(Self.unreadable(drawing) == names, "\(label)")
        #expect(Self.counted(drawing) == sample.total, "\(label)")
    }

    /// The name an entity that cannot be read is counted under when its object can be opened.
    static func countedName(_ handle: UInt64, in store: ObjectStore) throws -> String {
        let reader = try #require(try store.reader(for: handle))
        let name =
            ObjectType.typeName(reader.type, classes: store.classes)
            ?? ObjectType.decodedTypeName(reader.type)
        return "UNREADABLE_\(try #require(name))"
    }

    @Test("one damaged entity is the only one a block loses: the first, a middle one, the last")
    func oneDamagedEntity() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        let sample = try Self.sample(corpus)
        let entities = sample.modelSpace.entities
        #expect(entities.count > 100)

        for index in [0, entities.count / 2, entities.count - 1] {
            let handle = entities[index]
            let label = "entity \(index) of \(entities.count), handle \(handle)"
            try Self.expectNoneLost(
                DamagedFileTests.remove([handle], from: sample.store),
                counted: ["UNREADABLE_OBJECT": 1], in: sample, label)
            try Self.expectNoneLost(
                try DamagedFileTests.overwrite([handle], in: sample.store),
                counted: ["UNREADABLE_OBJECT": 1], in: sample, label)
        }
    }

    @Test("damaging any one entity of any block leaves every block with all its entities")
    func anyOneEntity() throws {
        guard let corpus = Fixtures.corpus else { return }
        let sample = try Self.sample(corpus)
        for block in sample.document.blocks {
            for handle in block.entities {
                try Self.expectNoneLost(
                    DamagedFileTests.remove([handle], from: sample.store), in: sample,
                    "\(block.name) \(handle)")
            }
        }
    }

    @Test("two damaged entities, with others between them, lose only those two")
    func twoDamagedEntities() throws {
        guard let corpus = Fixtures.corpus else { return }
        let sample = try Self.sample(corpus)
        let model = sample.modelSpace.entities
        // A block whose entities name it as their owner, where model space entities name no owner.
        let owned = try #require(
            sample.document.blocks
                .filter { $0.handle != sample.document.modelSpace }
                .max { $0.entities.count < $1.entities.count })
        #expect(owned.entities.count > 10)
        if let first = owned.entities.first, var reader = try sample.store.reader(for: first) {
            #expect(try reader.readEntityCommon().entityMode == 0)
        }
        if let first = model.first, var reader = try sample.store.reader(for: first) {
            #expect(try reader.readEntityCommon().entityMode == 2)
        }

        let pairs: [(name: String, entities: [UInt64], at: [Int])] = [
            ("model space, entities between", model, [10, 50]),
            ("model space, the first and the last", model, [0, model.count - 1]),
            ("model space, next to each other", model, [70, 71]),
            ("model space, one between", model, [30, 32]),
            ("a block, entities between", owned.entities, [5, 20]),
            ("a block, the first and the last", owned.entities, [0, owned.entities.count - 1]),
        ]
        for (name, entities, at) in pairs {
            let handles = at.map { entities[$0] }
            try Self.expectNoneLost(
                DamagedFileTests.remove(handles, from: sample.store),
                counted: ["UNREADABLE_OBJECT": 2], in: sample, name)
            try Self.expectNoneLost(
                try DamagedFileTests.overwrite(handles, in: sample.store),
                counted: ["UNREADABLE_OBJECT": 2], in: sample, name)
        }
    }

    @Test("a damaged field after the links does not break the chain, and the entity is counted")
    func damagedAfterTheLinks() throws {
        guard let corpus = Fixtures.corpus else { return }
        let sample = try Self.sample(corpus)
        // Three in a row: the walks stop at the ones either side only if the data after the links
        // is read, and then the one in the middle belongs to neither walk.
        let handles = Array(sample.modelSpace.entities[40...42])

        var objects = sample.store.objects
        for handle in handles {
            var reader = try #require(try sample.store.reader(for: handle))
            _ = try reader.readEntityCommonThroughLinks()
            // The layer's handle follows the links. A code that does not exist makes the whole
            // common data unreadable, and leaves the links as they were.
            let position = reader.handles.position
            for bit in position..<(position + 8) { objects[bit >> 3] |= 0x80 >> UInt8(bit & 7) }
        }
        let damaged = ObjectStore(
            container: sample.store.container, classes: sample.store.classes,
            map: sample.store.map, objects: objects, textEncoding: sample.store.textEncoding)
        for handle in handles {
            #expect(throws: DWG.Error.self) { _ = try damaged.entity(handle) }
        }

        var names: [String: Int] = [:]
        for handle in handles {
            names[try Self.countedName(handle, in: sample.store), default: 0] += 1
        }
        try Self.expectNoneLost(damaged, counted: names, in: sample, "layer handles of 40...42")
    }
}
