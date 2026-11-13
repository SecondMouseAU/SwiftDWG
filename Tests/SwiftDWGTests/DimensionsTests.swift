import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// A drawing read from a DWG and the raw groups of AutoCAD's own DXF export of it, by handle.
///
/// The decoders of dimensions, leaders and hatches are compared with these groups, so nothing is
/// checked against SwiftDWG's own output.
struct AnnotationSample {
    var name: String
    var store: ObjectStore
    var records: [UInt64: DXFRecord]

    /// The committed fixture, and the AutoCAD samples of `DWG_CORPUS` when it is set.
    static func all() throws -> [AnnotationSample] {
        var out: [AnnotationSample] = []
        out.append(
            try load(
                "BLOCKPOINTPARAMETER", dwg: Fixtures.directory, dxf: Fixtures.directory,
                dxfName: "BLOCKPOINTPARAMETER.dxf"))
        out.append(contentsOf: try corpus())
        return out
    }

    /// The AutoCAD samples of `DWG_CORPUS`, or none without it.
    static func corpus() throws -> [AnnotationSample] {
        guard let corpus = Fixtures.corpus else { return [] }
        return try Fixtures.corpusNames.map {
            try load($0, dwg: corpus, dxf: corpus, dxfName: "\($0)_ascii.dxf")
        }
    }

    private static func load(
        _ name: String, dwg: URL, dxf: URL, dxfName: String
    ) throws -> AnnotationSample {
        let bytes = [UInt8](try Data(contentsOf: dwg.appendingPathComponent("\(name).dwg")))
        let store = try ObjectStore(try Container(bytes))
        let records = try DXFGroups.records(in: dxf.appendingPathComponent(dxfName))
        return AnnotationSample(name: name, store: store, records: records)
    }

    /// The handles of the objects with one of these type codes, in order.
    func handles(ofTypes types: Set<Int>) throws -> [UInt64] {
        try store.handles.filter {
            guard let reader = try store.reader(for: $0) else { return false }
            return types.contains(reader.type)
        }
    }

    /// The DXF records of this type, by handle.
    func records(ofType type: String) -> [UInt64: DXFRecord] {
        records.filter { $0.value.type == type }
    }
}

enum DimensionOracle {
    static let objectTypes: Set<Int> = [
        ObjectType.dimensionOrdinate, ObjectType.dimensionLinear, ObjectType.dimensionAligned,
        ObjectType.dimensionAngular3Point, ObjectType.dimensionAngular2Line,
        ObjectType.dimensionRadius, ObjectType.dimensionDiameter,
    ]

    /// The DXF subclass marker that ends a dimension record, for each kind.
    static func marker(of kind: DimensionKind) -> String {
        switch kind {
        case .linear: return "AcDbRotatedDimension"
        case .aligned: return "AcDbAlignedDimension"
        case .angular3Point: return "AcDb3PointAngularDimension"
        case .angular2Line: return "AcDb2LineAngularDimension"
        case .radius: return "AcDbRadialDimension"
        case .diameter: return "AcDbDiametricDimension"
        case .ordinate: return "AcDbOrdinateDimension"
        }
    }

    struct Result {
        var compared = 0
        var mismatches: [String] = []
        /// How many dimensions of each DXF subclass the DWG has, and the DXF.
        var decodedCounts: [String: Int] = [:]
        var dxfCounts: [String: Int] = [:]
        var dwgOnly: [UInt64] = []
        var dxfOnly: [UInt64] = []
    }

    static func near(_ a: Double, _ b: Double) -> Bool { EntityOracle.near(a, b) }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    static func compare(_ sample: AnnotationSample) throws -> Result {
        var result = Result()
        let dxf = sample.records(ofType: "DIMENSION")
        for record in dxf.values {
            let marker = record.all(100).last ?? "?"
            result.dxfCounts[marker, default: 0] += 1
        }

        var seen = Set<UInt64>()
        for handle in try sample.handles(ofTypes: objectTypes) {
            var reader = try #require(try sample.store.reader(for: handle))
            let entity = try reader.readDimension()
            guard case .dimension(let data) = entity.geometry else {
                result.mismatches.append("\(handle): not a dimension")
                continue
            }
            result.decodedCounts[marker(of: data.kind), default: 0] += 1
            seen.insert(handle)
            guard let record = dxf[handle] else {
                result.dwgOnly.append(handle)
                continue
            }
            result.compared += 1
            let bad = mismatches(of: data, entity.common, against: record, in: sample)
            let name = String(handle, radix: 16, uppercase: true)
            result.mismatches.append(
                contentsOf: bad.map { "\(sample.name) \(name) \(data.kind): \($0)" })
        }
        result.dxfOnly = dxf.keys.filter { !seen.contains($0) }
        return result
    }

    /// What differs between a decoded dimension and its DXF record.
    static func mismatches(
        of data: DimensionData, _ common: EntityCommon, against record: DXFRecord,
        in sample: AnnotationSample
    ) -> [String] {
        var bad: [String] = []
        func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
            if !ok { bad.append(what()) }
        }
        func point(_ x: Int, _ y: Int, _ z: Int) -> DXF.Point? {
            record.point(x, y, z).map { DXF.Point($0.x, $0.y, $0.z) }
        }
        /// A decoded point against a DXF one; a point that kind does not have must be absent.
        func expectPoint(_ decoded: DXF.Point?, _ codes: (Int, Int, Int), _ what: String) {
            let reference = point(codes.0, codes.1, codes.2)
            switch (decoded, reference) {
            case (nil, nil): break
            case (let a?, let b?): expect(EntityOracle.near(a, b), "\(what) \(a) vs \(b)")
            default: bad.append("\(what) present in one only: \(String(describing: decoded))")
            }
        }
        /// An angle that the DXF writes in degrees, and leaves out when it is 0.
        func expectAngle(_ radians: Double, _ code: Int, _ what: String) {
            expect(
                near(degrees(radians), record.double(code) ?? 0),
                "\(what) \(degrees(radians)) vs \(String(describing: record.double(code)))")
        }

        expect(
            data.typeFlags == record.int(70),
            "70: \(data.typeFlags) vs \(String(describing: record.int(70)))")
        expect(
            marker(of: data.kind) == record.all(100).last,
            "kind \(data.kind) is not \(String(describing: record.all(100).last))")
        expectPoint(data.definitionPoint, (10, 20, 30), "10")
        expectPoint(data.textMidPoint, (11, 21, 31), "11")
        expectPoint(data.firstPoint, (13, 23, 33), "13")
        expectPoint(data.secondPoint, (14, 24, 34), "14")
        expectPoint(data.vertexPoint, (15, 25, 35), "15")
        expectPoint(data.arcPoint, (16, 26, 36), "16")
        if record.first(12) != nil {
            expectPoint(data.insertionPoint, (12, 22, 32), "12")
        } else {
            // AutoCAD leaves the clone insertion point out when it is the origin.
            expect(data.insertionPoint.x == 0 && data.insertionPoint.y == 0, "12 is not the origin")
        }

        expect(data.text == (record.first(1) ?? ""), "1: \(data.text)")
        expectAngle(data.textRotation, 53, "53")
        if let horizontal = record.double(51) {
            expect(near(degrees(data.horizontalDirection), horizontal), "51")
        } else {
            expect(data.horizontalDirection == 0, "51 is \(data.horizontalDirection), not absent")
        }
        if data.kind == .linear {
            expectAngle(data.rotation ?? .nan, 50, "50")
        } else {
            expect(data.rotation == nil && record.first(50) == nil, "50 on a kind without it")
        }
        if data.kind == .linear || data.kind == .aligned {
            expectAngle(data.extLineRotation ?? .nan, 52, "52")
        } else {
            expect(
                data.extLineRotation == nil && record.first(52) == nil, "52 on a kind without it")
        }
        if data.kind == .radius || data.kind == .diameter {
            expect(near(data.leaderLength ?? .nan, record.double(40) ?? 0), "40 leader length")
        } else {
            expect(data.leaderLength == nil && record.first(40) == nil, "40 on a kind without it")
        }

        // 42 is the measurement, which the DXF may leave out or write as a negative number.
        if let measurement = record.double(42), measurement > 0 {
            expect(
                near(data.measurement ?? .nan, measurement),
                "42: \(String(describing: data.measurement)) vs \(measurement)")
        }
        expect(
            data.attachmentPoint == record.int(71),
            "71: \(String(describing: data.attachmentPoint))")
        if let style = record.int(72) {
            expect(
                data.lineSpacingStyle == style, "72: \(String(describing: data.lineSpacingStyle))")
        }
        if let factor = record.double(41) {
            expect(near(data.lineSpacingFactor ?? .nan, factor), "41")
        }
        expect(data.flipArrow1 == ((record.int(74) ?? 0) != 0), "74")
        expect(data.flipArrow2 == ((record.int(75) ?? 0) != 0), "75")
        expect(
            EntityOracle.near(
                data.extrusion, point(210, 220, 230) ?? DXF.Point(0, 0, 1)), "210")

        // The style and the anonymous block, by the names the DXF gives the records they name.
        expect(
            sample.records[data.block]?.type == "BLOCK_RECORD"
                && sample.records[data.block]?.first(2) == record.first(2),
            "anonymous block \(data.block) is not \(String(describing: record.first(2)))")
        expect(
            sample.records[data.style]?.type == "DIMSTYLE"
                && sample.records[data.style]?.first(2) == record.first(3),
            "dimension style \(data.style) is not \(String(describing: record.first(3)))")
        return bad
    }
}

@Suite("Dimensions against AutoCAD's DXF")
struct DimensionsTests {
    @Test("the committed fixture holds no dimension, and the reader finds none")
    func fixtureHasNone() throws {
        let sample = try #require(try AnnotationSample.all().first)
        #expect(try sample.handles(ofTypes: DimensionOracle.objectTypes).isEmpty)
        #expect(sample.records(ofType: "DIMENSION").isEmpty)
    }

    @Test("every dimension of the AutoCAD samples from R2004 to R2018 equals its DXF record")
    func corpus() throws {
        let samples = try AnnotationSample.corpus()
        guard !samples.isEmpty else { return }  // needs DWG_CORPUS: skipped without it
        let expectedCounts = [
            "AcDbRotatedDimension": 3, "AcDbAlignedDimension": 2, "AcDb3PointAngularDimension": 1,
            "AcDb2LineAngularDimension": 1, "AcDbRadialDimension": 1, "AcDbDiametricDimension": 1,
            "AcDbOrdinateDimension": 2,
        ]
        for sample in samples {
            let result = try DimensionOracle.compare(sample)
            #expect(result.compared == 11, "\(sample.name)")
            #expect(result.mismatches.isEmpty, "\(result.mismatches)")
            #expect(result.dwgOnly.isEmpty && result.dxfOnly.isEmpty, "\(sample.name)")
            #expect(result.decodedCounts == result.dxfCounts, "\(sample.name)")
            #expect(result.decodedCounts == expectedCounts, "\(sample.name)")
        }
    }

    @Test("the two ordinate dimensions are of the X and the Y type, and the text can be moved")
    func flagBits() throws {
        let samples = try AnnotationSample.corpus()
        guard !samples.isEmpty else { return }
        for sample in samples {
            var ordinates: [Bool] = []
            var movedText = 0
            for handle in try sample.handles(ofTypes: DimensionOracle.objectTypes) {
                var reader = try #require(try sample.store.reader(for: handle))
                let entity = try reader.readDimension()
                guard case .dimension(let data) = entity.geometry else { continue }
                if data.kind == .ordinate { ordinates.append(data.isOrdinateTypeX) }
                if data.isTextUserDefinedLocation { movedText += 1 }
            }
            #expect(ordinates.sorted(by: { !$0 && $1 }) == [false, true], "\(sample.name)")
            #expect(movedText == 1, "\(sample.name)")
        }
    }

    @Test("extended data is kept as the bytes it was stored in")
    func extendedData() throws {
        let samples = try AnnotationSample.corpus()
        guard !samples.isEmpty else { return }
        for sample in samples {
            for handle in try sample.handles(ofTypes: DimensionOracle.objectTypes) {
                var reader = try #require(try sample.store.reader(for: handle))
                let entity = try reader.readDimension()
                let record = try #require(sample.records[handle])
                #expect(
                    entity.common.extendedData.count == record.all(1001).count,
                    "\(sample.name) \(handle)")
            }
        }
    }

    @Test("a dimension cut short throws and does not trap")
    func truncation() throws {
        let samples = try AnnotationSample.corpus()
        guard !samples.isEmpty else { return }
        for sample in samples {
            let store = sample.store
            for handle in try sample.handles(ofTypes: DimensionOracle.objectTypes) {
                let offset = try #require(store.map[handle])
                // Every cut of the objects section from just after the object's start to well
                // inside it ends in a throw or a value, never a trap.
                for length in stride(from: 4, to: 400, by: 3) {
                    let cut = Array(store.objects.prefix(offset + length))
                    var reader = try? ObjectReader(
                        objects: cut, offset: offset, version: store.container.version,
                        textEncoding: store.textEncoding)
                    _ = try? reader?.readDimension()
                }
            }
        }
    }

    @Test("the dimension kinds follow the object type codes")
    func kinds() {
        #expect(DimensionKind(objectType: ObjectType.dimensionLinear) == .linear)
        #expect(DimensionKind(objectType: ObjectType.dimensionAligned) == .aligned)
        #expect(DimensionKind(objectType: ObjectType.dimensionAngular2Line) == .angular2Line)
        #expect(DimensionKind(objectType: ObjectType.dimensionAngular3Point) == .angular3Point)
        #expect(DimensionKind(objectType: ObjectType.dimensionRadius) == .radius)
        #expect(DimensionKind(objectType: ObjectType.dimensionDiameter) == .diameter)
        #expect(DimensionKind(objectType: ObjectType.dimensionOrdinate) == .ordinate)
        #expect(DimensionKind(objectType: ObjectType.line) == nil)
    }
}
