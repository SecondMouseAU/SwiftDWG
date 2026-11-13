import Testing

@testable import SwiftDWG

/// What the chain recovery asks of a file: the links of an entity and the block it is in, read
/// from constructed objects of R14 and R2000 layout, which run without a drawing.
@Suite("Entity chain, read from objects")
struct EntityChainStoreTests {
    static let releases: [DWG.Version] = [.ac1014, .ac1015]
    static let modelSpace: UInt64 = 0x31
    static let paperSpace: UInt64 = 0x601

    /// A store holding these objects, as the bytes `SyntheticObject` makes, under their handles.
    static func store(_ objects: [UInt64: [UInt8]], version: DWG.Version) throws -> ObjectStore {
        var bytes: [UInt8] = []
        var map: [UInt64: Int] = [:]
        for (handle, object) in objects.sorted(by: { $0.key < $1.key }) {
            map[handle] = bytes.count
            bytes += object
        }
        // A header with no sections is all an object read needs of the container.
        let container = try Container(Array(version.code.utf8) + [UInt8](repeating: 0, count: 0x20))
        return ObjectStore(
            container: container, classes: [:], map: map, objects: bytes,
            textEncoding: .windowsCP1252)
    }

    /// The object with the first bit of its layer handle, which follows the links, set to make the
    /// handle's code one that does not exist, so that the whole common data cannot be read.
    static func withDamagedLayer(_ object: SyntheticObject) throws -> [UInt8] {
        var bytes = object.bytes()
        var reader = try ObjectReader(
            objects: bytes, offset: 0, version: object.version, textEncoding: .windowsCP1252)
        _ = try reader.readEntityCommonThroughLinks()
        let position = reader.handles.position
        for bit in position..<(position + 8) { bytes[bit >> 3] |= 0x80 >> UInt8(bit & 7) }
        return bytes
    }

    @Test("an entity's links are read as the file gives them", arguments: releases)
    func linksAsGiven(_ version: DWG.Version) throws {
        let given = SyntheticObject(
            version: version, type: ObjectType.line, links: (previous: 0x41, next: 0x43))
        let implied = SyntheticObject(version: version, type: ObjectType.line)
        let store = try Self.store([0x42: given.bytes(), 0x50: implied.bytes()], version: version)

        let links = try #require(store.chainLinks(of: 0x42))
        #expect(links.previous == 0x41)
        #expect(links.next == 0x43)
        // An entity written without links names none; the chain takes the handles next to it.
        let none = try #require(store.chainLinks(of: 0x50))
        #expect(none.previous == 0)
        #expect(none.next == 0)
    }

    @Test("an entity that is not in the file, or cannot be read, has no links", arguments: releases)
    func noLinks(_ version: DWG.Version) throws {
        let entity = SyntheticObject(version: version, type: ObjectType.line).bytes()
        let store = try Self.store(
            [0x42: entity, 0x43: [UInt8](repeating: 0xFF, count: 12)], version: version)
        #expect(store.chainLinks(of: 0x42) != nil)
        #expect(store.chainLinks(of: 0x44) == nil)
        #expect(store.chainLinks(of: 0x43) == nil)
    }

    @Test("the links of an entity are read though a field after them cannot be")
    func linksBeforeTheDamage() throws {
        let object = SyntheticObject(
            version: .ac1015, type: ObjectType.line, links: (previous: 0x41, next: 0x43))
        let damaged = try Self.withDamagedLayer(object)
        let store = try Self.store([0x42: damaged], version: .ac1015)

        // The whole common data is no longer readable ...
        var whole = try #require(try store.reader(for: 0x42))
        #expect(throws: DWG.Error.self) { _ = try whole.readEntityCommon() }
        // ... and the links, which come before the layer, still are.
        let links = try #require(store.chainLinks(of: 0x42))
        #expect(links.previous == 0x41)
        #expect(links.next == 0x43)
    }

    @Test("the block an entity is in comes from its entity mode", arguments: releases)
    func blockOfEntity(_ version: DWG.Version) throws {
        func line(mode: Int) -> [UInt8] {
            SyntheticObject(version: version, type: ObjectType.line, entityMode: mode, owner: 0x77)
                .bytes()
        }
        let store = try Self.store(
            [0x42: line(mode: 0), 0x43: line(mode: 1), 0x44: line(mode: 2)], version: version)
        func block(_ handle: UInt64) -> UInt64? {
            store.block(
                ofEntity: handle, modelSpace: Self.modelSpace, paperSpace: Self.paperSpace)
        }
        #expect(block(0x42) == 0x77)
        #expect(block(0x43) == Self.paperSpace)
        #expect(block(0x44) == Self.modelSpace)
    }

    @Test("no block comes of an object that is not an entity, is missing or cannot be read")
    func noBlock() throws {
        let line = SyntheticObject(version: .ac1015, type: ObjectType.line).bytes()
        // A layer's data is not an entity's, whatever follows its type.
        let layer = SyntheticObject(version: .ac1015, type: ObjectType.layer).bytes()
        let store = try Self.store(
            [0x42: line, 0x43: layer, 0x44: [UInt8](repeating: 0xFF, count: 12)], version: .ac1015)
        func block(_ handle: UInt64) -> UInt64? {
            store.block(
                ofEntity: handle, modelSpace: Self.modelSpace, paperSpace: Self.paperSpace)
        }
        #expect(block(0x42) == Self.modelSpace)
        #expect(block(0x43) == nil)
        #expect(block(0x44) == nil)
        #expect(block(0x45) == nil)
    }

    @Test("the block of an entity is read though a field after the owner cannot be")
    func blockBeforeTheDamage() throws {
        let object = SyntheticObject(
            version: .ac1015, type: ObjectType.line, entityMode: 0, owner: 0x77)
        let store = try Self.store([0x42: try Self.withDamagedLayer(object)], version: .ac1015)
        #expect(store.block(ofEntity: 0x42, modelSpace: 0, paperSpace: 0) == 0x77)
    }

    @Test("an entity mode that names a space the file does not have names no block")
    func noSpace() {
        var common = EntityCommon()
        common.owner = 0x77
        common.entityMode = 0
        #expect(common.block(modelSpace: 0x31, paperSpace: 0x601) == 0x77)
        common.entityMode = 1
        #expect(common.block(modelSpace: 0x31, paperSpace: 0x601) == 0x601)
        #expect(common.block(modelSpace: 0x31, paperSpace: 0) == nil)
        common.entityMode = 2
        #expect(common.block(modelSpace: 0x31, paperSpace: 0x601) == 0x31)
        #expect(common.block(modelSpace: 0, paperSpace: 0x601) == nil)
        common.entityMode = 3
        #expect(common.block(modelSpace: 0x31, paperSpace: 0x601) == nil)
        common.entityMode = 0
        common.owner = 0
        #expect(common.block(modelSpace: 0x31, paperSpace: 0x601) == nil)
    }

    @Test("the entity types the scan looks at are the ones the emitter can name")
    func entityTypes() {
        let classes = [
            600: DWGClass(
                number: 600, proxyFlags: 0, applicationName: "", cppClassName: "AcDbImage",
                dxfName: "IMAGE", wasZombie: false, itemClassID: 0x1F2, instanceCount: 1),
            601: DWGClass(
                number: 601, proxyFlags: 0, applicationName: "", cppClassName: "AcDbDictionaryVar",
                dxfName: "DICTIONARYVAR", wasZombie: false, itemClassID: 0x1F3, instanceCount: 1),
        ]
        // Decoded, and not decoded, entities.
        for type in [ObjectType.line, ObjectType.vertex2D, ObjectType.seqend, ObjectType.attrib] {
            #expect(ObjectType.isEntity(type, classes: classes), "\(type)")
        }
        #expect(ObjectType.isEntity(600, classes: classes))
        // Objects that are not entities, a class of objects, and a class the file does not have.
        for type in [
            ObjectType.block, ObjectType.endBlock, ObjectType.layer, ObjectType.dictionary, 601,
            602,
        ] {
            #expect(!ObjectType.isEntity(type, classes: classes), "\(type)")
        }
    }
}
