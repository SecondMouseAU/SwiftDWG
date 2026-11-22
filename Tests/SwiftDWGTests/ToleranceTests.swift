import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// What differs between the TOLERANCE records of two DXF texts, which are compared by handle.
enum ToleranceOracle {
    struct Result {
        var compared = 0
        var mismatches: [String] = []
        var oursOnly: [UInt64] = []
        var theirsOnly: [UInt64] = []
    }

    /// Compares the TOLERANCE records of `ours`, the text SwiftDWG writes, with `theirs`, the ones
    /// in AutoCAD's own DXF.
    ///
    /// `caseInsensitiveNames` is for R14, which writes the names of its tables in upper case.
    static func compare(
        ours: [UInt64: DXFRecord], theirs: [UInt64: DXFRecord], caseInsensitiveNames: Bool = false
    ) -> Result {
        var result = Result()
        let expected = theirs.filter { $0.value.type == "TOLERANCE" }
        let written = ours.filter { $0.value.type == "TOLERANCE" }
        result.oursOnly = written.keys.filter { expected[$0] == nil }.sorted()
        for (handle, reference) in expected.sorted(by: { $0.key < $1.key }) {
            guard let record = written[handle] else {
                result.theirsOnly.append(handle)
                continue
            }
            result.compared += 1
            let name = String(handle, radix: 16, uppercase: true)
            for problem in mismatches(record, reference, caseInsensitiveNames) {
                result.mismatches.append("\(name): \(problem)")
            }
        }
        return result
    }

    /// The groups of a tolerance: layer, dimension style, insertion point, frame text, extrusion
    /// and direction, the last two being 0 0 1 and 1 0 0 when the record leaves them out.
    static func mismatches(
        _ record: DXFRecord, _ reference: DXFRecord, _ caseInsensitiveNames: Bool
    ) -> [String] {
        var bad: [String] = []
        func same(_ code: Int) {
            var a = record.first(code)
            var b = reference.first(code)
            if caseInsensitiveNames, code == 3 || code == 8 {
                a = a?.uppercased()
                b = b?.uppercased()
            }
            if a != b { bad.append("\(code): \(a ?? "none") is not \(b ?? "none")") }
        }
        func point(_ x: Int, default fallback: (Double, Double, Double)?) {
            guard let a = record.point(x, x + 10, x + 20) ?? fallback,
                let b = reference.point(x, x + 10, x + 20) ?? fallback
            else {
                bad.append("\(x): a point is missing")
                return
            }
            let ok =
                EntityOracle.near(a.0, b.0) && EntityOracle.near(a.1, b.1)
                && EntityOracle.near(a.2, b.2)
            if !ok { bad.append("\(x): \(a) is not \(b)") }
        }
        same(8)
        same(3)
        same(1)
        point(10, default: nil)
        point(210, default: (0, 0, 1))
        point(11, default: (1, 0, 0))
        // The groups the record has, in the order AutoCAD has them.
        let order = [8, 3, 10, 20, 30, 1]
        let ours = record.groups.map(\.code).filter { order.contains($0) }
        let theirs = reference.groups.map(\.code).filter { order.contains($0) }
        if ours != theirs { bad.append("groups \(ours) are not \(theirs)") }
        return bad
    }
}

@Suite("TOLERANCE")
struct ToleranceTests {
    static let releases: [DWG.Version] = [
        .ac1012, .ac1014, .ac1015, .ac1018, .ac1021, .ac1024, .ac1027, .ac1032,
    ]

    static let text = "{\\Fgdt;i}%%v0.012%%v%%vB\n.5"

    // MARK: Objects built by hand

    /// A tolerance with every field set to something that is not the default.
    static func object(_ version: DWG.Version, text: String = Self.text) -> SyntheticObject {
        var object = SyntheticObject(version: version, type: ObjectType.tolerance)
        if version <= .ac1014 {
            object.main.bitShort(7)  // a short no one uses
            object.main.bitDouble(2.5)  // the height of the frame
            object.main.bitDouble(0.18)  // DIMGAP times the dimension scale
        }
        object.main.point(10.5, -4.25, 2)  // the insertion point
        object.main.point(0, 1, 0)  // the direction
        object.main.point(1, 0, 0)  // the extrusion
        object.string(text)
        object.handles.handle(0x2D)  // the dimension style
        return object
    }

    static func decode(_ object: SyntheticObject) throws -> (EntityCommon, ToleranceData)? {
        var reader = try object.reader()
        guard let entity = try reader.readEntity(), case .tolerance(let data) = entity.geometry
        else { return nil }
        return (entity.common, data)
    }

    @Test("a tolerance reads back from every release")
    func handBuilt() throws {
        for version in Self.releases {
            let text = version >= .ac1021 ? Self.text + " \u{2300}" : Self.text
            let found = try Self.decode(Self.object(version, text: text))
            let (common, tolerance) = try #require(found, "\(version)")
            #expect(common.layer == 0x10 && common.handle == 0x1000, "\(version)")
            #expect(tolerance.insertion == DXF.Point(10.5, -4.25, 2), "\(version)")
            #expect(tolerance.direction == DXF.Point(0, 1, 0), "\(version)")
            #expect(tolerance.extrusion == DXF.Point(1, 0, 0), "\(version)")
            #expect(tolerance.text == text, "\(version)")
            #expect(tolerance.style == 0x2D, "\(version)")
        }
    }

    @Test("a tolerance is decoded, so it is named as an entity and not as one that is skipped")
    func names() {
        #expect(ObjectType.decodedTypeName(ObjectType.tolerance) == "TOLERANCE")
        #expect(ObjectType.typeName(ObjectType.tolerance, classes: [:]) == nil)
        #expect(ObjectType.isEntity(ObjectType.tolerance, classes: [:]))
    }

    @Test("a tolerance cut at any byte is refused until it is whole")
    func truncated() {
        for version in Self.releases {
            DamagedObjectTests.checkTruncation(
                Self.object(version).bytes(), version, "tolerance \(version)")
        }
    }

    // MARK: The DXF text

    /// The group codes of a record, without the line weight, which a hand-made entity has set to
    /// 0 and not left at the layer's.
    static func codes(_ record: DXFRecord) -> [Int] {
        record.groups.map(\.code).filter { $0 != 370 }
    }

    /// The text the emitter writes for this tolerance, as a record, on a drawing that has a
    /// dimension style to name.
    static func record(
        _ tolerance: ToleranceData, space: DXFEmitter.Space = .model
    ) throws -> (DXFRecord, styleName: String) {
        let store = try ObjectStore(try Container(try Fixtures.data("BLOCKPOINTPARAMETER.dwg")))
        let document = try Document(store: store)
        let (style, name) = try #require(document.dimensionStyleNames.first)
        var tolerance = tolerance
        if tolerance.style != 0 { tolerance.style = style }
        var emitter = DXFEmitter(document)
        emitter.write(
            DecodedEntity(
                common: EntityCommon(handle: 0x99, layer: 0), geometry: .tolerance(tolerance)),
            space: space)
        let record = try #require(DXFGroups.records(text: emitter.writer.text)[0x99])
        return (record, name)
    }

    @Test(
        "the groups are written in AutoCAD's order, and the usual direction and extrusion left out")
    func usualGroups() throws {
        var tolerance = ToleranceData()
        tolerance.style = 1
        tolerance.insertion = DXF.Point(214.5, -4.25, 0)
        tolerance.text = "{\\Fgdt;j}%%v0.5\n99"
        let (record, styleName) = try Self.record(tolerance)
        #expect(record.type == "TOLERANCE")
        #expect(Self.codes(record) == [5, 8, 3, 10, 20, 30, 1])
        #expect(record.first(3) == styleName)
        #expect(record.point(10, 20, 30) != nil && record.double(10) == 214.5)
        // A line feed is written as AutoCAD writes one in a value.
        #expect(record.first(1) == "{\\Fgdt;j}%%v0.5^J99")
    }

    @Test("a direction and an extrusion that are not the usual are written, after the text")
    func unusualGroups() throws {
        var tolerance = ToleranceData()
        tolerance.style = 1
        tolerance.direction = DXF.Point(0, 1, 0)
        tolerance.extrusion = DXF.Point(1, 0, 0)
        tolerance.text = "A"
        let (record, _) = try Self.record(tolerance, space: .paper)
        #expect(
            Self.codes(record) == [5, 67, 8, 3, 10, 20, 30, 1, 210, 220, 230, 11, 21, 31])
        #expect(record.point(11, 21, 31)?.y == 1)
        #expect(record.point(210, 220, 230)?.x == 1)
    }

    @Test("a dimension style the file does not hold is not named")
    func unknownStyle() throws {
        var tolerance = ToleranceData()
        tolerance.text = "A"
        let (record, _) = try Self.record(tolerance)
        #expect(record.first(3) == nil)
        #expect(record.first(1) == "A")
    }

    // MARK: AutoCAD's DXF

    @Test(
        "the tolerances of every AutoCAD sample from R2000 to R2018 equal its DXF records",
        .enabled(if: Fixtures.corpus != nil))
    func corpus() throws {
        let corpus = try #require(Fixtures.corpus)
        for name in Fixtures.corpusNamesOther + Fixtures.corpusNames {
            let data = try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg"))
            let ours = DXFGroups.records(text: try DWG.dxfText(data: data))
            let theirs = try DXFGroups.records(
                in: corpus.appendingPathComponent("\(name)_ascii.dxf"))
            let result = ToleranceOracle.compare(ours: ours, theirs: theirs)
            #expect(result.compared == 3, "\(name)")
            #expect(result.mismatches.isEmpty, "\(name) \(result.mismatches)")
            #expect(result.oursOnly.isEmpty && result.theirsOnly.isEmpty, "\(name)")
        }
    }

    @Test(
        "the tolerances of the R14 sample equal the R2000 DXF's, which keep their handles",
        .enabled(if: Fixtures.corpus != nil))
    func corpusR14() throws {
        let corpus = try #require(Fixtures.corpus)
        // There is no DXF of the R14 file, but it is the same drawing as the R2000 one.
        let data = try Data(contentsOf: corpus.appendingPathComponent("sample_AC1014.dwg"))
        let ours = DXFGroups.records(text: try DWG.dxfText(data: data))
        let theirs = try DXFGroups.records(
            in: corpus.appendingPathComponent("sample_AC1015_ascii.dxf"))
        let result = ToleranceOracle.compare(
            ours: ours, theirs: theirs, caseInsensitiveNames: true)
        #expect(result.compared == 3)
        #expect(result.mismatches.isEmpty, "\(result.mismatches)")
        #expect(result.oursOnly.isEmpty && result.theirsOnly.isEmpty)
    }
}
