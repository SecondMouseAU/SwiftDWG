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

    @Test("a section map cut off inside a section record throws instead of trapping")
    func truncatedSectionMap() {
        // 48 bytes hold the section count and the first fields of one record, but not its name,
        // which starts at byte 52.
        var sectionMap = [UInt8](repeating: 0, count: 48)
        sectionMap[0] = 1
        #expect(throws: DWG.Error.truncated("a section name")) {
            _ = try Container(Self.r2004File(sectionMap: sectionMap))
        }
    }

    @Test("a section with a negative page size is refused instead of trapping")
    func negativePageSize() {
        // One record in full, 96 bytes after the 20 that precede it, with a page size of -1.
        var sectionMap = [UInt8](repeating: 0, count: 20 + 96)
        sectionMap[0] = 1
        sectionMap.replaceSubrange(32..<36, with: [0xFF, 0xFF, 0xFF, 0xFF])
        #expect(throws: DWG.Error.self) {
            _ = try Container(Self.r2004File(sectionMap: sectionMap))
        }
    }

    /// A section map with one section of `size` bytes in pages of `pageSize`, and `pages` records
    /// for pages, each with a page number and the offset it starts at.
    private static func sectionMap(size: UInt64, pageSize: Int32, pages: [UInt64]) -> [UInt8] {
        func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
            (0..<(T.bitWidth / 8)).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
        }
        var map = [UInt8](repeating: 0, count: 20 + 96)
        map.replaceSubrange(0..<4, with: bytes(Int32(1)))
        map.replaceSubrange(20..<28, with: bytes(size))
        map.replaceSubrange(28..<32, with: bytes(Int32(pages.count)))
        map.replaceSubrange(32..<36, with: bytes(pageSize))
        map.replaceSubrange(52..<53, with: [UInt8(ascii: "S")])
        for offset in pages {
            map += bytes(Int32(1)) + bytes(Int32(0)) + bytes(offset)
        }
        return map
    }

    @Test(
        "a page that starts far past the end of its section is refused, and does not fill the gap",
        .timeLimit(.minutes(1)))
    func pageOffsetPastTheSection() {
        // Before it was bounded, the gap before this page was filled one page at a time: some
        // 4.7 billion of them.
        let map = Self.sectionMap(size: 0x7400, pageSize: 0x7400, pages: [0x7FFF_FFFF_FFFF])
        #expect(throws: DWG.Error.invalid("a page of section S is past its end")) {
            _ = try Container(Self.r2004File(sectionMap: map))
        }
    }

    @Test(
        "a section of more pages than the limit is refused, so a tiny page size cannot take the memory",
        .timeLimit(.minutes(1)))
    func tooManyPages() {
        // 2 GiB in pages of one byte would be two billion pages.
        let map = Self.sectionMap(size: 1 << 31, pageSize: 1, pages: [])
        #expect(throws: DWG.Error.invalid("section S has too many pages")) {
            _ = try Container(Self.r2004File(sectionMap: map))
        }
    }

    /// The smallest file the R2004 reader gets as far as the section map with: the file header, a
    /// page map that names one page, and that page holding `sectionMap`.
    ///
    /// The two system pages are stored as an LZ77 stream of literals only.
    static func r2004File(sectionMap: [UInt8]) -> [UInt8] {
        var file = [UInt8](repeating: 0, count: 0x400)
        func put(_ bytes: [UInt8], at offset: Int) {
            file.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
        }
        func int32(_ value: Int) -> [UInt8] {
            (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
        }
        func systemPage(_ content: [UInt8], at address: Int) {
            put(int32(content.count), at: address + 4)
            // A first byte above 0x11 is a run of literals, 17 fewer than the byte; 0x11 ends it.
            put([UInt8(17 + content.count)] + content + [0x11], at: address + 20)
        }

        put([UInt8]("AC1032".utf8), at: 0)
        // The header at 0x80 is XORed with a congruential sequence, which the same pass undoes.
        var header = [UInt8](repeating: 0, count: 0x6C)
        header.replaceSubrange(0..<11, with: [UInt8]("AcFssFcAJMB".utf8))
        header.replaceSubrange(0x54..<0x5C, with: int32(0x200) + int32(0))
        header.replaceSubrange(0x5C..<0x60, with: int32(1))
        var seed: Int32 = 1
        put(
            header.map { byte in
                seed = seed &* 0x343FD &+ 0x269EC3
                return byte ^ UInt8(truncatingIfNeeded: seed >> 16)
            }, at: 0x80)

        // Page 1 starts at 0x100 and is 0x200 long; the page map itself is at 0x300.
        systemPage(int32(1) + int32(0x200), at: 0x300)
        systemPage(sectionMap, at: 0x100)
        return file
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
