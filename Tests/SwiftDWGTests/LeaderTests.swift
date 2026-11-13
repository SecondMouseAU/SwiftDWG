import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

enum LeaderOracle {
    struct Result {
        var compared = 0
        var mismatches: [String] = []
        var dwgOnly: [UInt64] = []
        var dxfOnly: [UInt64] = []
    }

    static func near(_ a: Double, _ b: Double) -> Bool { EntityOracle.near(a, b) }

    static func compare(_ sample: AnnotationSample) throws -> Result {
        var result = Result()
        let dxf = sample.records(ofType: "LEADER")
        var seen = Set<UInt64>()
        for handle in try sample.handles(ofTypes: [ObjectType.leader]) {
            var reader = try #require(try sample.store.reader(for: handle))
            let entity = try reader.readLeader()
            guard case .leader(let leader) = entity.geometry else { continue }
            seen.insert(handle)
            guard let record = dxf[handle] else {
                result.dwgOnly.append(handle)
                continue
            }
            result.compared += 1
            let name = String(handle, radix: 16, uppercase: true)
            result.mismatches.append(
                contentsOf: mismatches(of: leader, against: record, in: sample).map {
                    "\(sample.name) \(name): \($0)"
                })
        }
        result.dxfOnly = dxf.keys.filter { !seen.contains($0) }
        return result
    }

    /// What differs between a decoded leader and its DXF record.
    static func mismatches(
        of leader: LeaderData, against record: DXFRecord, in sample: AnnotationSample
    ) -> [String] {
        var bad: [String] = []
        func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
            if !ok { bad.append(what()) }
        }
        func point(_ x: Int, _ y: Int, _ z: Int, default value: DXF.Point) -> DXF.Point {
            record.point(x, y, z).map { DXF.Point($0.x, $0.y, $0.z) } ?? value
        }

        // AutoCAD leaves the groups that hold their default out: 71 is 1 and 72 is 0 by default.
        expect(leader.annotationType == record.int(73), "73: \(leader.annotationType)")
        expect(leader.pathType == (record.int(72) ?? 0), "72: \(leader.pathType)")
        expect(leader.hasArrowHead == ((record.int(71) ?? 1) != 0), "71")
        expect(leader.hookLineOnHorizontalDirection == ((record.int(74) ?? 0) != 0), "74")
        expect(
            leader.annotation == record.first(340).flatMap { UInt64($0, radix: 16) },
            "340: \(leader.annotation)")
        expect(
            sample.records[leader.style]?.type == "DIMSTYLE"
                && sample.records[leader.style]?.first(2) == record.first(3),
            "dimension style \(leader.style) is not \(String(describing: record.first(3)))")

        // The DXF has a vertex more than the file when it flags a hook line (75): the start of
        // the hook line, which lies before the last vertex along the horizontal direction.
        let xs = record.all(10).compactMap { Double($0) }
        let ys = record.all(20).compactMap { Double($0) }
        let zs = record.all(30).compactMap { Double($0) }
        expect(xs.count == record.int(76) && ys.count == xs.count && zs.count == xs.count, "76")
        var reference = zip(xs, zip(ys, zs)).map { DXF.Point($0, $1.0, $1.1) }
        if record.int(75) == 1, reference.count == leader.vertices.count + 1 {
            let hook = reference.remove(at: reference.count - 2)
            if let last = leader.vertices.last {
                let along = leader.horizontalDirection
                let offset = (hook.x - last.x, hook.y - last.y, hook.z - last.z)
                let cross = (
                    offset.1 * along.z - offset.2 * along.y,
                    offset.2 * along.x - offset.0 * along.z,
                    offset.0 * along.y - offset.1 * along.x
                )
                expect(
                    abs(cross.0) + abs(cross.1) + abs(cross.2) < 1e-9 * (1 + abs(offset.0)),
                    "the hook line start is not along the horizontal direction")
            }
        }
        expect(reference.count == leader.vertices.count, "vertex count \(leader.vertices.count)")
        for (decoded, expected) in zip(leader.vertices, reference) {
            expect(EntityOracle.near(decoded, expected), "vertex \(decoded) vs \(expected)")
        }

        // The size of the text box is in the file until R2007.
        if let height = leader.textHeight, let width = leader.textWidth {
            expect(near(height, record.double(40) ?? .nan), "40")
            expect(near(width, record.double(41) ?? .nan), "41")
        } else {
            expect(sample.store.container.version >= .ac1024, "no text box before R2010")
        }
        expect(
            EntityOracle.near(leader.extrusion, point(210, 220, 230, default: DXF.Point(0, 0, 1))),
            "210")
        expect(
            EntityOracle.near(
                leader.horizontalDirection, point(211, 221, 231, default: DXF.Point(1, 0, 0))),
            "211")
        expect(
            EntityOracle.near(
                leader.blockOffset, point(212, 222, 232, default: DXF.Point(0, 0, 0))),
            "212")
        if let offset = leader.annotationOffset {
            expect(
                EntityOracle.near(offset, point(213, 223, 233, default: DXF.Point(0, 0, 0))),
                "213")
        }
        return bad
    }
}

@Suite("Leaders against AutoCAD's DXF")
struct LeaderTests {
    @Test("the committed fixture holds no leader, and the reader finds none")
    func fixtureHasNone() throws {
        let sample = try #require(try AnnotationSample.all().first)
        #expect(try sample.handles(ofTypes: [ObjectType.leader]).isEmpty)
        #expect(sample.records(ofType: "LEADER").isEmpty)
    }

    @Test("the leader of every AutoCAD sample from R2004 to R2018 equals its DXF record")
    func corpus() throws {
        let samples = try AnnotationSample.corpus()
        guard !samples.isEmpty else { return }  // needs DWG_CORPUS: skipped without it
        for sample in samples {
            let result = try LeaderOracle.compare(sample)
            #expect(result.compared == 1, "\(sample.name)")
            #expect(result.mismatches.isEmpty, "\(result.mismatches)")
            #expect(result.dwgOnly.isEmpty && result.dxfOnly.isEmpty, "\(sample.name)")
        }
    }

    @Test("a leader cut short throws and does not trap")
    func truncation() throws {
        let samples = try AnnotationSample.corpus()
        guard !samples.isEmpty else { return }
        for sample in samples {
            let store = sample.store
            for handle in try sample.handles(ofTypes: [ObjectType.leader]) {
                let offset = try #require(store.map[handle])
                for length in stride(from: 4, to: 300, by: 3) {
                    let cut = Array(store.objects.prefix(offset + length))
                    var reader = try? ObjectReader(
                        objects: cut, offset: offset, version: store.container.version,
                        textEncoding: store.textEncoding)
                    _ = try? reader?.readLeader()
                }
            }
        }
    }
}
