import Foundation
import Testing

@testable import SwiftDWG

/// The HEADER section of `DWG.dxfText` against the HEADER section of AutoCAD's own DXF export of
/// the same drawing: the same variables, in the same order, with the same group codes and values.
@Suite("Header variables in the DXF text")
struct HeaderTextTests {
    // MARK: What is not written, and why

    /// Variables `HeaderReader` decodes and the DXF text does not carry.
    ///
    /// Each is in the README.
    static let decodedNotWritten: [String: String] = [
        "$FACETRES": "AutoCAD keeps it in the registry: its DXF of every sample omits it",
        "$ISOLINES": "AutoCAD keeps it in the registry: its DXF of every sample omits it",
        "$PELLIPSE": "AutoCAD keeps it in the registry: its DXF of every sample omits it",
        "$TEXTQLTY": "AutoCAD keeps it in the registry: its DXF of every sample omits it",
        "$TSTACKALIGN": "AutoCAD keeps it in the registry: its DXF of every sample omits it",
        "$TSTACKSIZE": "AutoCAD keeps it in the registry: its DXF of every sample omits it",
        "$DIMALTMZF": "a dimension style variable, which DXF has only in the DIMSTYLE table",
        "$DIMALTMZS": "a dimension style variable, which DXF has only in the DIMSTYLE table",
        "$DIMMZF": "a dimension style variable, which DXF has only in the DIMSTYLE table",
        "$DIMMZS": "a dimension style variable, which DXF has only in the DIMSTYLE table",
        "$DRAGVS": "null in every sample, which AutoCAD's DXF omits, and no sample has it set",
        "$DIMFIT": "R14 only, and there is no AutoCAD DXF of an R14 drawing to show it is written",
        "$DIMUNIT": "R14 only, and there is no AutoCAD DXF of an R14 drawing to show it is written",
        "$DIMSAV": "R14 only, and there is no AutoCAD DXF of an R14 drawing to show it is written",
        "$DELOBJ": "R14 only, and there is no AutoCAD DXF of an R14 drawing to show it is written",
        "$PICKSTYLE":
            "R14 only, and there is no AutoCAD DXF of an R14 drawing to show it is written",
    ]

    /// Variables AutoCAD's DXF has that the header section of a DWG does not.
    static let notInTheHeaderSection: [String: String] = [
        "$ACADMAINTVER": "the file header's byte equals it in 4 of 6 samples, so it is not derived",
        "$LASTSAVEDBY": "kept in the summary information section, which is not read",
        "$TDCREATE":
            "from R2000 the DWG has the universal time only, and DXF adds the local offset",
        "$TDUPDATE":
            "from R2000 the DWG has the universal time only, and DXF adds the local offset",
        "$REALWORLDSCALE":
            "an unexplained bit in the DWG, 1 in every sample, so it is not told apart",
    ]

    /// Variables the DWG header may hold as a null handle, where AutoCAD's DXF names its default.
    static let defaultedPointers: Set<String> = ["$INTERFEREOBJVS", "$INTERFEREVPVS"]

    // MARK: Comparison

    enum Outcome: Equatable {
        /// The same text.
        case equal
        /// The same number to the digits DXF prints.
        case close
        /// A difference the text states and the test allows.
        case bounded(String)
        case differs(String)

        var rank: Int {
            switch self {
            case .equal: return 0
            case .close: return 1
            case .bounded: return 2
            case .differs: return 3
            }
        }
    }

    /// The dates and lengths of time, which DXF prints to 9 or 10 decimals of a day.
    static let times: Set<String> = [
        "$TDCREATE", "$TDUCREATE", "$TDUPDATE", "$TDUUPDATE", "$TDINDWG", "$TDUSRTIMER",
    ]

    /// The ones a save moves on: AutoCAD exported the DXF a second or so after the DWG.
    static let movedBySaving: Set<String> = ["$TDUPDATE", "$TDUUPDATE", "$TDINDWG", "$TDUSRTIMER"]

    /// Half a unit in the last place AutoCAD prints, for a time: 5e-10 of a day, rounded up.
    static let timeTolerance = 1e-9

    /// The relative tolerance for a real that DXF prints with 16 significant digits.
    ///
    /// The number AutoCAD prints is within half a unit of the 16th digit, which is at most 5e-16
    /// of its size. The double the DWG holds can differ from the printed one by that much and no
    /// more, so 1e-15 allows that and nothing else.
    static let relativeTolerance = 1e-15

    static func compare(
        _ name: String, ours: [DXFReference.Tag], theirs: [DXFReference.Tag],
        decoded: HeaderVariables
    ) -> Outcome {
        guard ours.map(\.code) == theirs.map(\.code) else {
            return .differs("group codes \(ours.map(\.code)) against \(theirs.map(\.code))")
        }
        var result = Outcome.equal
        for (mine, other) in zip(ours, theirs) {
            let one = compare(name, code: mine.code, mine.value, other.value, decoded: decoded)
            if one.rank > result.rank { result = one }
        }
        return result
    }

    private static func compare(
        _ name: String, code: Int, _ mine: String, _ other: String, decoded: HeaderVariables
    ) -> Outcome {
        let ours = mine.trimmingCharacters(in: .whitespaces)
        let theirs = other.trimmingCharacters(in: .whitespaces)
        if ours == theirs { return .equal }
        switch name {
        case "$VERSIONGUID":
            // AutoCAD makes a new version GUID at each save, so the DXF has another one.
            return isGUID(ours)
                ? .bounded("a new GUID at each save") : .differs("\(ours) is not a GUID")
        case "$HANDSEED":
            // The DXF came from the drawing after the DWG was saved, and more handles are in use.
            guard let read = UInt64(ours, radix: 16), let expected = UInt64(theirs, radix: 16)
            else { return .differs("\(ours) against \(theirs)") }
            return read <= expected
                ? .bounded("the DXF seed is higher") : .differs("\(ours) above \(theirs)")
        case "$CECOLOR":
            // DXF has no place for a true colour and writes the palette index AutoCAD picked for
            // it, which is not always the one nearest in RGB, as this is.
            if case .color(_, let rgb?)? = decoded.values[name], let index = Int(ours),
                index
                    == ColorIndex.nearest(
                        red: UInt8(rgb >> 16 & 0xFF), green: UInt8(rgb >> 8 & 0xFF),
                        blue: UInt8(rgb & 0xFF))
            {
                return .bounded("a true colour: the nearest index is \(ours), AutoCAD's \(theirs)")
            }
            return .differs("\(ours) against \(theirs)")
        default:
            break
        }
        guard (10...59).contains(code), let read = Double(ours), let expected = Double(theirs)
        else { return .differs("\(ours) against \(theirs)") }
        if times.contains(name) {
            let delta = expected - read
            if abs(delta) <= timeTolerance { return .close }
            if movedBySaving.contains(name), delta > 0, delta <= 5.0 / 86_400.0 {
                return .bounded("the DXF is \(String(format: "%.1f", delta * 86_400)) s later")
            }
            return .differs("\(ours) against \(theirs)")
        }
        if abs(read - expected) <= relativeTolerance * max(abs(read), abs(expected)) {
            return .close
        }
        return .differs("\(ours) against \(theirs)")
    }

    private static func isGUID(_ text: String) -> Bool {
        let parts = text.dropFirst().dropLast().split(
            separator: "-", omittingEmptySubsequences: false)
        return text.hasPrefix("{") && text.hasSuffix("}") && parts.map(\.count) == [8, 4, 4, 4, 12]
            && parts.allSatisfy { $0.allSatisfy(\.isHexDigit) }
    }

    /// Variables whose value is allowed to differ in the way `compare` states, whatever the drawing.
    static let allowedToBeBounded: Set<String> = [
        "$HANDSEED", "$VERSIONGUID", "$CECOLOR", "$TDUUPDATE", "$TDINDWG", "$TDUSRTIMER",
    ]

    // MARK: Drawings

    /// A drawing and AutoCAD's DXF export of it.
    struct Pair: Sendable, CustomTestStringConvertible {
        var dwg: String
        var dxf: String
        /// Whether the DXF is AutoCAD's export of the same save of the drawing.
        ///
        /// `save_samples.lsp` made that for the `sample_<release>` files. The others were
        /// exported from a copy that had been edited or saved again, so what an edit changes
        /// differs.
        var sameSave: Bool
        var testDescription: String { dwg }
    }

    /// What an edit or a save changes, and so what may differ where the DXF is of another save.
    ///
    /// They are the extents, the times, the next handle and the drawing's GUID. Every other
    /// variable is compared as for the others.
    static let editedBetweenSaves: Set<String> = [
        "$EXTMIN", "$EXTMAX", "$FINGERPRINTGUID", "$TDUCREATE", "$TDUUPDATE", "$TDINDWG",
        "$TDUSRTIMER", "$HANDSEED",
    ]

    /// The `sample_<release>` drawings, which are the same drawing saved as each release.
    static let releases = ["AC1015", "AC1018", "AC1021", "AC1024", "AC1027", "AC1032"]

    static let dynamicBlocks = [
        "BLOCKALIGNMENTPARAMETER", "BLOCKBASEPOINTPARAMETER", "BLOCKFLIPPARAMETER",
        "BLOCKLINEARPARAMETER", "BLOCKLOOKUPPARAMETER", "BLOCKPOINTPARAMETER",
        "BLOCKPOLARPARAMETER", "BLOCKROTATIONPARAMETER", "BLOCKVISIBILITYPARAMETER",
        "BLOCKXYPARAMETER",
    ]

    /// Every drawing of the corpus that has a DXF export by AutoCAD: six releases of one drawing,
    /// ten dynamic block drawings of R2018, and a georeferenced one from another machine.
    static let corpusPairs: [Pair] =
        releases.map {
            Pair(dwg: "sample_\($0).dwg", dxf: "sample_\($0)_ascii.dxf", sameSave: true)
        }
        + dynamicBlocks.map {
            Pair(
                dwg: "dynamic-blocks/\($0).dwg", dxf: "dynamic-blocks/\($0).dxf", sameSave: false)
        } + [Pair(dwg: "geolocation/geoloc.dwg", dxf: "geolocation/geoloc.dxf", sameSave: false)]

    /// How many variables each release's text is expected to have, which pins the count, so that a
    /// variable that stops being written shows at once.
    static let written = [
        "AC1015": 196, "AC1018": 207, "AC1021": 246, "AC1024": 247, "AC1027": 248, "AC1032": 248,
    ]

    // MARK: Tests

    /// Compares the text for one drawing with AutoCAD's DXF, and returns the number of variables.
    @discardableResult
    static func check(_ name: String, dwg: URL, dxf: URL, sameSave: Bool) throws -> Int {
        let bytes = try Data(contentsOf: dwg)
        let ours = DXFReference(text: try DWG.dxfText(data: bytes))
        let theirs = try DXFReference(contentsOf: dxf)
        let decoded = try HeaderInput([UInt8](bytes)).read()

        #expect(Set(ours.headerOrder).count == ours.headerOrder.count, "\(name): a repeated name")
        let onlyOurs = ours.headerOrder.filter { theirs.header[$0] == nil }
        let onlyTheirs = theirs.headerOrder.filter { ours.header[$0] == nil }
        #expect(onlyOurs.isEmpty, "\(name): not in AutoCAD's DXF: \(onlyOurs)")
        for variable in onlyTheirs {
            let defaulted =
                Self.defaultedPointers.contains(variable) && decoded.handle(variable) == 0
            #expect(
                Self.notInTheHeaderSection[variable] != nil || defaulted,
                "\(name): \(variable) is in AutoCAD's DXF and neither written nor listed")
        }
        // The order is AutoCAD's, for the variables both have.
        #expect(
            ours.headerOrder.filter { theirs.header[$0] != nil }
                == theirs.headerOrder.filter { ours.header[$0] != nil },
            "\(name): the order differs")

        var counts = [Int: Int]()
        var bounded = Set<String>()
        for variable in ours.headerOrder {
            guard let mine = ours.header[variable], let other = theirs.header[variable] else {
                continue
            }
            var outcome = compare(variable, ours: mine, theirs: other, decoded: decoded)
            if case .differs = outcome, !sameSave, Self.editedBetweenSaves.contains(variable) {
                outcome = .bounded("not the same save of the drawing")
            }
            counts[outcome.rank, default: 0] += 1
            switch outcome {
            case .bounded: bounded.insert(variable)
            case .differs(let how): Issue.record("\(name) \(variable): \(how)")
            default: break
            }
        }
        let allowed = Self.allowedToBeBounded.union(sameSave ? [] : Self.editedBetweenSaves)
        #expect(bounded.isSubset(of: allowed), "\(name): \(bounded)")
        print(
            "header text \(name): \(ours.headerOrder.count) variables, \(counts[0] ?? 0) the same "
                + "text, \(counts[1] ?? 0) the same number, \(counts[2] ?? 0) within an allowance "
                + "\(bounded.sorted()); only in AutoCAD's: \(onlyTheirs)")
        return ours.headerOrder.count
    }

    @Test(
        "every variable written equals AutoCAD's own DXF export of the drawing, in its order",
        .enabled(if: Fixtures.corpus != nil), arguments: corpusPairs)
    func matchesAutoCADsDXF(pair: Pair) throws {
        let corpus = try #require(Fixtures.corpus)
        let count = try Self.check(
            pair.dwg, dwg: corpus.appendingPathComponent(pair.dwg),
            dxf: corpus.appendingPathComponent(pair.dxf), sameSave: pair.sameSave)
        if let release = Self.releases.first(where: { pair.dwg.contains($0) }) {
            #expect(count == Self.written[release])
        } else {
            #expect(count >= 240)
        }
    }

    @Test("the committed drawing's header equals AutoCAD's own DXF export of it")
    func committedDrawingMatchesAutoCADsDXF() throws {
        let count = try Self.check(
            "BLOCKPOINTPARAMETER",
            dwg: Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dwg"),
            dxf: Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dxf"),
            sameSave: false)
        #expect(count >= 240)
    }

    @Test(
        "every variable the header decodes is written or listed as not written",
        .enabled(if: Fixtures.corpus != nil))
    func everyDecodedVariableIsAccountedFor() throws {
        var decoded = Set<String>()
        for release in ["AC1014"] + Self.releases {
            let (input, _) = try HeaderInput.corpus(release, withDXF: false)
            decoded.formUnion(try input.read().values.keys)
        }
        let layout = Set(HeaderLayout.entries.map(\.name))
        #expect(layout.count == HeaderLayout.entries.count, "a variable is in the layout twice")
        // The only ones decoded and not written are the ones listed, and every one listed is one.
        #expect(decoded.subtracting(layout) == Set(Self.decodedNotWritten.keys))
        #expect(layout.isDisjoint(with: Self.decodedNotWritten.keys))
        // R14 keeps the local times that later releases do not.
        let notInLayout = Set(Self.notInTheHeaderSection.keys).subtracting([
            "$TDCREATE", "$TDUPDATE",
        ])
        #expect(layout.isDisjoint(with: notInLayout))
    }

    @Test("the README says which variables are not written, and why")
    func readmeListsWhatIsNotWritten() throws {
        let readme = try String(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("README.md"), encoding: .utf8)
        let names = Set(Self.decodedNotWritten.keys).union(Self.notInTheHeaderSection.keys)
        for name in names.sorted() {
            #expect(readme.contains(name), "the README does not mention \(name)")
        }
    }

    @Test(
        "an R14 header has AutoCAD's order, and the R12 variables where AutoCAD's R12 DXF has them",
        .enabled(if: Fixtures.corpus != nil))
    func r14Header() throws {
        // No AutoCAD DXF of an R14 drawing exists. Its variables are in the R2000 DXF of the same
        // drawing, but for the ones R2000 moved to the registry, which the R12 DXF has.
        let corpus = try #require(Fixtures.corpus)
        let bytes = try Data(contentsOf: corpus.appendingPathComponent("sample_AC1014.dwg"))
        let ours = DXFReference(text: try DWG.dxfText(data: bytes))
        let r2000 = try DXFReference(
            contentsOf: corpus.appendingPathComponent("sample_AC1015_ascii.dxf"))
        let r12 = try DXFReference(
            contentsOf: corpus.appendingPathComponent("sample_AC1009_ascii.dxf"))

        #expect(ours.header["$ACADVER"]?.first?.value == "AC1014")
        let r14Only = ["$DRAGMODE", "$OSMODE", "$BLIPMODE", "$COORDS", "$ATTDIA", "$ATTREQ"]
        for name in r14Only { #expect(ours.header[name] != nil, "\(name) is not written") }
        let strangers = ours.headerOrder.filter { r2000.header[$0] == nil && r12.header[$0] == nil }
        #expect(strangers.isEmpty, "in neither AutoCAD DXF: \(strangers)")
        for other in [r2000, r12] {
            #expect(
                ours.headerOrder.filter { other.header[$0] != nil }
                    == other.headerOrder.filter { ours.header[$0] != nil })
        }
        // R14 keeps the local times, as DXF names them, and has no universal ones.
        #expect(ours.header["$TDCREATE"] != nil)
        #expect(ours.header["$TDUCREATE"] == nil)
        #expect(
            ours.header["$MEASUREMENT"]?.first?.value.trimmingCharacters(in: .whitespaces) == "0")
    }

    // MARK: Pieces

    @Test("the template section's measurement is read for each layout, and a damaged one is nil")
    func templateMeasurement() {
        #expect(TemplateSection.measurement([0, 0, 0, 0], version: .ac1015) == 0)
        #expect(TemplateSection.measurement([0, 0, 1, 0], version: .ac1015) == 1)
        // From R2007 the length counts characters, and a one character description is empty.
        #expect(TemplateSection.measurement([1, 0, 0, 0, 1, 0], version: .ac1021) == 1)
        #expect(TemplateSection.measurement([1, 0, 0, 0, 0, 0], version: .ac1032) == 0)
        // A description of 2 characters is 4 bytes from R2007 and 2 before it.
        #expect(TemplateSection.measurement([2, 0, 65, 0, 66, 0, 1, 0], version: .ac1021) == 1)
        #expect(TemplateSection.measurement([2, 0, 65, 66, 1, 0], version: .ac1018) == 1)
        // Too short, or a value that is not 0 or 1.
        #expect(TemplateSection.measurement([], version: .ac1032) == nil)
        #expect(TemplateSection.measurement([0, 0], version: .ac1018) == nil)
        #expect(TemplateSection.measurement([0, 0, 2, 0], version: .ac1018) == nil)
        #expect(TemplateSection.measurement([0xFF, 0xFF, 1, 0], version: .ac1032) == nil)
    }

    @Test(
        "a drawing in metric units reads $MEASUREMENT as 1, which no DXF of the samples shows",
        .enabled(if: Fixtures.corpus != nil))
    func metricDrawingMeasurement() throws {
        // Every drawing that has an AutoCAD DXF is 0 in it. AecObjects.dwg has no DXF, so this is
        // not checked against AutoCAD: it shows that the value is read, not a constant, and that
        // it is 1 for a drawing in millimetres (INSUNITS 4) while another drawing in millimetres,
        // svg/export_sample.dwg, is 0, so it is a setting of its own.
        let corpus = try #require(Fixtures.corpus)
        let metric = try Document(
            [UInt8](
                try Data(contentsOf: corpus.appendingPathComponent("aec_objects/AecObjects.dwg"))))
        #expect(metric.header.int("$INSUNITS") == 4)
        #expect(metric.header.int("$MEASUREMENT") == 1)
        let other = try Document(
            [UInt8](try Data(contentsOf: corpus.appendingPathComponent("svg/export_sample.dwg"))))
        #expect(other.header.int("$INSUNITS") == 4)
        #expect(other.header.int("$MEASUREMENT") == 0)
    }

    @Test("a built-in arrowhead is named without its underscore, a block of the user's is not")
    func arrowheadNames() {
        #expect(DXFEmitter.arrowheadName("_BoxBlank") == "BoxBlank")
        #expect(DXFEmitter.arrowheadName("_ARCHTICK") == "ARCHTICK")
        #expect(DXFEmitter.arrowheadName("_MyArrow") == "_MyArrow")
        #expect(DXFEmitter.arrowheadName("Arrow") == "Arrow")
    }

    @Test("the code pages that have a DXF name are the ones that have an encoding")
    func codePageNames() {
        #expect(CodePage.dxfName(for: 30) == "ANSI_1252")
        for number in 0..<64 where CodePage.dxfName(for: number) != nil {
            #expect(CodePage.encoding(for: number) != nil)
        }
        #expect(CodePage.dxfName(for: 0) == nil)
    }
}
