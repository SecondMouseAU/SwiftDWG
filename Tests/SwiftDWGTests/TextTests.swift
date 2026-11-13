import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// TEXT and MTEXT read from a DWG, compared with the records of AutoCAD's own DXF export.
///
/// The expected values are the raw groups AutoCAD wrote, so nothing here is checked against
/// SwiftDWG's own output. The style is a handle in the DWG and a name in the DXF, so it is checked
/// by looking the handle up among the DXF's own style records.
enum TextOracle {
    /// What comparing one drawing found, by DXF type (`TEXT` or `MTEXT`).
    struct Result {
        /// Entities the DWG holds.
        var decoded: [String: Int] = [:]
        /// Entities the DXF holds.
        var expected: [String: Int] = [:]
        /// Entities compared with the DXF record of the same handle.
        var byHandle: [String: Int] = [:]
        /// Entities compared with a DXF record found by content, because the DXF has none under
        /// their handle.
        var byContent: [String: Int] = [:]
        var mismatches: [String] = []
        /// Decoded entities with no DXF record to compare with.
        var unmatched: [String] = []
        /// DXF records with no decoded entity.
        var dxfOnly: [String] = []
    }

    static func near(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= 1e-9 * max(1, abs(b))
    }

    static func near(_ a: DXF.Point, _ b: (x: Double, y: Double, z: Double)) -> Bool {
        near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z)
    }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Whether two angles in degrees are the same angle, modulo a full turn.
    static func nearAngle(_ degrees: Double, _ expected: Double) -> Bool {
        var difference = (degrees - expected).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        return abs(difference) <= 1e-7
    }

    /// A DXF string with its control characters decoded: `^J` is a line feed, `^ ` a caret.
    static func decoded(_ text: String) -> String {
        var out = ""
        var iterator = text.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            guard scalar == "^", let next = iterator.next() else {
                out.unicodeScalars.append(scalar)
                continue
            }
            if next == " " {
                out += "^"
            } else if let control = Unicode.Scalar(next.value ^ 0x40) {
                out.unicodeScalars.append(control)
            }
        }
        return out
    }

    /// The strings of every TEXT and MTEXT in a DXF as written, spaces included, by handle.
    ///
    /// `DXFGroups` trims every value, which would drop the spaces at the ends of the 250-character
    /// chunks a long MTEXT is written in, so the strings are read again here untouched. A long
    /// MTEXT is its group 3 chunks followed by its group 1.
    static func strings(in url: URL) throws -> [UInt64: String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : String($0)
        }
        var out: [UInt64: String] = [:]
        var type = ""
        var handle: UInt64?
        var chunks = ""
        var last: String?
        func finish() {
            if let handle, type == "TEXT" || type == "MTEXT" { out[handle] = chunks + (last ?? "") }
            handle = nil
            chunks = ""
            last = nil
        }
        var index = 0
        while index + 1 < lines.count {
            let code = Int(lines[index].trimmingCharacters(in: .whitespaces))
            let value = lines[index + 1]
            index += 2
            switch code {
            case 0:
                finish()
                type = value.trimmingCharacters(in: .whitespaces)
            case 5 where handle == nil:
                handle = UInt64(value.trimmingCharacters(in: .whitespaces), radix: 16)
            case 3: chunks += value
            case 1 where last == nil: last = value
            default: break
            }
        }
        finish()
        return out
    }

    /// Whether a style handle names the style the DXF record names.
    static func styleMatches(_ handle: UInt64, name: String?, in records: [UInt64: DXFRecord])
        -> Bool
    {
        guard let name, !name.isEmpty else { return true }
        guard handle != 0, let style = records[handle], style.type == "STYLE" else { return false }
        return style.first(2)?.lowercased() == name.lowercased()
    }

    /// The decoded TEXT and MTEXT of a drawing, with the type name the DXF gives them.
    static func decode(_ store: ObjectStore) throws -> [(handle: UInt64, geometry: EntityGeometry)]
    {
        var out: [(UInt64, EntityGeometry)] = []
        for handle in store.handles {
            guard var reader = try store.reader(for: handle),
                reader.type == ObjectType.text || reader.type == ObjectType.mtext
            else { continue }
            if let decoded = try reader.readEntity() { out.append((handle, decoded.geometry)) }
        }
        return out
    }

    static func typeName(_ geometry: EntityGeometry) -> String {
        if case .text = geometry { return "TEXT" }
        return "MTEXT"
    }

    static func value(_ geometry: EntityGeometry) -> String {
        switch geometry {
        case .text(let text): return text.value
        case .mtext(let mtext): return mtext.value
        default: return ""
        }
    }

    static func insertion(_ geometry: EntityGeometry) -> DXF.Point {
        switch geometry {
        case .text(let text): return text.insertion
        case .mtext(let mtext): return mtext.insertion
        default: return DXF.Point(0, 0, 0)
        }
    }

    /// Checks that the style handle leads to a text style in the DWG.
    static func kinds(_ geometry: EntityGeometry, in store: ObjectStore) -> [String] {
        let style: UInt64
        switch geometry {
        case .text(let text): style = text.style
        case .mtext(let mtext): style = mtext.style
        default: return ["not a text entity"]
        }
        return (try? store.reader(for: style))?.type == ObjectType.style ? [] : ["style kind"]
    }

    /// Compares every decoded TEXT and MTEXT with the DXF.
    ///
    /// A table cell's text has no record of its own in AutoCAD's DXF under the handle the DWG
    /// gives it: the export writes the table out again with new handles. Such an entity is
    /// compared with the DXF record that has the same text at the same point.
    static func compare(
        _ store: ObjectStore, with records: [UInt64: DXFRecord], strings: [UInt64: String]
    ) throws -> Result {
        var result = Result()
        let hasAnnotativeFlag = store.container.version >= .ac1032
        for record in records.values where record.type == "TEXT" || record.type == "MTEXT" {
            result.expected[record.type, default: 0] += 1
        }

        var claimed = Set<UInt64>()
        var orphans: [(handle: UInt64, geometry: EntityGeometry)] = []
        for entry in try decode(store) {
            let type = typeName(entry.geometry)
            result.decoded[type, default: 0] += 1
            guard let record = records[entry.handle], record.type == type else {
                orphans.append(entry)
                continue
            }
            claimed.insert(entry.handle)
            result.byHandle[type, default: 0] += 1
            let text = decoded(strings[entry.handle] ?? "")
            let failures =
                check(
                    entry.geometry, against: record, text: text, in: records,
                    hasAnnotativeFlag: hasAnnotativeFlag) + kinds(entry.geometry, in: store)
            result.mismatches += failures.map { "\(hex(entry.handle)) \($0)" }
        }

        for entry in orphans {
            let type = typeName(entry.geometry)
            let candidate = records.first { handle, record in
                record.type == type && !claimed.contains(handle)
                    && decoded(strings[handle] ?? "") == value(entry.geometry)
                    && record.point(10, 20, 30).map { near(insertion(entry.geometry), $0) } == true
            }
            guard let (handle, record) = candidate else {
                result.unmatched.append("\(hex(entry.handle)) \(type)")
                continue
            }
            claimed.insert(handle)
            result.byContent[type, default: 0] += 1
            let failures =
                check(
                    entry.geometry, against: record, text: value(entry.geometry), in: records,
                    hasAnnotativeFlag: hasAnnotativeFlag) + kinds(entry.geometry, in: store)
            result.mismatches += failures.map { "\(hex(entry.handle)) \($0)" }
        }

        for (handle, record) in records
        where (record.type == "TEXT" || record.type == "MTEXT") && !claimed.contains(handle) {
            result.dxfOnly.append("\(hex(handle)) \(record.type)")
        }
        return result
    }

    static func hex(_ handle: UInt64) -> String { String(handle, radix: 16, uppercase: true) }

    static func check(
        _ geometry: EntityGeometry, against record: DXFRecord, text: String,
        in records: [UInt64: DXFRecord], hasAnnotativeFlag: Bool
    ) -> [String] {
        switch geometry {
        case .text(let data):
            return check(data, against: record, text: text, in: records)
        case .mtext(let data):
            return check(
                data, against: record, text: text, in: records,
                hasAnnotativeFlag: hasAnnotativeFlag)
        default:
            return ["not a text entity"]
        }
    }

    static func check(
        _ text: TextData, against record: DXFRecord, text expected: String,
        in records: [UInt64: DXFRecord]
    ) -> [String] {
        var failures: [String] = []
        func expect(_ ok: Bool, _ field: String) { if !ok { failures.append(field) } }

        expect(record.point(10, 20, 30).map { near(text.insertion, $0) } ?? false, "insertion")
        expect(near(text.height, record.double(40) ?? .nan), "height")
        expect(text.value == expected, "value")
        expect(nearAngle(degrees(text.rotation), record.double(50) ?? 0), "rotation")
        expect(near(text.widthFactor, record.double(41) ?? 1), "widthFactor")
        expect(nearAngle(degrees(text.obliqueAngle), record.double(51) ?? 0), "oblique")
        expect(text.generation == (record.int(71) ?? 0), "generation")
        expect(text.horizontalAlignment == (record.int(72) ?? 0), "horizontalAlignment")
        expect(text.verticalAlignment == (record.int(73) ?? 0), "verticalAlignment")
        expect(near(text.thickness, record.double(39) ?? 0), "thickness")
        expect(near(text.extrusion, record.point(210, 220, 230) ?? (0, 0, 1)), "extrusion")
        if let alignment = record.point(11, 21, 31) {
            expect(text.alignmentPoint.map { near($0, alignment) } ?? false, "alignmentPoint")
        } else {
            expect(text.alignmentPoint == nil, "alignmentPoint absent")
        }
        expect(styleMatches(text.style, name: record.first(7), in: records), "style")
        return failures
    }

    /// Compares an MTEXT.
    ///
    /// From R2018 a DXF MTEXT may carry an embedded object (from group 101 on) that repeats the
    /// box and gives the column layout, so the main groups are the ones before it.
    static func check(
        _ mtext: MTextData, against whole: DXFRecord, text expected: String,
        in records: [UInt64: DXFRecord], hasAnnotativeFlag: Bool
    ) -> [String] {
        var failures: [String] = []
        func expect(_ ok: Bool, _ field: String) { if !ok { failures.append(field) } }

        let split = whole.groups.firstIndex { $0.code == 101 } ?? whole.groups.count
        let record = DXFRecord(type: whole.type, groups: Array(whole.groups[..<split]))
        let embedded = DXFRecord(type: whole.type, groups: Array(whole.groups[split...]))

        expect(record.point(10, 20, 30).map { near(mtext.insertion, $0) } ?? false, "insertion")
        expect(near(mtext.height, record.double(40) ?? .nan), "height")
        expect(near(mtext.rectangleWidth, record.double(41) ?? 0), "rectangleWidth")
        expect(near(mtext.rectangleHeight, record.double(46) ?? 0), "rectangleHeight")
        expect(mtext.attachment == (record.int(71) ?? 0), "attachment")
        expect(mtext.drawingDirection == (record.int(72) ?? 0), "drawingDirection")
        expect(mtext.lineSpacingStyle == (record.int(73) ?? 1), "lineSpacingStyle")
        expect(near(mtext.lineSpacingFactor, record.double(44) ?? 1), "lineSpacingFactor")
        expect(near(mtext.extrusion, record.point(210, 220, 230) ?? (0, 0, 1)), "extrusion")
        // The DXF gives the direction as group 11, or as a rotation (group 50) when it is flat.
        if let direction = record.point(11, 21, 31) {
            expect(near(mtext.xAxisDirection, direction), "xAxisDirection")
        } else {
            let angle = degrees(atan2(mtext.xAxisDirection.y, mtext.xAxisDirection.x))
            expect(nearAngle(angle, record.double(50) ?? 0), "rotation")
        }
        expect(mtext.value == expected, "value")
        expect(styleMatches(mtext.style, name: record.first(7), in: records), "style")
        expect(mtext.backgroundFillFlags == (record.int(90) ?? 0), "backgroundFillFlags")
        if mtext.backgroundFillFlags & 1 != 0 {
            expect(near(mtext.backgroundScale, record.double(45) ?? 1.5), "backgroundScale")
            expect(mtext.backgroundTransparency == (record.int(441) ?? 0), "backgroundTransparency")
            // A true colour is group 421 as one number, an index group 63.
            switch mtext.backgroundColor {
            case .rgb(let red, let green, let blue):
                let packed = Int(red) << 16 | Int(green) << 8 | Int(blue)
                expect(record.int(421) == packed, "backgroundColor")
            case .index(let index):
                expect(record.int(63) == index, "backgroundColor")
            default:
                expect(false, "backgroundColor")
            }
        }

        if hasAnnotativeFlag {
            let annotative = record.all(1001).contains("AcadAnnotative")
            expect(mtext.isAnnotative == annotative, "isAnnotative")
        }
        // The embedded object is there exactly when the text has columns.
        if hasAnnotativeFlag, let columns = mtext.columns {
            expect(near(mtext.extentsWidth, embedded.double(42) ?? .nan), "extentsWidth")
            expect(near(mtext.extentsHeight, embedded.double(43) ?? .nan), "extentsHeight")
            expect(columns.type == embedded.int(71), "columnType")
            expect(near(columns.width, embedded.double(44) ?? .nan), "columnWidth")
            expect(near(columns.gutter, embedded.double(45) ?? .nan), "columnGutter")
            expect(columns.autoHeight == ((embedded.int(73) ?? 0) != 0), "columnAutoHeight")
            expect(columns.flowReversed == ((embedded.int(74) ?? 0) != 0), "columnFlowReversed")
            // Where the DXF writes a height of 0.0 the DWG holds a negative one, which is not a
            // height the drawing gives, so only a height that is not 0.0 is compared.
            let heights = embedded.all(46).compactMap { Double($0) }
            expect(columns.heights.count == heights.count, "columnHeights count")
            for (height, expected) in zip(columns.heights, heights) {
                expect(expected == 0 ? height <= 0 : near(height, expected), "columnHeight")
            }
        } else if hasAnnotativeFlag {
            expect(embedded.groups.isEmpty, "embedded object without columns")
        }
        return failures
    }
}

@Suite("TEXT and MTEXT against AutoCAD's DXF")
struct TextTests {
    @Test("every AutoCAD sample from R2004 to R2018 reads to the TEXT and MTEXT its DXF has")
    func corpus() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        for name in Fixtures.corpusNames {
            let data = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
            let store = try ObjectStore(try Container(data))
            let dxf = corpus.appendingPathComponent("\(name)_ascii.dxf")
            let result = try TextOracle.compare(
                store, with: try DXFGroups.records(in: dxf),
                strings: try TextOracle.strings(in: dxf))
            #expect(result.decoded == ["TEXT": 29, "MTEXT": 36], "\(name)")
            #expect(result.expected == result.decoded, "\(name)")
            #expect(result.byHandle == ["TEXT": 29, "MTEXT": 35], "\(name)")
            #expect(result.byContent == ["MTEXT": 1], "\(name)")
            #expect(result.mismatches.isEmpty, "\(name) \(result.mismatches.prefix(5))")
            #expect(result.unmatched.isEmpty, "\(name) \(result.unmatched)")
            #expect(result.dxfOnly.isEmpty, "\(name) \(result.dxfOnly)")
        }
    }
}
