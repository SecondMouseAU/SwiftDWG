import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// INSERT and MINSERT read from a DWG, compared with the records of AutoCAD's own DXF export.
///
/// The expected values are the raw groups AutoCAD wrote, so nothing here is checked against
/// SwiftDWG's own output. The block is a handle in the DWG and a name in the DXF, so it is checked
/// by looking the handle up among the DXF's own block records. The attributes and the SEQEND are
/// checked the same way: the DXF gives each the handle of the insert that owns it (group 330).
enum InsertOracle {
    /// What comparing one drawing found.
    struct Result {
        /// Inserts the DWG holds, and how many of them are MINSERTs.
        var decoded = 0
        var arrays = 0
        /// Inserts the DXF holds.
        var expected = 0
        /// Inserts compared with the DXF record of the same handle.
        var byHandle = 0
        /// Inserts compared with a DXF record found by content, because the DXF has none under
        /// their handle.
        var byContent = 0
        /// Inserts that own attributes, and the attributes they own.
        var withAttributes = 0
        var attributes = 0
        /// Inserts whose block handle is not among the DXF's block records, so its name could not
        /// be compared.
        var unresolvedBlocks = 0
        var mismatches: [String] = []
        /// Decoded inserts with no DXF record to compare with.
        var unmatched: [String] = []
        /// DXF records with no decoded insert.
        var dxfOnly: [String] = []
    }

    static func near(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= 1e-9 * max(1, abs(b))
    }

    static func near(_ a: DXF.Point, _ b: (x: Double, y: Double, z: Double)) -> Bool {
        near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z)
    }

    /// Whether two angles in degrees are the same angle, modulo a full turn.
    static func nearAngle(_ degrees: Double, _ expected: Double) -> Bool {
        var difference = (degrees - expected).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        return abs(difference) <= 1e-7
    }

    static func hex(_ handle: UInt64) -> String { String(handle, radix: 16, uppercase: true) }

    /// The decoded INSERT and MINSERT of a drawing.
    static func decode(_ store: ObjectStore) throws -> [(handle: UInt64, data: InsertData)] {
        var out: [(UInt64, InsertData)] = []
        for handle in store.handles {
            guard var reader = try store.reader(for: handle),
                reader.type == ObjectType.insert || reader.type == ObjectType.minsert
            else { continue }
            if case .insert(let data)? = try reader.readEntity()?.geometry {
                out.append((handle, data))
            }
        }
        return out
    }

    /// The name of the block record a handle names in the DXF.
    static func blockName(_ handle: UInt64, in records: [UInt64: DXFRecord]) -> String? {
        guard handle != 0, let block = records[handle], block.type == "BLOCK_RECORD" else {
            return nil
        }
        return block.first(2)
    }

    /// Compares every decoded INSERT and MINSERT with the DXF.
    ///
    /// The DXF export writes a table out again with new handles, so an insert that sits in a
    /// table cell has no record under the handle the DWG gives it. Such an insert is compared
    /// with the DXF record that names the same block at the same point.
    static func compare(_ store: ObjectStore, with records: [UInt64: DXFRecord]) throws -> Result {
        var result = Result()
        result.expected = records.values.filter { $0.type == "INSERT" }.count
        var claimed = Set<UInt64>()
        var orphans: [(handle: UInt64, data: InsertData)] = []

        for entry in try decode(store) {
            result.decoded += 1
            if entry.data.grid != nil { result.arrays += 1 }
            guard let record = records[entry.handle], record.type == "INSERT" else {
                orphans.append(entry)
                continue
            }
            claimed.insert(entry.handle)
            result.byHandle += 1
            let failures =
                check(entry.data, handle: entry.handle, against: record, in: records)
                + kinds(entry.data, in: store)
            result.mismatches += failures.map { "\(hex(entry.handle)) \($0)" }
            if blockName(entry.data.blockHeader, in: records) == nil {
                result.unresolvedBlocks += 1
            }
            if entry.data.hasAttributes { result.withAttributes += 1 }
            result.attributes += entry.data.attributes.count
        }

        for entry in orphans {
            let name = blockName(entry.data.blockHeader, in: records)
            let candidate = records.first { handle, record in
                record.type == "INSERT" && !claimed.contains(handle) && record.first(2) == name
                    && record.point(10, 20, 30).map { near(entry.data.insertion, $0) } == true
            }
            guard let (handle, record) = candidate else {
                result.unmatched.append(hex(entry.handle))
                continue
            }
            claimed.insert(handle)
            result.byContent += 1
            if blockName(entry.data.blockHeader, in: records) == nil {
                result.unresolvedBlocks += 1
            }
            let failures =
                check(entry.data, handle: handle, against: record, in: records)
                + kinds(entry.data, in: store)
            result.mismatches += failures.map { "\(hex(entry.handle)) \($0)" }
        }

        for (handle, record) in records where record.type == "INSERT" && !claimed.contains(handle) {
            result.dxfOnly.append(hex(handle))
        }
        return result
    }

    /// Checks that the handles of an insert lead to the kind of object they should in the DWG.
    static func kinds(_ insert: InsertData, in store: ObjectStore) -> [String] {
        func type(of handle: UInt64) -> Int? { (try? store.reader(for: handle))?.type }
        var failures: [String] = []
        if type(of: insert.blockHeader) != ObjectType.blockHeader { failures.append("block kind") }
        if insert.attributes.contains(where: { type(of: $0) != ObjectType.attrib }) {
            failures.append("attribute kind")
        }
        if insert.hasAttributes, type(of: insert.seqend) != ObjectType.seqend {
            failures.append("seqend kind")
        }
        return failures
    }

    /// Compares one insert with its DXF record; `handle` is the handle the record has.
    static func check(
        _ insert: InsertData, handle: UInt64, against record: DXFRecord,
        in records: [UInt64: DXFRecord]
    ) -> [String] {
        var failures: [String] = []
        func expect(_ ok: Bool, _ field: String) { if !ok { failures.append(field) } }

        expect(record.point(10, 20, 30).map { near(insert.insertion, $0) } ?? false, "insertion")
        expect(near(insert.xScale, record.double(41) ?? 1), "xScale")
        expect(near(insert.yScale, record.double(42) ?? 1), "yScale")
        expect(near(insert.zScale, record.double(43) ?? 1), "zScale")
        expect(nearAngle(insert.rotation * 180 / .pi, record.double(50) ?? 0), "rotation")
        expect(near(insert.extrusion, record.point(210, 220, 230) ?? (0, 0, 1)), "extrusion")
        // The export writes an anonymous block out again under a handle of its own, and names a
        // dynamic block reference after its definition, so for those the handle is not among the
        // DXF's block records. Then only `kinds` can check it, that it leads to a block record.
        if let name = blockName(insert.blockHeader, in: records) {
            expect(name == record.first(2), "blockHeader")
        } else {
            expect(insert.blockHeader != 0, "blockHeader")
        }

        if let grid = insert.grid {
            expect(grid.columnCount == (record.int(70) ?? 1), "columnCount")
            expect(grid.rowCount == (record.int(71) ?? 1), "rowCount")
            expect(near(grid.columnSpacing, record.double(44) ?? 0), "columnSpacing")
            expect(near(grid.rowSpacing, record.double(45) ?? 0), "rowSpacing")
        } else {
            expect(record.int(70) == nil && record.int(71) == nil, "grid absent")
        }

        // Attributes and the SEQEND closing them are the records that name this insert as their
        // owner, and an insert without attributes has none.
        expect(insert.hasAttributes == (record.int(66) == 1), "hasAttributes")
        let attributes = Set(
            records.filter { $0.value.type == "ATTRIB" && ownerOf($0.value) == handle }.keys)
        expect(Set(insert.attributes) == attributes, "attributes")
        expect(insert.attributes.count == attributes.count, "attribute count")
        if insert.hasAttributes {
            let end = records[insert.seqend]
            expect(end?.type == "SEQEND" && end.map(ownerOf) == handle, "seqend")
        } else {
            expect(insert.seqend == 0 && insert.attributes.isEmpty, "no seqend")
        }
        return failures
    }

    /// The handle in a record's owner group (330).
    static func ownerOf(_ record: DXFRecord) -> UInt64? {
        record.first(330).flatMap { UInt64($0, radix: 16) }
    }
}

@Suite("INSERT and MINSERT against AutoCAD's DXF")
struct InsertTests {
    @Test("the INSERTs of a small AutoCAD drawing equal those in its DXF export")
    func smallDrawing() throws {
        let store = try ObjectStore(try Container(try Fixtures.data("BLOCKPOINTPARAMETER.dwg")))
        let records = try DXFGroups.records(
            in: Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dxf"))
        let result = try InsertOracle.compare(store, with: records)
        #expect(result.decoded == 3)
        #expect(result.expected == result.decoded)
        #expect(result.byHandle == 3)
        #expect(result.mismatches.isEmpty, "\(result.mismatches.prefix(5))")
        #expect(result.unmatched.isEmpty && result.dxfOnly.isEmpty)
    }

    @Test("the ten dynamic block drawings read to the INSERTs their DXF exports have")
    func dynamicBlocks() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        let directory = corpus.appendingPathComponent("dynamic-blocks")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".dwg") }.sorted()
        #expect(names.count == 10)
        var decoded = 0
        var unresolved = 0
        for file in names {
            let stem = String(file.dropLast(4))
            let data = [UInt8](try Data(contentsOf: directory.appendingPathComponent(file)))
            let store = try ObjectStore(try Container(data))
            let records = try DXFGroups.records(
                in: directory.appendingPathComponent("\(stem).dxf"))
            let result = try InsertOracle.compare(store, with: records)
            decoded += result.decoded
            unresolved += result.unresolvedBlocks
            #expect(result.mismatches.isEmpty, "\(stem) \(result.mismatches.prefix(5))")
            #expect(result.unmatched.isEmpty && result.dxfOnly.isEmpty, "\(stem)")
            #expect(result.byHandle + result.byContent == result.expected, "\(stem)")
        }
        #expect(decoded == 25)
        #expect(unresolved == 2)
    }

    @Test("every AutoCAD sample from R2004 to R2018 reads to the INSERTs its DXF has")
    func corpus() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        for name in Fixtures.corpusNames {
            let data = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
            let store = try ObjectStore(try Container(data))
            let records = try DXFGroups.records(
                in: corpus.appendingPathComponent("\(name)_ascii.dxf"))
            let result = try InsertOracle.compare(store, with: records)
            #expect(result.decoded == 14 && result.expected == 14, "\(name)")
            #expect(result.byHandle == 12 && result.byContent == 2, "\(name)")
            #expect(result.withAttributes == 2 && result.attributes == 4, "\(name)")
            #expect(result.unresolvedBlocks == 1, "\(name)")
            #expect(result.mismatches.isEmpty, "\(name) \(result.mismatches.prefix(5))")
            #expect(result.unmatched.isEmpty, "\(name) \(result.unmatched)")
            #expect(result.dxfOnly.isEmpty, "\(name) \(result.dxfOnly)")
        }
    }
}
