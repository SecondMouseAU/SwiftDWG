import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// What differs between the WIPEOUT records of two DXF texts, which are compared by handle.
enum WipeoutOracle {
    struct Result {
        var compared = 0
        var vertices = 0
        var mismatches: [String] = []
        var oursOnly: [UInt64] = []
        var theirsOnly: [UInt64] = []
    }

    static func compare(
        ours: [UInt64: DXFRecord], theirs: [UInt64: DXFRecord], hasClipMode: Bool,
        caseInsensitiveNames: Bool = false
    ) -> Result {
        var result = Result()
        let expected = theirs.filter { $0.value.type == "WIPEOUT" }
        let written = ours.filter { $0.value.type == "WIPEOUT" }
        result.oursOnly = written.keys.filter { expected[$0] == nil }.sorted()
        for (handle, reference) in expected.sorted(by: { $0.key < $1.key }) {
            guard let record = written[handle] else {
                result.theirsOnly.append(handle)
                continue
            }
            result.compared += 1
            result.vertices += reference.all(14).count
            let name = String(handle, radix: 16, uppercase: true)
            for problem in mismatches(record, reference, hasClipMode, caseInsensitiveNames) {
                result.mismatches.append("\(name): \(problem)")
            }
        }
        return result
    }

    /// The groups of a wipeout: layer, class version, the corner and the vectors, the size, the
    /// references to the image definition, the display values and the clip boundary.
    static func mismatches(
        _ record: DXFRecord, _ reference: DXFRecord, _ hasClipMode: Bool,
        _ caseInsensitiveNames: Bool
    ) -> [String] {
        var bad: [String] = []
        func text(_ code: Int) {
            var a = record.first(code)
            var b = reference.first(code)
            if caseInsensitiveNames, code == 8 {
                a = a?.uppercased()
                b = b?.uppercased()
            }
            if a != b { bad.append("\(code): \(a ?? "none") is not \(b ?? "none")") }
        }
        func numbers(_ code: Int) {
            let a = record.all(code).compactMap { Double($0) }
            let b = reference.all(code).compactMap { Double($0) }
            let ok = a.count == b.count && zip(a, b).allSatisfy { EntityOracle.near($0, $1) }
            if !ok { bad.append("\(code): \(a) is not \(b)") }
        }
        text(8)
        for code in [90, 340, 70, 280, 281, 282, 283, 360, 71, 91] { text(code) }
        for code in [10, 20, 30, 11, 21, 31, 12, 22, 32, 13, 23, 14, 24] { numbers(code) }
        if hasClipMode { text(290) } else if record.first(290) != nil { bad.append("290 is there") }
        // The groups from the class version on, in AutoCAD's order.
        let order = [90, 10, 20, 30, 11, 21, 31, 12, 22, 32, 13, 23, 340, 70, 280, 281, 282, 283]
        let from = order + [290, 360, 71, 91, 14, 24]
        func sequence(_ r: DXFRecord) -> [Int] {
            r.groups.map(\.code).filter { from.contains($0) }
        }
        if sequence(record) != sequence(reference) {
            bad.append("groups \(sequence(record)) are not \(sequence(reference))")
        }
        return bad
    }
}

@Suite("WIPEOUT")
struct WipeoutTests {
    static let releases: [DWG.Version] = [
        .ac1012, .ac1014, .ac1015, .ac1018, .ac1021, .ac1024, .ac1027, .ac1032,
    ]

    /// The class number a WIPEOUT has in the files built here.
    static let number = 520

    /// Classes as a file defines them, with one for the wipeout and one for the image.
    static let classes: [Int: DWGClass] = [
        ClassEntityTests.entityClass(number, "WIPEOUT", "AcDbWipeout"),
        ClassEntityTests.entityClass(521, "IMAGE", "AcDbRasterImage"),
    ].reduce(into: [:]) { $0[$1.number] = $1 }

    // MARK: Objects built by hand

    /// A wipeout with every field set to something that is not the default.
    static func object(
        _ version: DWG.Version, clipType: Int = 2, type: Int = Self.number
    ) -> SyntheticObject {
        var object = SyntheticObject(version: version, type: type)
        object.main.bitLong(0)  // the class version
        object.main.point(271.5, 3.25, 2)  // the corner
        object.main.point(31.5, 0, 0)  // the vector of a pixel along the bottom
        object.main.point(0, 31.5, 0)  // the vector of a pixel along the left side
        object.main.rawDouble(640)  // the size in pixels
        object.main.rawDouble(480)
        object.main.bitShort(7)  // display flags
        object.main.bit(true)  // clipping is on
        object.main.byte(60)  // brightness
        object.main.byte(40)  // contrast
        object.main.byte(10)  // fade
        if version >= .ac1024 { object.main.bit(true) }  // the area inside is kept
        object.main.bitShort(Int16(clipType))
        let corners = [(-0.5, 0.5), (0.25, 0.5), (0.25, -0.25), (-0.5, -0.5)]
        switch clipType {
        case 1:
            for corner in corners.prefix(2) {
                object.main.rawDouble(corner.0)
                object.main.rawDouble(corner.1)
            }
        case 2:
            object.main.bitLong(Int32(corners.count))
            for corner in corners {
                object.main.rawDouble(corner.0)
                object.main.rawDouble(corner.1)
            }
        default: break
        }
        object.handles.handle(0)  // the image definition, which a wipeout has none of
        object.handles.handle(0x2F)  // its reactor, which is here only to be read back
        return object
    }

    static func decode(
        _ object: SyntheticObject, classes: [Int: DWGClass] = Self.classes
    ) throws -> (EntityCommon, WipeoutData)? {
        var reader = try ObjectReader(
            objects: object.bytes(), offset: 0, version: object.version,
            textEncoding: .windowsCP1252, classes: classes)
        guard let entity = try reader.readEntity(), case .wipeout(let data) = entity.geometry
        else { return nil }
        return (entity.common, data)
    }

    @Test("a wipeout of a class reads back from every release")
    func handBuilt() throws {
        for version in Self.releases {
            let found = try Self.decode(Self.object(version))
            let (common, wipeout) = try #require(found, "\(version)")
            #expect(common.layer == 0x10 && common.handle == 0x1000, "\(version)")
            #expect(wipeout.classVersion == 0, "\(version)")
            #expect(wipeout.insertion == DXF.Point(271.5, 3.25, 2), "\(version)")
            #expect(wipeout.uVector == DXF.Point(31.5, 0, 0), "\(version)")
            #expect(wipeout.vVector == DXF.Point(0, 31.5, 0), "\(version)")
            #expect(wipeout.size == DXF.Point2(640, 480), "\(version)")
            #expect(wipeout.displayFlags == 7 && wipeout.isClipping, "\(version)")
            #expect(wipeout.brightness == 60 && wipeout.contrast == 40, "\(version)")
            #expect(wipeout.fade == 10, "\(version)")
            // The clip mode is kept from R2010.
            #expect(wipeout.clipsInside == (version >= .ac1024 ? true : nil), "\(version)")
            #expect(wipeout.clipType == 2, "\(version)")
            #expect(
                wipeout.clipVertices == [
                    DXF.Point2(-0.5, 0.5), DXF.Point2(0.25, 0.5), DXF.Point2(0.25, -0.25),
                    DXF.Point2(-0.5, -0.5),
                ], "\(version)")
            #expect(wipeout.imageDefinition == 0 && wipeout.imageReactor == 0x2F, "\(version)")
        }
    }

    @Test("a rectangular clip boundary is two opposite corners")
    func rectangle() throws {
        for version in Self.releases {
            let found = try Self.decode(Self.object(version, clipType: 1))
            let (_, wipeout) = try #require(found, "\(version)")
            #expect(wipeout.clipType == 1, "\(version)")
            #expect(
                wipeout.clipVertices == [DXF.Point2(-0.5, 0.5), DXF.Point2(0.25, 0.5)],
                "\(version)")
        }
    }

    @Test("a clip boundary of a kind the format does not define has no vertices")
    func unknownClipType() throws {
        let found = try Self.decode(Self.object(.ac1015, clipType: 9))
        let (_, wipeout) = try #require(found)
        #expect(wipeout.clipType == 9 && wipeout.clipVertices.isEmpty)
    }

    @Test("an object is a wipeout only through a class of that name")
    func classRouting() throws {
        #expect(ObjectType.fixedCode(of: Self.number, classes: Self.classes) == ObjectType.wipeout)
        // The image class, a class the file does not define, and no classes at all.
        #expect(ObjectType.fixedCode(of: 521, classes: Self.classes) == 521)
        #expect(ObjectType.fixedCode(of: 777, classes: Self.classes) == 777)
        #expect(ObjectType.fixedCode(of: Self.number, classes: [:]) == Self.number)
        #expect(try Self.decode(Self.object(.ac1015), classes: [:]) == nil)
        #expect(try Self.decode(Self.object(.ac1032), classes: [:]) == nil)
        #expect(try Self.decode(Self.object(.ac1015, type: 521)) == nil)
    }

    @Test("a wipeout is decoded, so it is named as an entity and not as one that is skipped")
    func names() {
        #expect(ObjectType.decodedTypeName(ObjectType.wipeout) == "WIPEOUT")
        #expect(ObjectType.typeName(ObjectType.wipeout, classes: [:]) == nil)
        #expect(ObjectType.isEntity(ObjectType.wipeout, classes: [:]))
        // No file can hold the code of its own, which is more than a type is stored in.
        #expect(ObjectType.wipeout > Int(UInt16.max))
    }

    @Test("a count of clip vertices the object cannot hold is refused")
    func hugeCount() {
        for version in [DWG.Version.ac1015, .ac1032] {
            var object = SyntheticObject(version: version, type: Self.number)
            object.main.bitLong(0)
            object.main.point(0, 0, 0)
            object.main.point(1, 0, 0)
            object.main.point(0, 1, 0)
            object.main.rawDouble(1)
            object.main.rawDouble(1)
            object.main.bitShort(0)
            object.main.bit(false)
            for _ in 0..<3 { object.main.byte(0) }
            if version >= .ac1024 { object.main.bit(false) }
            object.main.bitShort(2)
            object.main.bitLong(1_000_000)
            object.handles.handle(0)
            object.handles.handle(0)
            #expect(throws: DWG.Error.self) { _ = try Self.decode(object) }
        }
    }

    @Test("a wipeout cut at any byte is refused until it is whole")
    func truncated() {
        for version in Self.releases {
            for clipType in [1, 2] {
                DamagedObjectTests.checkTruncation(
                    Self.object(version, clipType: clipType).bytes(), version,
                    "wipeout \(version) clip \(clipType)", classes: Self.classes)
            }
        }
    }

    // MARK: The DXF text

    /// The text the emitter writes for this wipeout, as a record.
    static func record(_ wipeout: WipeoutData) throws -> DXFRecord {
        let store = try ObjectStore(try Container(try Fixtures.data("BLOCKPOINTPARAMETER.dwg")))
        var emitter = DXFEmitter(try Document(store: store))
        emitter.write(
            DecodedEntity(common: EntityCommon(handle: 0x99), geometry: .wipeout(wipeout)),
            space: .model)
        return try #require(DXFGroups.records(text: emitter.writer.text)[0x99])
    }

    @Test("the groups are written in AutoCAD's order, and a polygon is closed and counted so")
    func polygonGroups() throws {
        let found = try #require(try Self.decode(Self.object(.ac1032)))
        let record = try Self.record(found.1)
        #expect(record.type == "WIPEOUT")
        // The line weight (370) is left out: a hand-made entity has it set to 0, not to the layer's.
        #expect(
            record.groups.map(\.code).filter { $0 != 370 } == [
                5, 8, 90, 10, 20, 30, 11, 21, 31, 12, 22, 32, 13, 23, 340, 70, 280, 281, 282, 283,
                290, 360, 71, 91,
            ] + Array(repeating: [14, 24], count: 5).flatMap { $0 })
        #expect(record.int(91) == 5 && record.int(71) == 2)
        #expect(record.first(340) == "0" && record.first(360) == "2F")
        #expect(record.int(290) == 1 && record.int(280) == 1)
        // The first vertex comes again as the fifth.
        #expect(record.all(14) == ["-0.5", "0.25", "0.25", "-0.5", "-0.5"])
        #expect(record.all(24) == ["0.5", "0.5", "-0.25", "-0.5", "0.5"])
    }

    @Test("a rectangle is written as its two corners, and no clip mode before R2010")
    func rectangleGroups() throws {
        let found = try #require(try Self.decode(Self.object(.ac1015, clipType: 1)))
        let record = try Self.record(found.1)
        #expect(record.int(71) == 1 && record.int(91) == 2)
        #expect(record.all(14) == ["-0.5", "0.25"] && record.all(24) == ["0.5", "0.5"])
        #expect(record.first(290) == nil)
    }

    // MARK: AutoCAD's DXF

    @Test("the wipeout of every AutoCAD sample from R2000 to R2018 equals its DXF record")
    func corpus() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        for name in Fixtures.corpusNamesOther + Fixtures.corpusNames {
            let data = try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg"))
            let ours = DXFGroups.records(text: try DWG.dxfText(data: data))
            let theirs = try DXFGroups.records(
                in: corpus.appendingPathComponent("\(name)_ascii.dxf"))
            let version = try #require(DWG.version(of: data))
            let result = WipeoutOracle.compare(
                ours: ours, theirs: theirs, hasClipMode: version >= .ac1024)
            #expect(result.compared == 1, "\(name)")
            #expect(result.vertices == 5, "\(name)")
            #expect(result.mismatches.isEmpty, "\(name) \(result.mismatches)")
            #expect(result.oursOnly.isEmpty && result.theirsOnly.isEmpty, "\(name)")
        }
    }

    @Test("the wipeout of the R14 sample equals the R2000 DXF's, which keeps its handle")
    func corpusR14() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS
        // There is no DXF of the R14 file, but it is the same drawing as the R2000 one.
        let data = try Data(contentsOf: corpus.appendingPathComponent("sample_AC1014.dwg"))
        let ours = DXFGroups.records(text: try DWG.dxfText(data: data))
        let theirs = try DXFGroups.records(
            in: corpus.appendingPathComponent("sample_AC1015_ascii.dxf"))
        let result = WipeoutOracle.compare(
            ours: ours, theirs: theirs, hasClipMode: false, caseInsensitiveNames: true)
        #expect(result.compared == 1)
        #expect(result.mismatches.isEmpty, "\(result.mismatches)")
        #expect(result.oursOnly.isEmpty && result.theirsOnly.isEmpty)
    }
}
