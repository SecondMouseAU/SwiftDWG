import Foundation
import Testing

@testable import SwiftDWG

/// The drawings in `Fixtures/`, and the ones read from a checkout of ACadSharp's `samples/` folder
/// when `DWG_CORPUS` names it.
enum Fixtures {
    static var directory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures")
    }

    static func data(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: directory.appendingPathComponent(name)))
    }

    static var corpus: URL? {
        ProcessInfo.processInfo.environment["DWG_CORPUS"].map { URL(fileURLWithPath: $0) }
    }

    /// The AutoCAD samples of ACadSharp's `samples/` folder that the R2004 and later reader can
    /// open, each as the DWG and AutoCAD's ASCII DXF export of the same drawing.
    static let corpusNames = ["sample_AC1018", "sample_AC1024", "sample_AC1027", "sample_AC1032"]

    /// The R2000 and R2007 samples, which the other two container layouts read.
    ///
    /// Their DXF exports are AutoCAD's too.
    static let corpusNamesOther = ["sample_AC1015", "sample_AC1021"]
}

@Suite("Container")
struct ContainerTests {
    /// The 16 bytes that start the header variables section, and end it, as the format fixes them.
    static let headerStart: [UInt8] = [
        0xCF, 0x7B, 0x1F, 0x23, 0xFD, 0xDE, 0x38, 0xA9, 0x5F, 0x7C, 0x68, 0xB8, 0x4E, 0x6D, 0x33,
        0x5F,
    ]
    static let headerEnd: [UInt8] = [
        0x30, 0x84, 0xE0, 0xDC, 0x02, 0x21, 0xC7, 0x56, 0xA0, 0x83, 0x97, 0x47, 0xB1, 0x92, 0xCC,
        0xA0,
    ]
    static let classesStart: [UInt8] = [
        0x8D, 0xA1, 0xC4, 0xB8, 0xC4, 0xA9, 0xF8, 0xC5, 0xC0, 0xDC, 0xF4, 0x5F, 0xE7, 0xCF, 0xB6,
        0x8A,
    ]
    static let classesEnd: [UInt8] = [
        0x72, 0x5E, 0x3B, 0x47, 0x3B, 0x56, 0x07, 0x3A, 0x3F, 0x23, 0x0B, 0xA0, 0x18, 0x30, 0x49,
        0x75,
    ]

    @Test("an AC1032 file's sections are found, put together, and start with their sentinels")
    func sectionsOfAnAC1032() throws {
        let container = try Container(try Fixtures.data("empty.dwg"))
        #expect(container.version == .ac1032)
        for name in ["AcDb:Header", "AcDb:Classes", "AcDb:Handles", "AcDb:AcDbObjects"] {
            #expect(container.sectionNames.contains(name))
        }
        let header = try #require(try container.section("AcDb:Header"))
        #expect(Array(header.prefix(16)) == Self.headerStart)
        // After the sentinel come the size of the data and, from R2010, four more bytes; the data
        // follows, then its CRC, then the end sentinel.
        let declared = Int(try header.int32(at: 16))
        #expect(Array(header[(24 + declared + 2)..<(24 + declared + 18)]) == Self.headerEnd)

        let classes = try #require(try container.section("AcDb:Classes"))
        #expect(Array(classes.prefix(16)) == Self.classesStart)
        let classesSize = Int(try classes.int32(at: 16))
        #expect(Array(classes[(24 + classesSize + 2)..<(24 + classesSize + 18)]) == Self.classesEnd)

        #expect(try container.section("AcDb:Nothing") == nil)
    }

    @Test("things that are not a readable DWG are refused")
    func refusals() {
        #expect(throws: DWG.Error.notADWG) { _ = try Container([UInt8]("hello world".utf8)) }
        #expect(throws: DWG.Error.notADWG) { _ = try Container([]) }
        #expect(throws: DWG.Error.unsupportedVersion("AC1099")) {
            _ = try Container([UInt8]("AC1099".utf8) + [UInt8](repeating: 0, count: 200))
        }
        // A DWG header cut short does not trap.
        #expect(throws: DWG.Error.self) {
            _ = try Container([UInt8]("AC1032".utf8) + [UInt8](repeating: 0, count: 20))
        }
    }

    @Test("R14, R2000 and R2007 files are read: sections are found, and start with the sentinels")
    func sectionsOfOtherFiles() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS
        let files: [(String, DWG.Version)] = [
            ("sample_AC1014", .ac1014), ("sample_AC1015", .ac1015), ("sample_AC1021", .ac1021),
        ]
        for (name, version) in files {
            let data = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
            let container = try Container(data)
            #expect(container.version == version, "\(name)")
            for section in ["AcDb:Header", "AcDb:Classes", "AcDb:Handles", "AcDb:AcDbObjects"] {
                #expect(container.sectionNames.contains(section), "\(name) \(section)")
            }
            let header = try #require(try container.section("AcDb:Header"))
            #expect(Array(header.prefix(16)) == Self.headerStart, "\(name)")
            let classes = try #require(try container.section("AcDb:Classes"))
            #expect(Array(classes.prefix(16)) == Self.classesStart, "\(name)")
            if version < .ac1021 {
                #expect(Array(classes.suffix(16)) == Self.classesEnd, "\(name)")
            }
        }
    }
}
