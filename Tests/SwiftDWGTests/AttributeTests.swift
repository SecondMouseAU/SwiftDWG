import Foundation
import Testing

@testable import SwiftDWG

/// ATTRIB and ATTDEF read from a DWG and written as DXF text, compared with the records of
/// AutoCAD's own DXF export of the same drawing.
///
/// The expected side is the raw groups AutoCAD wrote, so nothing here is checked against what
/// SwiftDWG decoded. Every sample of ACadSharp's corpus holds the same four attributes (on two
/// inserts, one with three and one with one), five definitions in one block, and from R2018 a
/// multi-line attribute and definition. No drawing that is committed has an attribute, so these
/// tests need `DWG_CORPUS` and are skipped without it.
enum AttributeOracle {
    /// What comparing one drawing's records found.
    struct Result {
        /// Records compared with the DXF's, by type.
        var compared: [String: Int] = [:]
        var mismatches: [String] = []
        /// Attribute records that the DWG's text has and the DXF has not.
        var oursOnly: [String] = []
        /// Attribute records that the DXF has and the DWG's text has not.
        var dxfOnly: [String] = []
    }

    static func hex(_ handle: UInt64) -> String { String(handle, radix: 16, uppercase: true) }

    /// The groups of a record that both sides write: not the subclass markers (100) and the owner
    /// (330), and not the extension dictionary, which `plain` leaves out.
    static func comparable(_ record: DXFRecord) -> [DXFGroup] {
        record.plain.filter { $0.code != 100 && $0.code != 330 }
    }

    /// Whether two group values are the same: numbers to a relative 1e-9, the rest exactly.
    static func same(_ a: String, _ b: String) -> Bool {
        if let x = Double(a), let y = Double(b) { return abs(x - y) <= 1e-9 * max(1, abs(y)) }
        return a == b
    }

    /// The first difference between two lists of groups, or `nil` when they are the same.
    static func difference(_ ours: [DXFGroup], _ theirs: [DXFGroup]) -> String? {
        for (index, pair) in zip(ours, theirs).enumerated()
        where pair.0.code != pair.1.code || !same(pair.0.value, pair.1.value) {
            return "group \(index): \(pair.0.code)=\(pair.0.value) is not "
                + "\(pair.1.code)=\(pair.1.value)"
        }
        if ours.count != theirs.count { return "\(ours.count) groups, not \(theirs.count)" }
        return nil
    }

    /// Whether a DXF record is one the comparison covers: an ATTRIB, an ATTDEF, or the SEQEND of
    /// an INSERT (the SEQEND of a polyline is written by the polyline's own code).
    static func isCovered(_ record: DXFRecord, in records: [UInt64: DXFRecord]) -> Bool {
        switch record.type {
        case "ATTRIB", "ATTDEF": return true
        case "SEQEND": return records[record.handleValue(330)]?.type == "INSERT"
        default: return false
        }
    }

    /// Compares every attribute record and INSERT SEQEND of the DXF with the one of the same
    /// handle in the DWG's text, group for group.
    static func compare(ours: [UInt64: DXFRecord], theirs: [UInt64: DXFRecord]) -> Result {
        var result = Result()
        for (handle, expected) in theirs where isCovered(expected, in: theirs) {
            guard let actual = ours[handle], actual.type == expected.type else {
                result.dxfOnly.append("\(expected.type) \(hex(handle))")
                continue
            }
            result.compared[expected.type, default: 0] += 1
            if let found = difference(comparable(actual), comparable(expected)) {
                result.mismatches.append("\(expected.type) \(hex(handle)) \(found)")
            }
        }
        for (handle, record) in ours where ["ATTRIB", "ATTDEF"].contains(record.type) {
            if theirs[handle]?.type != record.type {
                result.oursOnly.append("\(record.type) \(hex(handle))")
            }
        }
        return result
    }

    /// The handles of the attributes of each INSERT that has group 66 set, in order, and the
    /// handle of the SEQEND that ends them last.
    static func runs(_ sequence: [DXFSectionRecord]) -> [UInt64: [UInt64]] {
        var out: [UInt64: [UInt64]] = [:]
        var open: UInt64?
        for item in sequence {
            let record = item.record
            switch record.type {
            case "INSERT":
                open = record.first(66) == "1" ? record.handle : nil
                if let open { out[open] = [] }
            case "ATTRIB":
                if let open, let handle = record.handle { out[open, default: []].append(handle) }
            case "SEQEND":
                if let open, let handle = record.handle { out[open, default: []].append(handle) }
                open = nil
            case "UNREADABLE_ATTRIB":
                break  // counted, and the run goes on
            default:
                open = nil
            }
        }
        return out
    }

    /// The handles of the ATTDEFs of each block, in order, by upper-case block name.
    static func definitions(_ sequence: [DXFSectionRecord]) -> [String: [UInt64]] {
        var out: [String: [UInt64]] = [:]
        var block: String?
        for item in sequence {
            switch item.record.type {
            case "BLOCK": block = item.record.first(2)?.uppercased()
            case "ENDBLK": block = nil
            case "ATTDEF":
                if let block, let handle = item.record.handle {
                    out[block, default: []].append(handle)
                }
            default: break
            }
        }
        return out
    }

    /// How many records of a type the text has.
    static func count(_ type: String, in sequence: [DXFSectionRecord]) -> Int {
        sequence.filter { $0.record.type == type }.count
    }
}

@Suite("ATTRIB and ATTDEF against AutoCAD's DXF")
struct AttributeTests {
    static let releases = ["AC1015", "AC1018", "AC1021", "AC1024", "AC1027", "AC1032"]

    /// The DWG of a sample, and the text DWG writes for it.
    private static func text(of name: String, in corpus: URL) throws -> String {
        try DWG.dxfText(data: try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
    }

    private static func dxf(_ release: String, in corpus: URL) -> URL {
        corpus.appendingPathComponent("sample_\(release)_ascii.dxf")
    }

    @Test(
        "every attribute record equals AutoCAD's, group for group",
        .enabled(if: Fixtures.corpus != nil), arguments: releases)
    func records(release: String) throws {
        let corpus = try #require(Fixtures.corpus)
        let ours = DXFGroups.records(text: try Self.text(of: "sample_\(release)", in: corpus))
        let theirs = try DXFGroups.records(in: Self.dxf(release, in: corpus))
        let result = AttributeOracle.compare(ours: ours, theirs: theirs)
        #expect(result.compared == ["ATTRIB": 4, "ATTDEF": 5, "SEQEND": 2], "\(release)")
        #expect(result.mismatches.isEmpty, "\(release) \(result.mismatches)")
        #expect(result.oursOnly.isEmpty && result.dxfOnly.isEmpty, "\(release) \(result)")
    }

    @Test(
        "the attributes follow their INSERT, the definitions stay in their block, none twice",
        .enabled(if: Fixtures.corpus != nil), arguments: releases)
    func placement(release: String) throws {
        let corpus = try #require(Fixtures.corpus)
        let ours = DXFGroups.sequence(text: try Self.text(of: "sample_\(release)", in: corpus))
        let theirs = try DXFGroups.sequence(in: Self.dxf(release, in: corpus))

        let inserts = AttributeOracle.runs(ours)
        #expect(inserts == AttributeOracle.runs(theirs), "\(release)")
        #expect(inserts == [0x704: [0x705, 0x706], 0x79C: [0x79D, 0x79F, 0x7A0, 0x79E]])
        let definitions = AttributeOracle.definitions(ours)
        #expect(definitions == AttributeOracle.definitions(theirs), "\(release)")
        #expect(
            definitions == ["MYBLOCK": [0x6F8], "MY_BLOCK_V2": [0x796, 0x797, 0x798, 0x799]],
            "\(release) \(definitions)")

        // Every record is accounted for by the runs and the block: none is written a second time
        // or outside them.
        #expect(AttributeOracle.count("ATTRIB", in: ours) == 4, "\(release)")
        #expect(AttributeOracle.count("ATTDEF", in: ours) == 5, "\(release)")
        #expect(AttributeOracle.count("ATTRIB", in: theirs) == 4, "\(release)")
        #expect(AttributeOracle.count("ATTDEF", in: theirs) == 5, "\(release)")
        let attributes = ours.filter { $0.record.type == "ATTRIB" }.compactMap(\.record.handle)
        #expect(Set(attributes).count == attributes.count, "\(release)")
        #expect(ours.filter { $0.record.type == "ATTRIB" }.allSatisfy { $0.section == "ENTITIES" })
        #expect(ours.filter { $0.record.type == "ATTDEF" }.allSatisfy { $0.section == "BLOCKS" })
    }

    @Test(
        "R2018 writes the text a multi-line attribute and definition embed, as AutoCAD does",
        .enabled(if: Fixtures.corpus != nil))
    func multiLine() throws {
        let corpus = try #require(Fixtures.corpus)
        let ours = DXFGroups.records(text: try Self.text(of: "sample_AC1032", in: corpus))
        let attribute = try #require(ours[0x79D])
        #expect(attribute.all(101) == ["Embedded Object"])
        #expect(attribute.first(71) == "2")
        let embedded = attribute.groups.drop { $0.code != 101 }.filter { $0.code == 1 }
        #expect(embedded.map(\.value) == ["my multi line text for the attrrib"])
        let definition = try #require(ours[0x796])
        #expect(definition.all(101) == ["Embedded Object"] && definition.all(71).contains("4"))
        // The releases before R2018 have no embedded text, and give the text as the value.
        let before = DXFGroups.records(text: try Self.text(of: "sample_AC1027", in: corpus))
        #expect(before[0x79D]?.all(101) == [])
    }

    @Test(
        "the R14 sample has the attributes the R2000 DXF has, by handle",
        .enabled(if: Fixtures.corpus != nil))
    func r14() throws {
        let corpus = try #require(Fixtures.corpus)
        // There is no DXF of the R14 file, and the two saves keep the handles of the drawing
        // they came from, so the R14 file is compared with the R2000 export. R14 stores no line
        // weight and always an alignment point, so those two groups and the layer's case are
        // not compared, and the other fields are.
        let text = try Self.text(of: "sample_AC1014", in: corpus)
        let ours = DXFGroups.records(text: text)
        let theirs = try DXFGroups.records(in: Self.dxf("AC1015", in: corpus))

        var compared = 0
        for (handle, expected) in theirs where AttributeOracle.isCovered(expected, in: theirs) {
            guard let actual = ours[handle], actual.type == expected.type else {
                Issue.record(
                    "\(expected.type) \(AttributeOracle.hex(handle)) is not in the R14 text")
                continue
            }
            compared += 1
            let label = "\(expected.type) \(AttributeOracle.hex(handle))"
            let kept = [1, 2, 3, 8, 10, 20, 30, 40, 70, 74]
            for code in kept {
                let a = actual.first(code)
                let b = expected.first(code)
                if code == 8 {
                    #expect(a?.uppercased() == b?.uppercased(), "\(label) group 8")
                } else if let a, let b {
                    #expect(AttributeOracle.same(a, b), "\(label) group \(code): \(a) is not \(b)")
                } else {
                    #expect(a == b, "\(label) group \(code)")
                }
            }
            if expected.first(11) != nil {
                for code in [11, 21] {
                    let a = try #require(actual.first(code), "\(label) group \(code)")
                    #expect(AttributeOracle.same(a, expected.first(code) ?? ""), "\(label) \(code)")
                }
            }
        }
        #expect(compared == 11)

        let sequence = DXFGroups.sequence(text: text)
        let reference = try DXFGroups.sequence(in: Self.dxf("AC1015", in: corpus))
        #expect(AttributeOracle.runs(sequence) == AttributeOracle.runs(reference))
        #expect(AttributeOracle.definitions(sequence) == AttributeOracle.definitions(reference))
        #expect(AttributeOracle.count("ATTRIB", in: sequence) == 4)
        #expect(AttributeOracle.count("ATTDEF", in: sequence) == 5)
    }

    // MARK: Damage

    /// The sample's store, a copy of it with the objects of these handles taken out of the file's
    /// map, and a copy where each has a damaged layer handle, which the links before it survive.
    private static func damaged(_ name: String, _ handles: [UInt64], in corpus: URL) throws -> (
        whole: ObjectStore, removed: ObjectStore, corrupted: ObjectStore
    ) {
        let bytes = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
        let whole = try ObjectStore(try Container(bytes))
        var objects = whole.objects
        for handle in handles {
            var reader = try #require(try whole.reader(for: handle))
            _ = try reader.readEntityCommonThroughLinks()
            // The layer's handle follows the links. A code that does not exist makes the whole
            // common data unreadable.
            let position = reader.handles.position
            for bit in position..<(position + 8) { objects[bit >> 3] |= 0x80 >> UInt8(bit & 7) }
        }
        let corrupted = ObjectStore(
            container: whole.container, classes: whole.classes, map: whole.map, objects: objects,
            textEncoding: whole.textEncoding)
        return (whole, DamagedFileTests.remove(handles, from: whole), corrupted)
    }

    private static func text(of store: ObjectStore) throws -> String {
        var emitter = DXFEmitter(try Document(store: store))
        return emitter.text()
    }

    @Test(
        "an attribute that cannot be read is counted, and the others and the INSERT are kept",
        .enabled(if: Fixtures.corpus != nil), arguments: ["sample_AC1015", "sample_AC1032"])
    func lostAttribute(name: String) throws {
        let corpus = try #require(Fixtures.corpus)
        // The middle one of the three the second INSERT owns: in R2000 the others are found by
        // walking to it and past it.
        let stores = try Self.damaged(name, [0x79F], in: corpus)
        let intact = DXFGroups.sequence(text: try Self.text(of: stores.whole))

        for (label, store) in [("removed", stores.removed), ("damaged", stores.corrupted)] {
            let text = DXFGroups.sequence(text: try Self.text(of: store))
            #expect(AttributeOracle.count("UNREADABLE_ATTRIB", in: text) == 1, "\(name) \(label)")
            #expect(AttributeOracle.count("ATTRIB", in: text) == 3, "\(name) \(label)")
            #expect(
                AttributeOracle.count("INSERT", in: text)
                    == AttributeOracle.count("INSERT", in: intact),
                "\(name) \(label)")
            #expect(AttributeOracle.count("ATTDEF", in: text) == 5, "\(name) \(label)")
            // The insert still ends its attributes, and each of the other two is still its own.
            let runs = AttributeOracle.runs(text)
            #expect(runs[0x79C] == [0x79D, 0x7A0, 0x79E], "\(name) \(label) \(runs)")
            #expect(runs[0x704] == [0x705, 0x706], "\(name) \(label)")
            let lost = text.first { $0.record.type == "UNREADABLE_ATTRIB" }
            #expect(lost?.record.handle == 0x79F, "\(name) \(label)")
        }
    }

    @Test(
        "a definition that cannot be read is counted by what it is",
        .enabled(if: Fixtures.corpus != nil), arguments: ["sample_AC1015", "sample_AC1032"])
    func lostDefinition(name: String) throws {
        let corpus = try #require(Fixtures.corpus)
        let stores = try Self.damaged(name, [0x797], in: corpus)

        let cut = DXFGroups.sequence(text: try Self.text(of: stores.corrupted))
        #expect(AttributeOracle.count("UNREADABLE_ATTDEF", in: cut) == 1, "\(name)")
        #expect(AttributeOracle.count("ATTDEF", in: cut) == 4, "\(name)")
        #expect(AttributeOracle.count("ATTRIB", in: cut) == 4, "\(name)")

        // One the file does not hold has no type to name.
        let removed = DXFGroups.sequence(text: try Self.text(of: stores.removed))
        #expect(AttributeOracle.count("UNREADABLE_OBJECT", in: removed) == 1, "\(name)")
        #expect(AttributeOracle.count("ATTDEF", in: removed) == 4, "\(name)")
    }
}
