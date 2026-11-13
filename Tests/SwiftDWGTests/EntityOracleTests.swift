import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// Entities read from a DWG, compared with the ones in AutoCAD's own DXF export of the drawing.
///
/// The expected values are read from the DXF by SwiftDXF, which is validated against ezdxf, so
/// nothing here is checked against SwiftDWG's own output.
enum EntityOracle {
    struct Result {
        var compared = 0
        var mismatches: [String] = []
        var dwgOnly: [UInt64] = []
        var dxfOnly: [UInt64] = []
    }

    /// Every modelled entity of a DXF drawing, model space and blocks, by handle.
    static func entities(of drawing: DXF.Drawing) -> [UInt64: DXF.Entity] {
        var out: [UInt64: DXF.Entity] = [:]
        func add(_ entities: [DXF.Entity], _ identities: [DXF.Identity]) {
            guard entities.count == identities.count else { return }
            for (entity, identity) in zip(entities, identities) {
                if let text = identity.handle, let handle = UInt64(text, radix: 16) {
                    out[handle] = entity
                }
            }
        }
        add(drawing.entities, drawing.identities)
        for block in drawing.blocks { add(block.entities, block.identities) }
        return out
    }

    static func near(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= 1e-9 * max(1, abs(b))
    }

    static func near(_ a: DXF.Point, _ b: DXF.Point) -> Bool {
        near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z)
    }

    /// Compares the decoded line, circle, arc and point entities with the DXF's.
    static func compare(_ store: ObjectStore, with drawing: DXF.Drawing) throws -> Result {
        let expected = entities(of: drawing)
        var result = Result()
        var seen = Set<UInt64>()
        for handle in store.handles {
            let decoded: DecodedEntity?
            do { decoded = try store.entity(handle) } catch is NotDecodedYet { continue }
            guard let decoded else { continue }
            seen.insert(handle)
            guard let reference = expected[handle] else {
                result.dwgOnly.append(handle)
                continue
            }
            result.compared += 1
            var ok = false
            switch (decoded.geometry, reference) {
            case (.line(let a, let b, _, _), .line(let ra, let rb, _, _)):
                ok = near(a, ra) && near(b, rb)
            case (.circle(let c, let r, _, _), .circle(let rc, let rr, _, _)):
                ok = near(c, rc) && near(r, rr)
            case (
                .arc(let c, let r, _, _, let s, let e), .arc(let rc, let rr, let rs, let re, _, _)
            ):
                ok =
                    near(c, rc) && near(r, rr) && near(s * 180 / .pi, rs) && near(e * 180 / .pi, re)
            case (.point(let p, _, _, _), .point(let rp, _, _)):
                ok = near(p, rp)
            default:
                ok = false
            }
            if !ok { result.mismatches.append(String(handle, radix: 16, uppercase: true)) }
        }
        for (handle, entity) in expected where !seen.contains(handle) {
            switch entity {
            case .line, .circle, .arc, .point: result.dxfOnly.append(handle)
            default: break
            }
        }
        return result
    }
}

@Suite("Entities against AutoCAD's DXF")
struct EntityOracleTests {
    @Test("lines and circles of an AutoCAD drawing equal those in its DXF export")
    func smallDrawing() throws {
        let container = try Container(try Fixtures.data("BLOCKPOINTPARAMETER.dwg"))
        let store = try ObjectStore(container)
        let drawing = try DXF.read(
            contentsOf: Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dxf"))
        let result = try EntityOracle.compare(store, with: drawing)
        #expect(result.compared >= 3)
        #expect(result.mismatches.isEmpty)
        #expect(result.dwgOnly.isEmpty)
        #expect(result.dxfOnly.isEmpty)
    }

    @Test("every AutoCAD sample from R2004 to R2018 reads to the entities its DXF has")
    func corpus() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        for name in ["sample_AC1018", "sample_AC1024", "sample_AC1027", "sample_AC1032"] {
            let data = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
            let store = try ObjectStore(try Container(data))
            let drawing = try DXF.read(
                contentsOf: corpus.appendingPathComponent("\(name)_ascii.dxf"))
            let result = try EntityOracle.compare(store, with: drawing)
            #expect(result.compared == 154, "\(name)")
            #expect(result.mismatches.isEmpty, "\(name)")
            #expect(result.dwgOnly.isEmpty && result.dxfOnly.isEmpty, "\(name)")
        }
    }

    @Test("the R2000 sample reads to the entities its DXF has")
    func corpusR2000() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS
        for name in Fixtures.corpusNamesR2000 {
            let data = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
            let store = try ObjectStore(try Container(data))
            let drawing = try DXF.read(
                contentsOf: corpus.appendingPathComponent("\(name)_ascii.dxf"))
            let result = try EntityOracle.compare(store, with: drawing)
            #expect(result.compared == 154, "\(name)")
            #expect(result.mismatches.isEmpty, "\(name)")
            #expect(result.dwgOnly.isEmpty && result.dxfOnly.isEmpty, "\(name)")
        }
    }

    @Test("the R14 sample has the same lines, circles, arcs and points as the R2000 DXF")
    func corpusR14() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS
        // There is no DXF of the R14 file. It is the same drawing as the R2000 one, so the
        // geometry is compared as a set, since the two saves do not share handles.
        let data = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("sample_AC1014.dwg")))
        let store = try ObjectStore(try Container(data))
        let drawing = try DXF.read(
            contentsOf: corpus.appendingPathComponent("sample_AC1015_ascii.dxf"))
        func signature(_ a: [Double]) -> String {
            a.map { String(format: "%.6f", $0) }.joined(separator: " ")
        }
        var ours: [String] = []
        for handle in store.handles {
            let decoded: DecodedEntity?
            do { decoded = try store.entity(handle) } catch is NotDecodedYet { continue }
            guard let entity = decoded else { continue }
            switch entity.geometry {
            case .line(let a, let b, _, _):
                ours.append("L " + signature([a.x, a.y, a.z, b.x, b.y, b.z]))
            case .circle(let c, let r, _, _): ours.append("C " + signature([c.x, c.y, c.z, r]))
            case .arc(let c, let r, _, _, let s, let e):
                ours.append("A " + signature([c.x, c.y, c.z, r, s * 180 / .pi, e * 180 / .pi]))
            case .point(let p, _, _, _): ours.append("P " + signature([p.x, p.y, p.z]))
            default: continue
            }
        }
        var theirs: [String] = []
        for entity in EntityOracle.entities(of: drawing).values {
            switch entity {
            case .line(let a, let b, _, _):
                theirs.append("L " + signature([a.x, a.y, a.z, b.x, b.y, b.z]))
            case .circle(let c, let r, _, _): theirs.append("C " + signature([c.x, c.y, c.z, r]))
            case .arc(let c, let r, let s, let e, _, _):
                theirs.append("A " + signature([c.x, c.y, c.z, r, s, e]))
            case .point(let p, _, _): theirs.append("P " + signature([p.x, p.y, p.z]))
            default: continue
            }
        }
        #expect(ours.count == 154)
        #expect(ours.sorted() == theirs.sorted())
    }
}
