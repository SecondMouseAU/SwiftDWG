import SwiftDXF
import Testing

@testable import SwiftDWG

@Suite("DXF writer")
struct DXFWriterTests {
    @Test("what is written is read back by SwiftDXF")
    func roundTrip() throws {
        var w = DXFWriter()
        w.beginSection("ENTITIES")
        w.begin("LINE")
        w.handle(5, 0x2C1)
        w.group(8, "Walls")
        w.group(62, 3)
        w.point(10, DXF.Point(1.5, -2.25, 0))
        w.point(11, DXF.Point(100, 1e-7, 3))
        w.begin("CIRCLE")
        w.handle(5, 0x2C2)
        w.group(8, "0")
        w.point(10, DXF.Point(0.1 + 0.2, 0, 0))
        w.group(40, 7.0)
        w.endSection()
        let drawing = try DXF.read(text: w.finish())
        #expect(drawing.entities.count == 2)
        if case .line(let a, let b, let layer, let color) = drawing.entities[0] {
            #expect(a == DXF.Point(1.5, -2.25, 0) && b == DXF.Point(100, 1e-7, 3))
            #expect(layer == "Walls" && color == 3)
        } else {
            Issue.record("the first entity is not a line")
        }
        if case .circle(let c, _, _, _) = drawing.entities[1] {
            // 0.1 + 0.2 survives exactly, because every digit is written.
            #expect(c.x == 0.1 + 0.2)
        } else {
            Issue.record("the second entity is not a circle")
        }
        #expect(drawing.identities.map(\.id) == ["2C1", "2C2"])
    }

    @Test("numbers are written with the digits a reader needs")
    func numbers() {
        #expect(DXFWriter.format(3) == "3.0")
        #expect(DXFWriter.format(-0.5) == "-0.5")
        #expect(DXFWriter.format(1e-7) == "1e-07")
        #expect(DXFWriter.format(.nan) == "0")
        #expect(DXFWriter.format(.infinity) == "0")
    }

    @Test("control characters are written as AutoCAD does, so a value stays on one line")
    func controlCharacters() {
        var w = DXFWriter()
        w.group(1, "two\nlines\tand ^ caret")
        #expect(w.text == "1\ntwo^Jlines^Iand ^  caret\n")
    }
}
