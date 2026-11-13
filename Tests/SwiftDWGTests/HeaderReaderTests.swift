import Foundation
import Testing

@testable import SwiftDWG

/// A small deterministic generator, so the damaged inputs are the same on every run.
private struct Generator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
}

/// A header section of a drawing, with what the file header says about it.
private struct HeaderInput {
    var version: DWG.Version
    var maintenanceVersion: Int
    var codePage: Int
    var section: [UInt8]

    init(_ bytes: [UInt8]) throws {
        let container = try Container(bytes)
        version = container.version
        maintenanceVersion = container.maintenanceVersion
        codePage = container.codePage
        section = try #require(try container.section("AcDb:Header"))
    }

    func read(_ section: [UInt8]? = nil) throws -> HeaderVariables {
        try HeaderReader.read(
            section ?? self.section, version: version, maintenanceVersion: maintenanceVersion,
            codePage: codePage)
    }

    /// The offset of the first byte of data in the section, after the sentinel, the size, and from
    /// R2010 the extra four bytes.
    var dataStart: Int { version >= .ac1024 ? 24 : 20 }

    /// The data's size in bytes, as the section declares it.
    var dataSize: Int { Int((try? section.int32(at: 16)) ?? 0) }

    /// A copy cut to `length` bytes, with the sizes in it that count bytes and bits changed to
    /// agree, so that the cut is found while the data is read and not by a check of the size.
    func cut(to length: Int) -> [UInt8] {
        var out = Array(section.prefix(length))
        let data = Swift.max(length - dataStart, 0)
        Self.put(Int32(data), into: &out, at: 16)
        if version >= .ac1021 { Self.put(Int32(data * 8), into: &out, at: dataStart) }
        return out
    }

    private static func put(_ value: Int32, into bytes: inout [UInt8], at offset: Int) {
        guard offset + 4 <= bytes.count else { return }
        for index in 0..<4 {
            bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index))
        }
    }
}

@Suite("Header variables")
struct HeaderReaderTests {
    /// The releases the corpus has AutoCAD's DXF export for, and that the container can read.
    static let corpusReleases = ["AC1018", "AC1024", "AC1027", "AC1032"]

    /// The variables in AutoCAD's DXF that are not in the header section of a DWG: the file header
    /// and the summary hold some, the rest cannot be known from a DWG.
    static let notInHeaderSection: Set<String> = [
        "$ACADVER", "$ACADMAINTVER", "$DWGCODEPAGE", "$LASTSAVEDBY", "$MEASUREMENT",
        // The DWG keeps the creation and the last save as universal time (`$TDUCREATE` and
        // `$TDUUPDATE`). DXF adds the offset of the computer that exported it for these two.
        "$TDCREATE", "$TDUPDATE",
        // Probably the unnamed bit before `$INTERFERECOLOR`, but only evidence of position.
        "$REALWORLDSCALE",
    ]

    private static func input(_ release: String) throws -> (HeaderInput, DXFReference) {
        let corpus = try #require(Fixtures.corpus)
        let bytes = [UInt8](
            try Data(contentsOf: corpus.appendingPathComponent("sample_\(release).dwg")))
        let dxf = try DXFReference(
            contentsOf: corpus.appendingPathComponent("sample_\(release)_ascii.dxf"))
        return (try HeaderInput(bytes), dxf)
    }

    // MARK: Against AutoCAD

    @Test(
        "every variable equals AutoCAD's own DXF export of the drawing",
        .enabled(if: Fixtures.corpus != nil), arguments: corpusReleases)
    func variablesMatchDXF(release: String) throws {
        let (input, dxf) = try Self.input(release)
        let header = try input.read()
        let oracle = HeaderOracle(dxf: dxf, release: release)
        #expect(dxf.header["$ACADVER"]?.first?.value == release)

        var matched = 0
        var bounded = [String: String]()
        var notCompared = [String: String]()
        for (name, value) in header.values where dxf.header[name] != nil {
            switch oracle.compare(name, value) {
            case .matched: matched += 1
            case .bounded(let why): bounded[name] = why
            case .notCompared(let why): notCompared[name] = why
            case .differs(let how): Issue.record("\(release) \(name): \(how)")
            }
        }
        let dxfOnly = Set(dxf.header.keys).subtracting(header.values.keys)
        #expect(dxfOnly.subtracting(Self.notInHeaderSection).isEmpty, "\(release): \(dxfOnly)")
        let dwgOnly = Set(header.values.keys).subtracting(dxf.header.keys)

        var pointersMatched = 0
        var pointersNotCompared = [String: String]()
        let pointers = header.handles.filter { HeaderReader.Parser.variableNames[$0.key] == nil }
        for (name, handle) in pointers {
            switch oracle.compare(pointer: name, handle) {
            case .matched: pointersMatched += 1
            case .notCompared(let why): pointersNotCompared[name] = why
            case .bounded, .differs: Issue.record("\(release) \(name): \(handle) is not in the DXF")
            }
        }

        let compared = matched + bounded.count + notCompared.count
        print(
            "header \(release): \(matched) of \(compared) variables equal AutoCAD's, "
                + "\(bounded.count) bounded, \(notCompared.count) not compared; "
                + "\(pointersMatched) of \(pointers.count) other handles equal, "
                + "DXF only: \(dxfOnly.sorted()), DWG only: \(dwgOnly.count)")
        print("  bounded: \(bounded.sorted { $0.key < $1.key })")
        print("  not compared: \(notCompared.sorted { $0.key < $1.key })")
        print("  handles not compared: \(pointersNotCompared.sorted { $0.key < $1.key })")
        print("  DWG only: \(dwgOnly.sorted())")

        #expect(matched >= 150, "\(release): only \(matched) variables equal")
        #expect(pointersMatched >= 20)
        // What cannot be compared is known, and listed here so that a new gap shows.
        let expectedNotCompared: Set<String> = ["$CECOLOR", "$VERSIONGUID", "$XCLIPFRAME"]
        #expect(Set(notCompared.keys).isSubset(of: expectedNotCompared), "\(notCompared)")
        #expect(Set(bounded.keys) == ["$HANDSEED", "$TDUUPDATE", "$TDINDWG", "$TDUSRTIMER"])
    }

    @Test(
        "the visual style dictionary keeps its handle, and R2013's extra handle is read after it",
        .enabled(if: Fixtures.corpus != nil), arguments: ["AC1027", "AC1032"])
    func visualStyleDictionaryAndTheExtraHandle(release: String) throws {
        let (input, dxf) = try Self.input(release)
        let header = try input.read()
        // ACadSharp stores both over the same name, so what it keeps is the second, which is null
        // in these drawings, and the dictionary's handle is lost.
        #expect(header.handles["UNKNOWN_R2013"] != nil)
        #expect(header.handles["DICTIONARY_VISUALSTYLE"] == dxf.rootEntries["ACAD_VISUALSTYLE"])
        #expect(header.handles["DICTIONARY_VISUALSTYLE"] != 0)
    }

    @Test(
        "text is decoded from the string stream of R2007 and later, and the single-byte text before",
        .enabled(if: Fixtures.corpus != nil), arguments: corpusReleases)
    func textComesBack(release: String) throws {
        let (input, dxf) = try Self.input(release)
        let header = try input.read()
        #expect(header.string("$MENU") == ".")
        #expect(header.string("$FINGERPRINTGUID") == dxf.header["$FINGERPRINTGUID"]?.first?.value)
        #expect(header.string("$DIMPOST") == "")
    }

    @Test(
        "the header is cut short at every length and never trapped on",
        .enabled(if: Fixtures.corpus != nil), arguments: corpusReleases)
    func truncatedCorpusHeaders(release: String) throws {
        let (input, _) = try Self.input(release)
        try expectEveryCutThrows(input)
    }

    // MARK: Without the corpus

    @Test("the committed AC1032 file's header is read, and its handles agree with each other")
    func emptyDrawing() throws {
        let input = try HeaderInput(try Fixtures.data("empty.dwg"))
        #expect(input.version == .ac1032)
        let header = try input.read()
        #expect(header.values.count > 200)
        #expect(header.handles.count >= 40)

        // The control objects are different, real objects.
        let controls = HeaderOracle.controlObjects.keys.compactMap { header.handles[$0] }
        #expect(controls.count == HeaderOracle.controlObjects.count)
        #expect(controls.allSatisfy { $0 != 0 })
        #expect(Set(controls).count == controls.count)
        // The next handle is above every handle the header names.
        if let seed = header.handle("$HANDSEED") {
            #expect(seed > (header.handles.values.max() ?? 0))
        }
        // The current layer is the one the header says it is, by either name.
        #expect(header.handle("$CLAYER") == header.handles["CLAYER"])
        // The extents, a variable of each shape.
        #expect(header.point3("$EXTMIN") != nil)
        #expect(header.point2("$LIMMAX") != nil)
        #expect(header.double("$LTSCALE") != nil)
        #expect(header.int("$INSUNITS") != nil)
        #expect(header.string("$MENU") != nil)
    }

    @Test("a header cut short at every length throws and does not trap")
    func truncatedEmptyDrawing() throws {
        try expectEveryCutThrows(try HeaderInput(try Fixtures.data("empty.dwg")))
    }

    /// Cuts the section at every length, ascending: every cut that is too short is refused, and the
    /// first that is long enough reads the same as the whole section, with the padding gone.
    private func expectEveryCutThrows(_ input: HeaderInput) throws {
        let whole = try input.read()
        let end = input.dataStart + input.dataSize
        var needed = end
        for length in 0..<end {
            do {
                let header = try input.read(input.cut(to: length))
                #expect(header == whole, "cut to \(length) bytes reads differently")
                needed = length
                break
            } catch is DWG.Error {
                continue
            } catch {
                Issue.record("cut to \(length): \(error)")
            }
        }
        // All the data is needed but for the padding at the end.
        #expect(needed > end - 16 && needed <= end, "first long enough cut: \(needed) of \(end)")
    }

    @Test("a header with damaged bytes and sizes is read or refused, and never trapped on")
    func damagedHeaders() throws {
        let input = try HeaderInput(try Fixtures.data("empty.dwg"))
        var random = Generator(state: 0x9E37_79B9_7F4A_7C15)
        for _ in 0..<1500 {
            var section = input.section
            for _ in 0...random.below(4) {
                section[16 + random.below(section.count - 16)] = UInt8(
                    truncatingIfNeeded: random.next())
            }
            expectNoTrap(input, section)
        }
        // Sizes that are absurd.
        for size in [Int32.min, -1, 0, 1, 0x7FFF_FFFF] {
            for offset in [16, input.dataStart] {
                var section = input.section
                for index in 0..<4 {
                    section[offset + index] = UInt8(truncatingIfNeeded: size >> (8 * index))
                }
                expectNoTrap(input, section)
            }
        }
    }

    @Test("the releases before R2004 and R2007's own, which no file reaches yet, do not trap")
    func olderReleasesDoNotTrap() {
        var random = Generator(state: 0xD1B5_4A32_D192_ED03)
        for version in [DWG.Version.ac1012, .ac1014, .ac1015, .ac1018, .ac1021, .ac1024] {
            for _ in 0..<400 {
                let payload = (0..<random.below(900)).map { _ in
                    UInt8(truncatingIfNeeded: random.next())
                }
                var section = HeaderReader.startSentinel
                let size = Int32(payload.count + random.below(40))
                section += (0..<4).map { UInt8(truncatingIfNeeded: size >> (8 * $0)) }
                section += payload
                do {
                    _ = try HeaderReader.read(
                        section, version: version, maintenanceVersion: 0, codePage: 30)
                } catch is DWG.Error {
                } catch {
                    Issue.record("\(version.code): \(error)")
                }
            }
        }
    }

    @Test(
        "a section that does not start with its sentinel, and releases it cannot read, are refused")
    func refusals() throws {
        let input = try HeaderInput(try Fixtures.data("empty.dwg"))
        var wrong = input.section
        wrong[0] ^= 0xFF
        #expect(throws: DWG.Error.self) { _ = try input.read(wrong) }
        #expect(throws: DWG.Error.self) { _ = try input.read([]) }
        #expect(throws: DWG.Error.unsupportedVersion("AC1009")) {
            _ = try HeaderReader.read(
                input.section, version: .ac1009, maintenanceVersion: 0, codePage: 30)
        }
        #expect(throws: DWG.Error.unsupportedVersion("AC1006")) {
            _ = try HeaderReader.read(
                input.section, version: .ac1006, maintenanceVersion: 0, codePage: 30)
        }
    }

    @Test("the typed accessors give a variable as the type it has, and nil otherwise")
    func accessors() {
        var header = HeaderVariables()
        header.values = [
            "$A": .int(3), "$B": .double(1.5), "$C": .string("x"), "$D": .bool(true),
            "$E": .point2(x: 1, y: 2), "$F": .point3(x: 1, y: 2, z: 3), "$G": .handle(0x2A),
            "$H": .color(index: 7, rgb: nil),
        ]
        #expect(header.int("$A") == 3)
        #expect(header.int("$D") == 1)
        #expect(header.int("$H") == 7)
        #expect(header.double("$B") == 1.5)
        #expect(header.string("$C") == "x")
        #expect(header.bool("$D") == true)
        #expect(header.point2("$E")?.y == 2)
        #expect(header.point3("$F")?.z == 3)
        #expect(header.handle("$G") == 0x2A)
        #expect(header.int("$B") == nil)
        #expect(header.double("$A") == nil)
        #expect(header.string("$A") == nil)
        #expect(header.point3("$E") == nil)
        #expect(header.handle("$missing") == nil)
    }

    @Test("a code page number gives its encoding, and an unlisted one gives none")
    func codePages() {
        #expect(CodePage.encoding(for: 30) == .windowsCP1252)
        #expect(CodePage.encoding(for: 29) == .windowsCP1251)
        #expect(CodePage.encoding(for: 2) == .isoLatin1)
        #expect(CodePage.encoding(for: 0) == nil)
        #expect(CodePage.encoding(for: 999) == nil)
        #expect(CodePage.encoding(for: -1) == nil)
    }

    @Test("line weight indexes become the hundredths of a millimetre, or the codes DXF uses")
    func lineWeights() {
        #expect(HeaderReader.Parser.lineWeight(index: 0) == 0)
        #expect(HeaderReader.Parser.lineWeight(index: 7) == 25)
        #expect(HeaderReader.Parser.lineWeight(index: 23) == 211)
        #expect(HeaderReader.Parser.lineWeight(index: 29) == -1)
        #expect(HeaderReader.Parser.lineWeight(index: 30) == -2)
        #expect(HeaderReader.Parser.lineWeight(index: 31) == -3)
        #expect(HeaderReader.Parser.lineWeight(index: 25) == -3)
    }

    /// Reads damaged bytes, which may be read or refused with a `DWG.Error` and nothing else.
    private func expectNoTrap(_ input: HeaderInput, _ section: [UInt8]) {
        do {
            _ = try input.read(section)
        } catch is DWG.Error {
        } catch {
            Issue.record("\(error)")
        }
    }
}
