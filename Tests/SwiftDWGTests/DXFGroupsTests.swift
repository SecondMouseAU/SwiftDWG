import Foundation
import Testing

@Suite("DXF groups helper")
struct DXFGroupsTests {
    @Test("records are keyed by handle and carry their groups")
    func records() throws {
        let url = Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dxf")
        let records = try DXFGroups.records(in: url)
        #expect(records.count > 50)
        let lines = records.values.filter { $0.type == "LINE" }
        #expect(lines.count == 2)
        for line in lines {
            #expect(line.point(10, 20, 30) != nil)
            #expect(line.point(11, 21, 31) != nil)
            #expect(line.first(8) != nil)
        }
        #expect(records.values.contains { $0.type == "LAYER" })
    }
}
