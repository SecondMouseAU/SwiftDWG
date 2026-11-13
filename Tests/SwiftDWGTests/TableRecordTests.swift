import Foundation
import Testing

@testable import SwiftDWG

/// Writes bit-coded values, so a test can make the bytes of an object by hand.
struct TableBitWriter {
    private(set) var bytes: [UInt8] = []
    private var used = 0

    mutating func bit(_ value: Bool) {
        if used % 8 == 0 { bytes.append(0) }
        if value { bytes[bytes.count - 1] |= 0x80 >> UInt8(used % 8) }
        used += 1
    }

    mutating func bits(_ value: UInt64, _ count: Int) {
        for index in stride(from: count - 1, through: 0, by: -1) {
            bit((value >> UInt64(index)) & 1 == 1)
        }
    }

    mutating func byte(_ value: UInt8) { bits(UInt64(value), 8) }

    /// A bit short, in its shortest form.
    mutating func bitShort(_ value: Int) {
        switch value {
        case 0: bits(2, 2)
        case 256: bits(3, 2)
        case 1...255:
            bits(1, 2)
            byte(UInt8(value))
        default:
            bits(0, 2)
            byte(UInt8(truncatingIfNeeded: value))
            byte(UInt8(truncatingIfNeeded: value >> 8))
        }
    }

    /// A bit long in its raw form: four bytes, low first.
    mutating func rawBitLong(_ value: UInt32) {
        bits(0, 2)
        for index in 0..<4 { byte(UInt8(truncatingIfNeeded: value >> UInt32(8 * index))) }
    }

    /// A variable text of single-byte characters, as R2004 and earlier write it.
    mutating func text(_ string: String) {
        let raw = Array(string.utf8) + [0]
        bitShort(raw.count)
        for byte in raw { self.byte(byte) }
    }

    /// The bytes of an object of this release that holds what was written, as the objects section
    /// would: its size, then its type, then the data.
    func object(type: Int) -> [UInt8] {
        var body = TableBitWriter()
        body.bitShort(type)
        for index in 0..<used { body.bit(bytes[index / 8] & (0x80 >> UInt8(index % 8)) != 0) }
        let size = body.bytes.count
        return [UInt8(size & 0xFF), UInt8(size >> 8)] + body.bytes
    }
}

@Suite("Table record reading")
struct TableRecordTests {
    func makeReader(_ writer: TableBitWriter, version: DWG.Version) throws -> ObjectReader {
        try ObjectReader(
            objects: writer.object(type: ObjectType.layer), offset: 0, version: version,
            textEncoding: .windowsCP1252)
    }

    @Test("a table colour is read in each of its forms, and the names that follow it are skipped")
    func t_cmcColours() throws {
        var writer = TableBitWriter()
        func colour(_ word: UInt32, names: [String] = []) {
            writer.bitShort(0)
            writer.rawBitLong(word)
            writer.byte(UInt8((names.count > 0 ? 1 : 0) | (names.count > 1 ? 2 : 0)))
            for name in names { writer.text(name) }
        }
        colour(0xC000_0000)
        colour(0xC100_0000)
        colour(0xC300_0096)
        colour(0xC211_2233, names: ["Red", "DIC 4"])
        writer.bitShort(77)  // what follows, to show the reader is where it should be
        var reader = try makeReader(writer, version: .ac1018)
        #expect(try reader.readCmColor() == .byLayer)
        #expect(try reader.readCmColor() == .byBlock)
        #expect(try reader.readCmColor() == .index(150))
        #expect(try reader.readCmColor() == .rgb(red: 0x11, green: 0x22, blue: 0x33))
        #expect(try reader.main.readBitShort() == 77)
    }

    @Test("before R2004 a table colour is an index")
    func t_oldColours() throws {
        var writer = TableBitWriter()
        writer.bitShort(256)
        writer.bitShort(0)
        writer.bitShort(5)
        var reader = try makeReader(writer, version: .ac1015)
        #expect(try reader.readCmColor() == .byLayer)
        #expect(try reader.readCmColor() == .byBlock)
        #expect(try reader.readCmColor() == .index(5))
    }

    @Test("a layer's line weight code means what the standard weights say")
    func t_lineWeights() {
        var layer = LayerData()
        let expected = [0: 0, 1: 5, 8: 30, 9: 35, 11: 50, 17: 100, 23: 211, 28: -1, 29: -1, 30: -2]
        for (code, weight) in expected {
            layer.lineWeightCode = code
            #expect(layer.lineWeight == weight, "code \(code)")
        }
        layer.lineWeightCode = 31
        #expect(layer.lineWeight == -3)
        layer.lineWeightCode = 24
        #expect(layer.lineWeight == -3)
    }

    @Test("table records cut off at any byte throw and never trap")
    func t_truncation() throws {
        let store = try ObjectStore(try Container(try Fixtures.data("BLOCKPOINTPARAMETER.dwg")))
        let handles = store.handles
        var cuts = 0
        for handle in handles {
            guard let offset = store.map[handle], let reader = try store.reader(for: handle),
                TableOracle.dxfType(of: reader.type) != nil
            else { continue }
            // Cut the section at a run of points from the start of the object to a little past it.
            for cut in stride(from: offset, to: min(offset + 4096, store.objects.count), by: 9) {
                let objects = Array(store.objects.prefix(cut))
                guard
                    var cutReader = try? ObjectReader(
                        objects: objects, offset: offset, version: store.container.version,
                        textEncoding: store.textEncoding)
                else { continue }
                if cutReader.type == ObjectType.block || cutReader.type == ObjectType.endBlock {
                    _ = try? cutReader.readEntity()
                } else {
                    _ = try? cutReader.readTableRecord()
                }
                cuts += 1
            }
        }
        #expect(cuts > 100)
    }

    @Test("table records with a byte changed throw or read, and never trap")
    func t_damage() throws {
        let store = try ObjectStore(try Container(try Fixtures.data("BLOCKPOINTPARAMETER.dwg")))
        var objects = store.objects
        var changes = 0
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for handle in store.handles {
            guard let offset = store.map[handle], let reader = try store.reader(for: handle),
                TableOracle.dxfType(of: reader.type) != nil
            else { continue }
            let end = min(offset + 160, objects.count)
            for position in stride(from: offset, to: end, by: 3) {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let original = objects[position]
                objects[position] = UInt8(truncatingIfNeeded: seed >> 33)
                guard
                    var changed = try? ObjectReader(
                        objects: objects, offset: offset, version: store.container.version,
                        textEncoding: store.textEncoding)
                else {
                    objects[position] = original
                    continue
                }
                if changed.type == ObjectType.block || changed.type == ObjectType.endBlock {
                    _ = try? changed.readEntity()
                } else {
                    _ = try? changed.readTableRecord()
                }
                objects[position] = original
                changes += 1
            }
        }
        #expect(changes > 100)
    }
}
