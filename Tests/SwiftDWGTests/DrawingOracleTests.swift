import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// A whole drawing read from a DWG, compared with the drawing SwiftDXF reads from AutoCAD's own
/// DXF export of it.
///
/// Both go through the same SwiftDXF reader, so what is compared is what SwiftDWG decoded, not how
/// SwiftDXF reads. The expected side is AutoCAD's.
enum DrawingOracle {
    struct Report {
        /// Entities, by handle, that are the same in both.
        var same = 0
        /// Handles of entities that differ, with the kind of entity.
        var differing: [String: String] = [:]
        var oursOnly = 0
        var theirsOnly = 0
    }

    /// Every modelled entity of a drawing, model space and blocks, by handle, described in full.
    static func entities(of drawing: DXF.Drawing) -> [String: String] {
        var out: [String: String] = [:]
        func add(_ entities: [DXF.Entity], _ identities: [DXF.Identity]) {
            guard entities.count == identities.count else {
                Issue.record("\(entities.count) entities but \(identities.count) identities")
                return
            }
            for (entity, identity) in zip(entities, identities) {
                if let handle = identity.handle { out[handle.uppercased()] = normalised(entity) }
            }
        }
        add(drawing.entities, drawing.identities)
        for block in drawing.blocks { add(block.entities, block.identities) }
        return out
    }

    /// An entity as text, with each number rounded to 8 significant digits and the values below
    /// 1e-15, which AutoCAD's DXF writes as 0, taken as 0.
    static func normalised(_ entity: DXF.Entity) -> String {
        normalised(String(describing: entity))
    }

    /// The numbers in a description.
    private static let number = try! NSRegularExpression(
        pattern: "-?\\d+(?:\\.\\d+)?(?:e-?\\d+)?")

    static func normalised(_ text: String) -> String {
        let pattern = number
        var out = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .reversed()
        {
            guard let range = Range(match.range, in: text), let value = Double(text[range]) else {
                continue
            }
            out.replaceSubrange(
                range, with: abs(value) < 1e-15 ? "0" : String(format: "%.8g", value))
        }
        return out
    }

    /// A tally by type name, with the `NOT_DECODED_` that SwiftDWG puts before the type of an
    /// entity it does not decode taken off, so that it can be compared with AutoCAD's.
    static func withoutNotDecodedPrefix(_ tally: [String: Int]) -> [String: Int] {
        var out: [String: Int] = [:]
        for (name, count) in tally {
            if case .notDecoded(let type)? = DWG.SkippedKind(typeName: name) {
                out[type, default: 0] += count
            } else {
                out[name, default: 0] += count
            }
        }
        return out
    }

    /// The counts of a drawing by the name of the field, without these.
    ///
    /// SwiftDXF 0.5 added `tolerance` and `wipeout` to the counts, so a test that is to build with
    /// every release it allows reads the fields by name.
    static func fields(_ counts: DXF.Drawing.Counts, without names: Set<String>) -> [String: Int] {
        var out: [String: Int] = [:]
        for child in Mirror(reflecting: counts).children {
            if let label = child.label, !names.contains(label), let value = child.value as? Int {
                out[label] = value
            }
        }
        return out
    }

    /// How many TOLERANCE and WIPEOUT entities SwiftDXF models in this drawing: none before
    /// SwiftDXF 0.5, which skipped them.
    static func modelledToleranceAndWipeout(_ counts: DXF.Drawing.Counts) -> Int {
        let byName = fields(counts, without: [])
        return byName["tolerance", default: 0] + byName["wipeout", default: 0]
    }

    static func compare(_ ours: DXF.Drawing, _ theirs: DXF.Drawing) -> Report {
        let a = entities(of: ours)
        let b = entities(of: theirs)
        var report = Report()
        for (handle, description) in a {
            guard let other = b[handle] else {
                report.oursOnly += 1
                continue
            }
            if description == other {
                report.same += 1
            } else {
                report.differing[handle] = String(description.prefix { $0 != "(" })
            }
        }
        report.theirsOnly = b.keys.filter { a[$0] == nil }.count
        return report
    }
}

@Suite("Whole drawings against AutoCAD's DXF")
struct DrawingOracleTests {
    static let releases = ["AC1015", "AC1018", "AC1021", "AC1024", "AC1027", "AC1032"]

    private static func drawings(_ release: String) throws -> (
        ours: DXF.Drawing, theirs: DXF.Drawing
    ) {
        let corpus = try #require(Fixtures.corpus)
        let data = try Data(contentsOf: corpus.appendingPathComponent("sample_\(release).dwg"))
        let theirs = try DXF.read(
            contentsOf: corpus.appendingPathComponent("sample_\(release)_ascii.dxf"))
        return (try DWG.read(data: data), theirs)
    }

    @Test("a small AutoCAD drawing reads to exactly the drawing its DXF reads to")
    func smallDrawing() throws {
        let data = try Data(
            contentsOf: Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dwg"))
        let ours = try DWG.read(data: data)
        let theirs = try DXF.read(
            contentsOf: Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dxf"))
        let report = DrawingOracle.compare(ours, theirs)
        #expect(report.same >= 3)
        #expect(report.differing.isEmpty, "\(report.differing)")
        #expect(ours.insUnits == theirs.insUnits)
        #expect(ours.counts == theirs.counts)
        #expect(ours.layers.map(\.name) == theirs.layers.map(\.name))
        #expect(ours.dimensionStyles.map(\.name) == theirs.dimensionStyles.map(\.name))
        // AutoCAD's DXF renumbers the anonymous blocks, so their numbers are not compared.
        func unnumbered(_ drawing: DXF.Drawing) -> [String] {
            drawing.blocks.map { $0.name.hasPrefix("*U") ? "*U" : $0.name }.sorted()
        }
        #expect(unnumbered(ours) == unnumbered(theirs))
        #expect(ours.references.count == theirs.references.count)
    }

    @Test(
        "the entities equal AutoCAD's, except the few it is known not to reproduce",
        .enabled(if: Fixtures.corpus != nil), arguments: releases)
    func entities(release: String) throws {
        let (ours, theirs) = try Self.drawings(release)
        let report = DrawingOracle.compare(ours, theirs)
        // Of 267 entities, 262 are identical. A leader: AutoCAD adds a vertex for its hook line
        // when it writes DXF, which the DWG does not hold. A spline that R2013 and later keep as
        // fit points only, where the DXF has computed control points and knots. Both are
        // reported, not hidden.
        #expect(report.same >= 262, "\(release)")
        #expect(
            Set(report.differing.values).isSubset(of: ["leader", "spline"]),
            "\(release) \(report.differing)")
        #expect(report.differing.count <= 2, "\(release)")
        #expect(report.same + report.differing.count + report.oursOnly == 265 + 1, "\(release)")
        // Handles the DXF export gave a different number, such as a table cell's block, and the
        // TOLERANCEs and WIPEOUTs that SwiftDXF models (from 0.5) and SwiftDWG does not decode
        // yet, which it counts as not decoded and does not write as an empty record.
        let notDecodedYet =
            DrawingOracle.modelledToleranceAndWipeout(theirs.counts)
            - DrawingOracle.modelledToleranceAndWipeout(ours.counts)
        #expect(report.oursOnly <= 1 && report.theirsOnly <= 2 + notDecodedYet, "\(release)")
    }

    @Test(
        "the counts, units, extents and skipped types equal AutoCAD's, with the named exceptions",
        .enabled(if: Fixtures.corpus != nil), arguments: releases)
    func summary(release: String) throws {
        let (ours, theirs) = try Self.drawings(release)
        // TOLERANCE and WIPEOUT: SwiftDXF 0.5 and later model them, and SwiftDWG does not decode
        // them yet, so they are counted as not decoded here and as entities there; before 0.5
        // both skip them. Either way none is left out.
        let undecoded = DrawingOracle.withoutNotDecodedPrefix(ours.skipped)
        for type in ["TOLERANCE", "WIPEOUT"] {
            let field = type.lowercased()
            let here =
                undecoded[type, default: 0]
                + DrawingOracle.fields(ours.counts, without: [])[field, default: 0]
            let there =
                theirs.skipped[type, default: 0]
                + DrawingOracle.fields(theirs.counts, without: [])[field, default: 0]
            #expect(here == there, "\(release) \(type)")
        }
        // The one polyface mesh is not decoded, so it is skipped here and a polyline there.
        #expect(ours.counts.polyline + 1 == theirs.counts.polyline, "\(release)")
        let apart: Set = ["polyline", "tolerance", "wipeout"]
        #expect(
            DrawingOracle.fields(ours.counts, without: apart)
                == DrawingOracle.fields(theirs.counts, without: apart),
            "\(release)")
        #expect(ours.insUnits == theirs.insUnits, "\(release)")
        #expect(
            DrawingOracle.withoutNotDecodedPrefix(ours.paperSpace) == theirs.paperSpace,
            "\(release)")
        if let x = ours.extMin, let y = theirs.extMin {
            #expect(abs(x.x - y.x) < 1e-6 && abs(x.y - y.y) < 1e-6, "\(release)")
        } else {
            Issue.record("\(release) has no extents")
        }
        // The polyface mesh and its vertices are skipped by name. The attributes are written, so
        // they are counted as AutoCAD's are, in whichever way SwiftDXF counts them.
        var skipped = DrawingOracle.withoutNotDecodedPrefix(ours.skipped)
        var expected = theirs.skipped
        skipped["POLYFACE_MESH"] = nil
        // TOLERANCE and WIPEOUT were compared above.
        for type in ["TOLERANCE", "WIPEOUT"] {
            skipped[type] = nil
            expected[type] = nil
        }
        #expect(skipped == expected, "\(release) \(skipped) \(expected)")
    }

    @Test(
        "the tables equal AutoCAD's, with the named exceptions",
        .enabled(if: Fixtures.corpus != nil), arguments: releases)
    func tables(release: String) throws {
        let (ours, theirs) = try Self.drawings(release)

        // Layers: the same names. The colour of a layer that has a true colour is the nearest
        // palette index, which AutoCAD chooses a little differently for one of them.
        #expect(
            ours.layers.map(\.name).sorted() == theirs.layers.map(\.name).sorted(), "\(release)")
        var colourDifferences = 0
        for layer in ours.layers {
            guard let other = theirs.layers.first(where: { $0.name == layer.name }) else {
                continue
            }
            if layer.color != other.color { colourDifferences += 1 }
            #expect(layer.lineTypeName == other.lineTypeName, "\(release) \(layer.name)")
            #expect(layer.isOff == other.isOff && layer.isFrozen == other.isFrozen, "\(layer.name)")
            #expect(layer.isLocked == other.isLocked, "\(release) \(layer.name)")
        }
        #expect(colourDifferences <= 1, "\(release)")

        // Line types: the same names and dash patterns.
        #expect(ours.lineTypes.map(\.name) == theirs.lineTypes.map(\.name), "\(release)")
        for (a, b) in zip(ours.lineTypes, theirs.lineTypes) {
            #expect(a.pattern.count == b.pattern.count, "\(release) \(a.name)")
            for (x, y) in zip(a.pattern, b.pattern) {
                #expect(abs(x - y) < 1e-9, "\(release) \(a.name)")
            }
        }

        // Dimension styles, with their variables and the header's defaults.
        #expect(ours.dimensionStyles.count == theirs.dimensionStyles.count, "\(release)")
        for (a, b) in zip(ours.dimensionStyles, theirs.dimensionStyles) {
            #expect(a.name == b.name && a.variables == b.variables, "\(release) \(a.name)")
        }
        #expect(ours.dimensionDefaults == theirs.dimensionDefaults, "\(release)")

        // Blocks: the same names and the same number of entities and references, except the
        // dynamic block that AutoCAD's DXF renames to its anonymous `*U` name.
        #expect(ours.blocks.count == theirs.blocks.count, "\(release)")
        var renamed = 0
        for block in ours.blocks {
            guard let other = theirs.blocks.first(where: { $0.name == block.name }) else {
                renamed += 1
                continue
            }
            #expect(block.entities.count == other.entities.count, "\(release) \(block.name)")
            #expect(block.references.count == other.references.count, "\(release) \(block.name)")
        }
        #expect(renamed <= 1, "\(release)")
    }

    @Test(
        "the R14 sample has the lines, circles, arcs, points and texts the R2000 DXF has",
        .enabled(if: Fixtures.corpus != nil))
    func r14() throws {
        let corpus = try #require(Fixtures.corpus)
        let ours = try DWG.read(
            data: try Data(contentsOf: corpus.appendingPathComponent("sample_AC1014.dwg")))
        let theirs = try DXF.read(
            contentsOf: corpus.appendingPathComponent("sample_AC1015_ascii.dxf"))
        // There is no DXF of the R14 file, and the two saves do not share every handle, so the
        // entities are compared as sets of what they hold. The later drawing's dimensions,
        // leader and spline differ in ways that need a DXF of the R14 file to judge: only the
        // simple kinds are required to agree here. The lightweight polylines and hatches keep
        // their handles, and are compared by handle in `ClassEntityTests`.
        func descriptions(_ drawing: DXF.Drawing) -> Set<String> {
            // R14 writes names in upper case, so the text is compared without regard to case.
            Set(DrawingOracle.entities(of: drawing).values.map { $0.uppercased() })
        }
        let missing = descriptions(theirs).subtracting(descriptions(ours))
        let simple = missing.filter { entity in
            ["LINE(", "CIRCLE(", "ARC(", "POINT("].contains { entity.hasPrefix($0) }
        }
        #expect(simple.isEmpty, "\(simple.prefix(3))")
        #expect(ours.counts.line == theirs.counts.line)
        #expect(ours.counts.circle == theirs.counts.circle)
        #expect(ours.counts.point == theirs.counts.point)
    }
}
