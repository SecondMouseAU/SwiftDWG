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

@Suite("Header variables")
struct HeaderReaderTests {
    /// The releases of the corpus that have a DXF export, and that the container can read.
    static let corpusReleases = ["AC1015", "AC1018", "AC1021", "AC1024", "AC1027", "AC1032"]

    /// Every release of the corpus that has a header to read, which adds AC1014 (no DXF export).
    static let readableReleases = ["AC1014"] + corpusReleases

    @Test(
        "text is decoded from the string stream of R2007 and later, and the single-byte text before",
        .enabled(if: Fixtures.corpus != nil), arguments: corpusReleases)
    func textComesBack(release: String) throws {
        let (input, dxf) = try HeaderInput.corpus(release)
        let header = try input.read()
        #expect(header.string("$MENU") == ".")
        #expect(
            header.string("$FINGERPRINTGUID") == dxf?.header["$FINGERPRINTGUID"]?.first?.value)
        #expect(header.string("$DIMPOST") == "")
    }

    @Test(
        "the header is cut short at every length and never trapped on",
        .enabled(if: Fixtures.corpus != nil), arguments: readableReleases)
    func truncatedCorpusHeaders(release: String) throws {
        let (input, _) = try HeaderInput.corpus(release, withDXF: false)
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

    @Test("random sections read as each release from R13 are read or refused, and never trapped on")
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
