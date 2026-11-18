import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// Lightweight polylines and hatches in R14 files, which keep them as classes.
///
/// From R2000 the two types have fixed codes. An R14 file defines a class for each instead, and
/// their objects carry the class's number, so the class's DXF name says what they are. The R14
/// sample has no DXF export of its own, but it is the same drawing as the R2000 sample and its
/// lightweight polylines and hatches keep the R2000 handles, so they are compared with AutoCAD's
/// R2000 DXF by handle.
@Suite("R14 entities kept as classes")
struct ClassEntityTests {
    static func entityClass(
        _ number: Int, _ dxfName: String, _ cppName: String, itemClassID: Int = 0x1F2
    ) -> DWGClass {
        DWGClass(
            number: number, proxyFlags: 0, applicationName: "AutoCAD 2000", cppClassName: cppName,
            dxfName: dxfName, wasZombie: false, itemClassID: itemClassID, instanceCount: 0)
    }

    /// Classes as an R14 file defines them, with the numbers and names of a real one.
    static let classes: [Int: DWGClass] = [
        500: entityClass(500, "DICTIONARYVAR", "AcDbDictionaryVar", itemClassID: 0x1F3),
        501: entityClass(501, "LWPOLYLINE", "AcDbPolyline"),
        502: entityClass(502, "HATCH", "AcDbHatch"),
        530: entityClass(530, "IMAGE", "AcDbRasterImage"),
    ]

    @Test("a class named LWPOLYLINE or HATCH is read as the fixed type, any other type as itself")
    func fixedCodes() {
        #expect(ObjectType.fixedCode(of: 501, classes: Self.classes) == ObjectType.lwpolyline)
        #expect(ObjectType.fixedCode(of: 502, classes: Self.classes) == ObjectType.hatch)
        // ACadSharp also takes LWPLINE as the name of the polyline class.
        let alias = [600: Self.entityClass(600, "LWPLINE", "AcDbPolyline")]
        #expect(ObjectType.fixedCode(of: 600, classes: alias) == ObjectType.lwpolyline)
        // Another class, a number the file defines no class for, and a fixed code are kept.
        #expect(ObjectType.fixedCode(of: 500, classes: Self.classes) == 500)
        #expect(ObjectType.fixedCode(of: 530, classes: Self.classes) == 530)
        #expect(ObjectType.fixedCode(of: 777, classes: Self.classes) == 777)
        #expect(ObjectType.fixedCode(of: ObjectType.line, classes: Self.classes) == ObjectType.line)
    }

    // MARK: Objects built by hand

    static func read(_ object: CurveObject, classes: [Int: DWGClass]) throws -> DecodedEntity? {
        var reader = try ObjectReader(
            objects: object.bytes(), offset: 0, version: object.version,
            textEncoding: .windowsCP1252, classes: classes)
        return try reader.readEntity()
    }

    /// An R14 lightweight polyline of class 501: closed, with three points and their bulges.
    static func polyline() -> CurveObject {
        var o = CurveObject(.ac1014, type: 501)
        o.main.bitShort(0x200 | 0x10)  // closed, with bulges
        o.main.bitLong(3)  // points
        o.main.bitLong(3)  // bulges
        for (x, y) in [(1.0, 2.0), (3.0, 4.0), (3.0, 9.0)] {
            o.main.rawDouble(x)
            o.main.rawDouble(y)
        }
        for bulge in [0.5, 0.0, -1.0] { o.main.bitDouble(bulge) }
        return o
    }

    /// An R14 hatch of class 502: one closed polyline path made from one object, one pattern
    /// line, and a seed point.
    static func hatch() -> CurveObject {
        var o = CurveObject(.ac1014, type: 502)
        o.main.bitDouble(2.5)  // elevation
        o.main.point(DXF.Point(0, 0, 1))  // extrusion
        let name = Array("ANSI37".utf8)
        o.main.bitShort(name.count)
        for character in name { o.main.byte(Int(character)) }
        o.main.bit(false)  // not solid
        o.main.bit(true)  // associative
        o.main.bitLong(1)  // one path
        o.main.bitLong(7)  // external, a polyline, derived
        o.main.bit(false)  // no bulges
        o.main.bit(true)  // closed
        o.main.bitLong(3)
        for (x, y) in [(0.0, 0.0), (4.0, 0.0), (4.0, 3.0)] {
            o.main.rawDouble(x)
            o.main.rawDouble(y)
        }
        o.main.bitLong(1)  // one source object
        o.handles.handle(0x2A0)
        o.main.bitShort(0)  // style
        o.main.bitShort(1)  // a predefined pattern
        o.main.bitDouble(0)  // pattern angle
        o.main.bitDouble(200)  // pattern scale
        o.main.bit(false)  // not double
        o.main.bitShort(1)  // one pattern line
        o.main.bitDouble(0.75)  // its angle
        o.main.bitDouble(1)  // its base point
        o.main.bitDouble(2)
        o.main.bitDouble(3)  // its offset
        o.main.bitDouble(4)
        o.main.bitShort(0)  // no dashes
        o.main.bitDouble(1.5)  // the pixel size, as the path is derived
        o.main.bitLong(1)  // one seed point
        o.main.rawDouble(0.5)
        o.main.rawDouble(0.5)
        return o
    }

    @Test("an R14 lightweight polyline of a class reads as one")
    func polylineOfAClass() throws {
        let entity = try Self.read(Self.polyline(), classes: Self.classes)
        guard let entity, case .lwpolyline(let polyline) = entity.geometry else {
            Issue.record("not read as a lightweight polyline")
            return
        }
        #expect(entity.common.layer == 0x10)
        #expect(polyline.isClosed)
        #expect(polyline.points == [DXF.Point2(1, 2), DXF.Point2(3, 4), DXF.Point2(3, 9)])
        #expect(polyline.bulges == [0.5, 0, -1])
        // Without the file's classes the number says nothing, and the object is not read.
        #expect(try Self.read(Self.polyline(), classes: [:]) == nil)
    }

    @Test("an R14 hatch of a class reads as one")
    func hatchOfAClass() throws {
        let entity = try Self.read(Self.hatch(), classes: Self.classes)
        guard let entity, case .hatch(let hatch) = entity.geometry else {
            Issue.record("not read as a hatch")
            return
        }
        #expect(entity.common.layer == 0x10)
        #expect(hatch.gradient == nil)
        #expect(hatch.elevation == 2.5 && hatch.patternName == "ANSI37")
        #expect(!hatch.isSolid && hatch.isAssociative)
        #expect(hatch.paths.count == 1)
        if let path = hatch.paths.first {
            #expect(path.flags == 7 && path.sourceBoundaries == [0x2A0])
            if case .polyline(let vertices, let isClosed, let hasBulges) = path.shape {
                #expect(isClosed && !hasBulges)
                #expect(
                    vertices.map(\.point) == [
                        DXF.Point2(0, 0), DXF.Point2(4, 0), DXF.Point2(4, 3),
                    ])
            } else {
                Issue.record("the path is not a polyline")
            }
        }
        #expect(hatch.patternType == 1 && hatch.patternScale == 200)
        #expect(hatch.patternLines.count == 1)
        if let line = hatch.patternLines.first {
            #expect(line.angle == 0.75 && line.dashLengths.isEmpty)
            #expect(line.basePoint == DXF.Point2(1, 2) && line.offset == DXF.Point2(3, 4))
        }
        #expect(hatch.pixelSize == 1.5)
        #expect(hatch.seedPoints == [DXF.Point2(0.5, 0.5)])
        #expect(try Self.read(Self.hatch(), classes: [:]) == nil)
    }

    // MARK: The R14 sample

    /// The R14 sample, and AutoCAD's DXF of the same drawing saved as R2000, or `nil` without
    /// `DWG_CORPUS`.
    static func sample() -> (dwg: URL, dxf: URL)? {
        guard let corpus = Fixtures.corpus else { return nil }
        return (
            corpus.appendingPathComponent("sample_AC1014.dwg"),
            corpus.appendingPathComponent("sample_AC1015_ascii.dxf")
        )
    }

    @Test("every lightweight polyline of the R14 sample equals AutoCAD's DXF of the drawing")
    func samplePolylines() throws {
        guard case (let dwg, let dxf)? = Self.sample() else { return }  // needs DWG_CORPUS
        let sample = try CurveOracle.sample(name: "sample_AC1014", dwg: dwg, dxf: dxf)
        let tally = try CurveOracle.tally(
            sample, dxfType: "LWPOLYLINE",
            pick: { geometry -> LWPolylineData? in
                if case .lwpolyline(let data) = geometry { return data }
                return nil
            },
            matches: { p, r in PolylinesTests.lwMatches(p, r) })
        #expect(tally.decoded == 23)
        #expect(tally.expected == 23)
        #expect(tally.mismatches.isEmpty, "\(tally.mismatches)")
    }

    @Test("every hatch of the R14 sample equals AutoCAD's DXF of the drawing")
    func sampleHatches() throws {
        guard case (let dwg, let dxf)? = Self.sample() else { return }  // needs DWG_CORPUS
        let store = try ObjectStore(try Container([UInt8](try Data(contentsOf: dwg))))
        let sample = AnnotationSample(
            name: "sample_AC1014", store: store, records: try DXFGroups.records(in: dxf))
        let result = try HatchOracle.compare(sample)
        #expect(result.compared == 8)
        #expect(result.mismatches.isEmpty, "\(result.mismatches)")
        #expect(result.dwgOnly.isEmpty && result.dxfOnly.isEmpty)
        #expect(result.shapes == ["line": 20, "polyline": 3], "\(result.shapes)")
    }

    @Test("DWG.read gives the R14 sample's lightweight polylines and hatches as AutoCAD's DXF does")
    func sampleDrawing() throws {
        guard case (let dwg, let dxf)? = Self.sample() else { return }  // needs DWG_CORPUS
        let data = try Data(contentsOf: dwg)
        let ours = DrawingOracle.entities(of: try DWG.read(data: data))
        let theirs = DrawingOracle.entities(of: try DXF.read(contentsOf: dxf))
        var compared: [String: Int] = [:]
        for (handle, record) in try DXFGroups.records(in: dxf)
        where record.type == "LWPOLYLINE" || record.type == "HATCH" {
            let key = String(handle, radix: 16, uppercase: true)
            guard let expected = theirs[key] else {
                Issue.record("SwiftDXF does not read the \(record.type) \(key) of the DXF")
                continue
            }
            #expect(ours[key] == expected, "\(record.type) \(key)")
            compared[record.type, default: 0] += 1
        }
        #expect(compared == ["LWPOLYLINE": 23, "HATCH": 8])

        // None of them is written without its layer.
        let written = DXFGroups.records(text: try DWG.dxfText(data: data)).values.filter {
            $0.type == "LWPOLYLINE" || $0.type == "HATCH"
        }
        #expect(written.count == 31)
        #expect(written.allSatisfy { $0.first(8) != nil })
    }

    @Test("an R14 lightweight polyline or hatch that cannot be read is counted as unreadable")
    func unreadable() throws {
        guard case (let dwg, _)? = Self.sample() else { return }  // needs DWG_CORPUS
        let whole = try ObjectStore(try Container([UInt8](try Data(contentsOf: dwg))))
        let intact = try Document(store: whole)
        let before = DamagedFileTests.entityCount(try DamagedFileTests.dxf(of: intact))

        // The first entity of each type, which in R14 carries the number of a class.
        func first(_ type: Int) throws -> UInt64 {
            try #require(
                intact.blocks.flatMap(\.entities).first {
                    (try? whole.reader(for: $0))?.type == type
                })
        }
        let lost = [try first(ObjectType.lwpolyline), try first(ObjectType.hatch)]
        var objects = whole.objects
        for handle in lost {
            let offset = try #require(whole.map[handle])
            let stored = try ObjectReader(
                objects: whole.objects, offset: offset, version: .ac1014,
                textEncoding: whole.textEncoding)
            #expect(stored.type >= ObjectType.firstClass)
            // An R14 object is not read within its stated size, so it is damaged instead: the
            // bytes after its size and its type, a class number of 18 bits, are overwritten.
            for index in (offset + 5)..<(offset + 25) { objects[index] = 0xFF }
        }
        let damaged = ObjectStore(
            container: whole.container, classes: whole.classes, map: whole.map, objects: objects,
            textEncoding: whole.textEncoding)
        for handle in lost {
            #expect(throws: (any Error).self) { _ = try damaged.entity(handle) }
        }
        let drawing = try DamagedFileTests.dxf(of: try Document(store: damaged))
        #expect(DamagedFileTests.skipped("UNREADABLE_LWPOLYLINE", in: drawing) == 1)
        #expect(DamagedFileTests.skipped("UNREADABLE_HATCH", in: drawing) == 1)
        #expect(DamagedFileTests.skipped("UNREADABLE_OBJECT", in: drawing) == 0)
        #expect(DamagedFileTests.entityCount(drawing) == before - 2)
    }

    // MARK: A real R14 drawing

    /// A railway vehicle drawing saved as R14, `FD-0123_ﾀ550形550-551.dwg`.
    ///
    /// It is not one of ACadSharp's samples and is not committed: the test runs when a copy of it
    /// is in the `DWG_CORPUS` folder. It has no DXF export, so the expected values are what
    /// acadrust 0.6.8 reads from it (through OCCTSwiftIO's `dwg2dxf`).
    @Test("a real R14 drawing's lightweight polylines and hatches are the ones acadrust reads")
    func railwayDrawing() throws {
        guard let corpus = Fixtures.corpus,
            let name = try FileManager.default.contentsOfDirectory(atPath: corpus.path).first(
                where: { $0.hasPrefix("FD-0123") && $0.hasSuffix(".dwg") })
        else { return }  // needs the drawing in DWG_CORPUS: skipped without it
        let text = try DWG.dxfText(data: try Data(contentsOf: corpus.appendingPathComponent(name)))
        let records = DXFGroups.records(text: text)
        func near(_ a: [String], _ b: [Double]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { EntityOracle.near(Double($0) ?? .nan, $1) }
        }

        let polylines = records.values.filter { $0.type == "LWPOLYLINE" }
        #expect(polylines.count == 14)
        #expect(polylines.allSatisfy { $0.first(8) != nil })
        #expect(polylines.reduce(0) { $0 + $1.all(10).count } == 80)
        #expect(polylines.filter { ($0.int(70) ?? 0) & 1 == 1 }.count == 4)
        let bulges = polylines.flatMap { $0.all(42).compactMap { Double($0) } }
        #expect(bulges.filter { $0 != 0 }.count == 16)
        #expect(EntityOracle.near(bulges.reduce(0, +), -6.627416997969511))
        if let first = records[0xCB01] {
            #expect(first.type == "LWPOLYLINE" && first.first(8) == "LINE-2B")
            #expect(near(first.all(10), [14547.702288173568, 14547.702288173568]))
            #expect(near(first.all(20), [3185.0787265390463, 3044.9586679602708]))
        } else {
            Issue.record("no record CB01")
        }

        let hatches = records.values.filter { $0.type == "HATCH" }
        #expect(hatches.count == 2)
        for hatch in hatches {
            #expect(hatch.first(8) == "LINE-1A" && hatch.first(2) == "ANSI37")
            // One path, of flags 7 (external, a polyline, derived), with six vertices.
            #expect(hatch.int(91) == 1 && hatch.int(92) == 7 && hatch.int(93) == 6)
        }
        if let first = records[0x113A8] {
            // The first vertex of the path follows the elevation point.
            #expect(near(Array(first.all(10).dropFirst().prefix(1)), [8299.994465637288]))
            #expect(near(Array(first.all(20).dropFirst().prefix(1)), [7989.961371177516]))
        } else {
            Issue.record("no record 113A8")
        }
    }
}
