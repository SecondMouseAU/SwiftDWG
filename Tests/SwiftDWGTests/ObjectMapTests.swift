import Foundation
import Testing

@testable import SwiftDWG

@Suite("Classes and object map")
struct ObjectMapTests {
    @Test("the classes of an AutoCAD drawing are read, with the names that make them known")
    func classes() throws {
        let container = try Container(try Fixtures.data("empty.dwg"))
        let section = try #require(try container.section("AcDb:Classes"))
        let classes = try ClassesReader.read(
            section, version: container.version, maintenanceVersion: container.maintenanceVersion,
            textEncoding: .windowsCP1252)
        #expect(!classes.isEmpty)
        // Custom classes are numbered from 500.
        #expect(classes.keys.allSatisfy { $0 >= 500 })
        #expect(classes.values.contains { $0.dxfName == "ACDBDICTIONARYWDFLT" })
        #expect(classes.values.allSatisfy { !$0.dxfName.isEmpty && !$0.cppClassName.isEmpty })
    }

    @Test("the object map gives every object a distinct place inside the objects section")
    func objectMap() throws {
        let container = try Container(try Fixtures.data("empty.dwg"))
        let section = try #require(try container.section("AcDb:Handles"))
        let map = try ObjectMapReader.read(section, version: container.version)
        let objects = try #require(try container.section("AcDb:AcDbObjects"))
        #expect(map.count > 20)
        #expect(map.values.allSatisfy { $0 >= 0 && $0 < objects.count })
        #expect(Set(map.values).count == map.count)
    }

    @Test("a truncated map throws or ends cleanly, never traps")
    func truncated() throws {
        #expect(throws: DWG.Error.self) {
            _ = try ObjectMapReader.read([0x00, 0x20, 0x01], version: .ac1032)
        }
        #expect(try ObjectMapReader.read([0x00, 0x02], version: .ac1032).isEmpty)
        #expect(try ObjectMapReader.read([], version: .ac1032).isEmpty)
    }
}
