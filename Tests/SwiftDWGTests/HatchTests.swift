import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// The groups of a DXF `HATCH` record, taken in the order AutoCAD wrote them.
private struct HatchGroups {
    let groups: [(code: Int, value: String)]
    var index: Int
    var problems: [String] = []

    init(_ record: DXFRecord) {
        groups = record.groups
        // The boundary data starts after the number of paths.
        index = (record.groups.firstIndex { $0.code == 91 } ?? record.groups.count) + 1
    }

    /// The next group, which must have this code.
    mutating func take(_ code: Int) -> String? {
        guard index < groups.count, groups[index].code == code else {
            let found = index < groups.count ? "\(groups[index].code)" : "the end"
            problems.append("expected group \(code) at \(index), found \(found)")
            return nil
        }
        defer { index += 1 }
        return groups[index].value
    }

    mutating func takeDouble(_ code: Int) -> Double? { take(code).flatMap { Double($0) } }

    mutating func takeInt(_ code: Int) -> Int? { take(code).flatMap { Int($0) } }

    /// Whether the next group has this code.
    func isNext(_ code: Int) -> Bool { index < groups.count && groups[index].code == code }
}

enum HatchOracle {
    struct Result {
        var compared = 0
        var mismatches: [String] = []
        var dwgOnly: [UInt64] = []
        var dxfOnly: [UInt64] = []
        /// The number of boundary paths by shape, and of edges by type, over all the hatches.
        var shapes: [String: Int] = [:]
    }

    static func near(_ a: Double, _ b: Double) -> Bool { EntityOracle.near(a, b) }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    static func compare(_ sample: AnnotationSample) throws -> Result {
        var result = Result()
        let dxf = sample.records(ofType: "HATCH")
        var seen = Set<UInt64>()
        for handle in try sample.handles(ofTypes: [ObjectType.hatch]) {
            var reader = try #require(try sample.store.reader(for: handle))
            let entity = try reader.readHatch()
            guard case .hatch(let hatch) = entity.geometry else { continue }
            seen.insert(handle)
            for path in hatch.paths {
                switch path.shape {
                case .polyline: result.shapes["polyline", default: 0] += 1
                case .edges(let edges):
                    for edge in edges {
                        switch edge {
                        case .line: result.shapes["line", default: 0] += 1
                        case .circularArc: result.shapes["circularArc", default: 0] += 1
                        case .ellipticArc: result.shapes["ellipticArc", default: 0] += 1
                        case .spline: result.shapes["spline", default: 0] += 1
                        }
                    }
                }
            }
            guard let record = dxf[handle] else {
                result.dwgOnly.append(handle)
                continue
            }
            result.compared += 1
            let name = String(handle, radix: 16, uppercase: true)
            result.mismatches.append(
                contentsOf: mismatches(of: hatch, against: record, in: sample).map {
                    "\(sample.name) \(name): \($0)"
                })
        }
        result.dxfOnly = dxf.keys.filter { !seen.contains($0) }
        return result
    }

    /// What differs between a decoded hatch and its DXF record.
    static func mismatches(
        of hatch: HatchData, against record: DXFRecord, in sample: AnnotationSample
    ) -> [String] {
        var bad: [String] = []
        func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
            if !ok { bad.append(what()) }
        }
        func expectPoint(_ point: DXF.Point2, _ x: Double?, _ y: Double?, _ what: String) {
            expect(
                near(point.x, x ?? .nan) && near(point.y, y ?? .nan),
                "\(what) (\(point.x), \(point.y)) vs (\(String(describing: x)), \(String(describing: y)))"
            )
        }

        expect(near(hatch.elevation, record.double(30) ?? 0), "elevation")
        if let normal = record.point(210, 220, 230) {
            expect(
                EntityOracle.near(
                    hatch.extrusion, DXF.Point(normal.x, normal.y, normal.z)), "extrusion")
        }
        expect(hatch.patternName == record.first(2), "pattern \(hatch.patternName)")
        expect(hatch.isSolid == (record.int(70) == 1), "70 solid")
        expect(hatch.isAssociative == (record.int(71) == 1), "71 associative")
        expect(hatch.paths.count == record.int(91), "91: \(hatch.paths.count)")

        var groups = HatchGroups(record)
        for (number, path) in hatch.paths.enumerated() {
            let label = "path \(number)"
            expect(groups.takeInt(92) == path.flags, "\(label) flags \(path.flags)")
            switch path.shape {
            case .polyline(let vertices, let isClosed, let hasBulges):
                expect(path.isPolyline, "\(label) is a polyline without the flag")
                expect((groups.takeInt(72) == 1) == hasBulges, "\(label) bulges")
                expect((groups.takeInt(73) == 1) == isClosed, "\(label) closed")
                expect(groups.takeInt(93) == vertices.count, "\(label) vertex count")
                for (n, vertex) in vertices.enumerated() {
                    expectPoint(
                        vertex.point, groups.takeDouble(10), groups.takeDouble(20),
                        "\(label) vertex \(n)")
                    if hasBulges {
                        expect(near(vertex.bulge, groups.takeDouble(42) ?? .nan), "\(label) bulge")
                    }
                }
            case .edges(let edges):
                expect(!path.isPolyline, "\(label) has edges and the polyline flag")
                expect(groups.takeInt(93) == edges.count, "\(label) edge count")
                for (n, edge) in edges.enumerated() {
                    compare(edge, &groups, "\(label) edge \(n)", &bad)
                }
            }
            expect(groups.takeInt(97) == path.sourceBoundaries.count, "\(label) source count")
            for source in path.sourceBoundaries {
                expect(
                    groups.take(330).flatMap { UInt64($0, radix: 16) } == source,
                    "\(label) source handle \(source)")
            }
        }

        expect(groups.takeInt(75) == hatch.style, "75 style")
        expect(groups.takeInt(76) == hatch.patternType, "76 pattern type")
        if !hatch.isSolid {
            expect(near(degrees(hatch.patternAngle), groups.takeDouble(52) ?? .nan), "52 angle")
            expect(near(hatch.patternScale, groups.takeDouble(41) ?? .nan), "41 scale")
            expect((groups.takeInt(77) == 1) == hatch.isDouble, "77 double")
            expect(groups.takeInt(78) == hatch.patternLines.count, "78 pattern line count")
            for (n, line) in hatch.patternLines.enumerated() {
                let label = "pattern line \(n)"
                expect(near(degrees(line.angle), groups.takeDouble(53) ?? .nan), "\(label) angle")
                expectPoint(line.basePoint, groups.takeDouble(43), groups.takeDouble(44), label)
                expectPoint(line.offset, groups.takeDouble(45), groups.takeDouble(46), label)
                expect(groups.takeInt(79) == line.dashLengths.count, "\(label) dash count")
                for dash in line.dashLengths {
                    expect(near(dash, groups.takeDouble(49) ?? .nan), "\(label) dash")
                }
            }
        }
        if let pixelSize = hatch.pixelSize {
            expect(near(pixelSize, groups.takeDouble(47) ?? .nan), "47 pixel size")
        } else {
            expect(!groups.isNext(47), "47 pixel size is in the DXF only")
        }
        expect(groups.takeInt(98) == hatch.seedPoints.count, "98 seed count")
        for seed in hatch.seedPoints {
            expectPoint(seed, groups.takeDouble(10), groups.takeDouble(20), "seed")
        }

        // The gradient is left out of the DXF for a hatch that has none.
        if let gradient = hatch.gradient, groups.isNext(450) {
            expect(groups.takeInt(450) == (gradient.isEnabled ? 1 : 0), "450")
            expect(groups.takeInt(451) == gradient.reserved, "451")
            expect(near(gradient.angle, groups.takeDouble(460) ?? .nan), "460 angle")
            expect(near(gradient.shift, groups.takeDouble(461) ?? .nan), "461 shift")
            expect((groups.takeInt(452) == 1) == gradient.isSingleColor, "452")
            expect(near(gradient.tint, groups.takeDouble(462) ?? .nan), "462 tint")
            expect(groups.takeInt(453) == gradient.colors.count, "453 colour count")
            for color in gradient.colors {
                expect(near(color.position, groups.takeDouble(463) ?? .nan), "463 position")
                let index = groups.takeInt(63)
                let rgb = groups.takeInt(421)
                switch color.color {
                case .rgb(let red, let green, let blue):
                    expect(
                        rgb == Int(red) << 16 | Int(green) << 8 | Int(blue), "421: \(color.color)")
                case .index(let value):
                    expect(index == value, "63: \(color.color)")
                default:
                    bad.append("gradient colour \(color.color)")
                }
            }
            expect(groups.take(470) == gradient.name, "470 name")
        } else if let gradient = hatch.gradient {
            expect(!gradient.isEnabled, "a gradient the DXF does not have is enabled")
        }
        bad.append(contentsOf: groups.problems)
        return bad
    }

    /// Compares one edge with the groups of the DXF, which are taken from `groups`.
    private static func compare(
        _ edge: HatchEdge, _ groups: inout HatchGroups, _ label: String, _ bad: inout [String]
    ) {
        func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
            if !ok { bad.append("\(label) \(what())") }
        }
        func point(_ x: Int, _ y: Int, _ decoded: DXF.Point2, _ what: String) {
            let a = groups.takeDouble(x) ?? .nan
            let b = groups.takeDouble(y) ?? .nan
            expect(near(decoded.x, a) && near(decoded.y, b), "\(what) \(decoded) vs (\(a), \(b))")
        }
        // The samples hold line edges only. The other edges are compared the way the DXF
        // reference describes them (angles in degrees) and are not exercised by any sample.
        switch edge {
        case .line(let start, let end):
            expect(groups.takeInt(72) == 1, "type")
            point(10, 20, start, "start")
            point(11, 21, end, "end")
        case .circularArc(let center, let radius, let start, let end, let ccw):
            expect(groups.takeInt(72) == 2, "type")
            point(10, 20, center, "centre")
            expect(near(radius, groups.takeDouble(40) ?? .nan), "radius")
            expect(near(degrees(start), groups.takeDouble(50) ?? .nan), "start angle")
            expect(near(degrees(end), groups.takeDouble(51) ?? .nan), "end angle")
            expect((groups.takeInt(73) == 1) == ccw, "counter clockwise")
        case .ellipticArc(let center, let axis, let ratio, let start, let end, let ccw):
            expect(groups.takeInt(72) == 3, "type")
            point(10, 20, center, "centre")
            point(11, 21, axis, "major axis")
            expect(near(ratio, groups.takeDouble(40) ?? .nan), "ratio")
            expect(near(degrees(start), groups.takeDouble(50) ?? .nan), "start angle")
            expect(near(degrees(end), groups.takeDouble(51) ?? .nan), "end angle")
            expect((groups.takeInt(73) == 1) == ccw, "counter clockwise")
        case .spline(let spline):
            expect(groups.takeInt(72) == 4, "type")
            expect(groups.takeInt(94) == spline.degree, "degree")
            expect((groups.takeInt(73) == 1) == spline.isRational, "rational")
            expect((groups.takeInt(74) == 1) == spline.isPeriodic, "periodic")
            expect(groups.takeInt(95) == spline.knots.count, "knot count")
            expect(groups.takeInt(96) == spline.controlPoints.count, "control point count")
            for knot in spline.knots { expect(near(knot, groups.takeDouble(40) ?? .nan), "knot") }
            for (n, control) in spline.controlPoints.enumerated() {
                point(10, 20, control, "control point")
                if spline.isRational {
                    expect(near(spline.weights[n], groups.takeDouble(42) ?? .nan), "weight")
                }
            }
            if groups.isNext(97) {
                expect(groups.takeInt(97) == spline.fitPoints.count, "fit point count")
                for fit in spline.fitPoints { point(11, 21, fit, "fit point") }
                if let start = spline.startTangent { point(12, 22, start, "start tangent") }
                if let end = spline.endTangent { point(13, 23, end, "end tangent") }
            }
        }
    }
}

@Suite("Hatches against AutoCAD's DXF")
struct HatchTests {
    @Test("the committed fixture holds no hatch, and the reader finds none")
    func fixtureHasNone() throws {
        let sample = try #require(try AnnotationSample.all().first)
        #expect(try sample.handles(ofTypes: [ObjectType.hatch]).isEmpty)
        #expect(sample.records(ofType: "HATCH").isEmpty)
    }

    @Test("every hatch of the AutoCAD samples from R2004 to R2018 equals its DXF record")
    func corpus() throws {
        let samples = try AnnotationSample.corpus()
        guard !samples.isEmpty else { return }  // needs DWG_CORPUS: skipped without it
        for sample in samples {
            let result = try HatchOracle.compare(sample)
            #expect(result.compared == 8, "\(sample.name)")
            #expect(result.mismatches.isEmpty, "\(result.mismatches)")
            #expect(result.dwgOnly.isEmpty && result.dxfOnly.isEmpty, "\(sample.name)")
            // Of the shapes a path can have, the samples hold these and no others.
            #expect(
                result.shapes == ["line": 20, "polyline": 3], "\(sample.name) \(result.shapes)")
        }
    }

    @Test("a hatch cut short throws and does not trap")
    func truncation() throws {
        let samples = try AnnotationSample.corpus()
        guard !samples.isEmpty else { return }
        for sample in samples {
            let store = sample.store
            for handle in try sample.handles(ofTypes: [ObjectType.hatch]) {
                let offset = try #require(store.map[handle])
                for length in stride(from: 4, to: 700, by: 5) {
                    let cut = Array(store.objects.prefix(offset + length))
                    var reader = try? ObjectReader(
                        objects: cut, offset: offset, version: store.container.version,
                        textEncoding: store.textEncoding)
                    _ = try? reader?.readHatch()
                }
            }
        }
    }

    @Test("path flags tell a polyline from a derived path")
    func pathFlags() {
        #expect(HatchBoundaryPath(flags: 7).isPolyline)
        #expect(HatchBoundaryPath(flags: 7).isDerived)
        #expect(!HatchBoundaryPath(flags: 1).isPolyline)
        #expect(!HatchBoundaryPath(flags: 1).isDerived)
    }

    // MARK: The DXF text

    /// The groups after group 78 that define the pattern lines (53, 43 to 46, 79 and 49), in
    /// order.
    static func patternGroups(_ record: DXFRecord?) -> [(code: Int, value: Double)] {
        guard let record else { return [] }
        let codes: Set<Int> = [53, 43, 44, 45, 46, 79, 49]
        return record.groups.drop { $0.code != 78 }.dropFirst()
            .filter { codes.contains($0.code) }
            .compactMap { group in Double(group.value).map { (group.code, $0) } }
    }

    @Test("a pattern line is written with its base point in 43 and 44, and its offset in 45 and 46")
    func patternLineGroups() throws {
        let store = try ObjectStore(try Container(try Fixtures.data("BLOCKPOINTPARAMETER.dwg")))
        var emitter = DXFEmitter(try Document(store: store))
        var hatch = HatchData()
        hatch.patternName = "ANSI31"
        hatch.patternLines = [
            HatchPatternLine(
                angle: .pi / 4, basePoint: DXF.Point2(1, 2), offset: DXF.Point2(3, 4),
                dashLengths: [0.5])
        ]
        emitter.write(
            DecodedEntity(common: EntityCommon(handle: 0x99), geometry: .hatch(hatch)),
            space: .model)
        let record = try #require(DXFGroups.records(text: emitter.writer.text)[0x99])
        let groups = Self.patternGroups(record)
        #expect(groups.map(\.code) == [53, 43, 44, 45, 46, 79, 49])
        #expect(groups.map(\.value) == [45, 1, 2, 3, 4, 1, 0.5])
    }

    @Test("the pattern lines in the DXF text are AutoCAD's, from R14 to R2018")
    func patternLinesAgainstAutoCAD() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        // R14 has no DXF of its own; its hatches keep the handles of the R2000 drawing.
        let pairs =
            [("sample_AC1014", "sample_AC1015")]
            + (Fixtures.corpusNamesOther + Fixtures.corpusNames).map { ($0, $0) }
        for (dwg, dxf) in pairs {
            let data = try Data(contentsOf: corpus.appendingPathComponent("\(dwg).dwg"))
            let ours = DXFGroups.records(text: try DWG.dxfText(data: data))
            let theirs = try DXFGroups.records(
                in: corpus.appendingPathComponent("\(dxf)_ascii.dxf")
            ).filter { $0.value.type == "HATCH" }
            #expect(theirs.count == 8, "\(dxf)")
            var lines = 0
            for (handle, record) in theirs {
                let expected = Self.patternGroups(record)
                let written = Self.patternGroups(ours[handle])
                lines += expected.filter { $0.code == 53 }.count
                #expect(
                    ours[handle]?.type == "HATCH" && written.count == expected.count
                        && zip(written, expected).allSatisfy {
                            $0.code == $1.code && EntityOracle.near($0.value, $1.value)
                        },
                    "\(dwg) \(String(handle, radix: 16, uppercase: true))")
            }
            #expect(lines > 0, "\(dxf) has pattern lines")
        }
    }
}
