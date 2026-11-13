import Foundation
import Testing

@testable import SwiftDWG

/// The header variables of the corpus drawings, against AutoCAD's own DXF export of each, and the
/// handles the header names against the objects in the file.
@Suite("Header variables against AutoCAD")
struct HeaderOracleTests {
    /// What comparing a release's header with its DXF is expected to give.
    ///
    /// Every number is exact, so a variable that starts or stops agreeing shows at once.
    struct Expectation {
        /// Variables, in both files, whose values are equal.
        var equal: Int
        /// Variables that agree within an allowance (see `HeaderOracle.Outcome.bounded`).
        var bounded: Set<String>
        /// Variables that cannot be compared, and are not counted as equal.
        var notCompared: Set<String>
        /// Handles the header names that are not variables, equal to where the DXF has the object.
        var pointersEqual: Int
        /// Handles the DXF has no counterpart for.
        var pointersNotCompared: Set<String>
    }

    /// Written at a different moment from the DXF, which was saved about a second later: the next
    /// handle, the last save, and the editing time and user timer that the save adds a second to.
    static let movedBySaving: Set<String> = ["$HANDSEED", "$TDUUPDATE", "$TDINDWG", "$TDUSRTIMER"]

    /// Variables the DXF holds as a different thing from the DWG: a nearest palette index for a true
    /// colour, and a GUID that is new at every save.
    static let neverEqual: Set<String> = ["$CECOLOR", "$VERSIONGUID"]

    static let expectations: [String: Expectation] = [
        // R2000: the DXF has no `$XCLIPFRAME`, and `$CECOLOR` is an index and so can be compared.
        // The two handles of the viewport entity header have no DXF counterpart: the objects they
        // point at are checked by type in the object stream instead.
        "AC1015": Expectation(
            equal: 188, bounded: movedBySaving, notCompared: ["$VERSIONGUID"], pointersEqual: 20,
            pointersNotCompared: [
                "CURRENT_VIEWPORT_ENTITY_HEADER", "VIEWPORT_ENTITY_HEADER_CONTROL_OBJECT",
            ]),
        "AC1018": Expectation(
            equal: 197, bounded: movedBySaving, notCompared: neverEqual.union(["$XCLIPFRAME"]),
            pointersEqual: 22, pointersNotCompared: []),
        // R2007: the times agree with the DXF's to the digits it prints (that DXF was written in the
        // same second as the DWG), and the next handle is the only one that moved.
        "AC1021": Expectation(
            equal: 239, bounded: ["$HANDSEED"], notCompared: neverEqual.union(["$XCLIPFRAME"]),
            pointersEqual: 23, pointersNotCompared: []),
        "AC1024": Expectation(
            equal: 238, bounded: movedBySaving, notCompared: neverEqual, pointersEqual: 23,
            pointersNotCompared: []),
        // R2013 and later: the extra handle after the visual style dictionary is null.
        "AC1027": Expectation(
            equal: 239, bounded: movedBySaving, notCompared: neverEqual, pointersEqual: 23,
            pointersNotCompared: ["UNKNOWN_R2013"]),
        "AC1032": Expectation(
            equal: 239, bounded: movedBySaving, notCompared: neverEqual, pointersEqual: 23,
            pointersNotCompared: ["UNKNOWN_R2013"]),
    ]

    /// The variables in AutoCAD's DXF that are not in the header section of a DWG: the file header
    /// and the summary hold some, the rest cannot be known from a DWG.
    static let notInHeaderSection: Set<String> = [
        "$ACADVER", "$ACADMAINTVER", "$DWGCODEPAGE", "$LASTSAVEDBY", "$MEASUREMENT",
        // From R2000 the DWG keeps the creation and the last save as universal time (`$TDUCREATE`
        // and `$TDUUPDATE`). DXF adds the offset of the computer that exported it for these two.
        "$TDCREATE", "$TDUPDATE",
        // Probably the unnamed bit before `$INTERFERECOLOR`, but only evidence of position.
        "$REALWORLDSCALE",
    ]

    // MARK: Variables

    @Test(
        "every variable equals AutoCAD's own DXF export of the drawing",
        .enabled(if: Fixtures.corpus != nil), arguments: HeaderReaderTests.corpusReleases)
    func variablesMatchDXF(release: String) throws {
        let (input, dxfOrNil) = try HeaderInput.corpus(release)
        let dxf = try #require(dxfOrNil)
        let header = try input.read()
        let oracle = HeaderOracle(dxf: dxf, release: release)
        #expect(dxf.header["$ACADVER"]?.first?.value == release)

        var equal = 0
        var bounded = [String: String]()
        var notCompared = [String: String]()
        var differ = 0
        for (name, value) in header.values where dxf.header[name] != nil {
            switch oracle.compare(name, value) {
            case .matched: equal += 1
            case .bounded(let why): bounded[name] = why
            case .notCompared(let why): notCompared[name] = why
            case .differs(let how):
                differ += 1
                Issue.record("\(release) \(name): \(how)")
            }
        }
        let dxfOnly = Set(dxf.header.keys).subtracting(header.values.keys)
        #expect(dxfOnly.subtracting(Self.notInHeaderSection).isEmpty, "\(release): \(dxfOnly)")
        let dwgOnly = Set(header.values.keys).subtracting(dxf.header.keys)

        var pointersEqual = 0
        var pointersNotCompared = [String: String]()
        let pointers = header.handles.filter { HeaderReader.Parser.variableNames[$0.key] == nil }
        for (name, handle) in pointers {
            switch oracle.compare(pointer: name, handle) {
            case .matched: pointersEqual += 1
            case .notCompared(let why): pointersNotCompared[name] = why
            case .bounded, .differs: Issue.record("\(release) \(name): \(handle) is not in the DXF")
            }
        }

        let total = equal + bounded.count + notCompared.count + differ
        print(
            "header \(release): \(equal) of \(total) variables equal AutoCAD's, \(differ) differ, "
                + "\(bounded.count) agree within an allowance, \(notCompared.count) not compared; "
                + "\(pointersEqual) of \(pointers.count) other handles equal; "
                + "\(dwgOnly.count) variables only in the DWG, DXF only: \(dxfOnly.sorted())")
        print("  allowance: \(bounded.sorted { $0.key < $1.key })")
        print("  not compared: \(notCompared.sorted { $0.key < $1.key })")
        print("  handles not compared: \(pointersNotCompared.sorted { $0.key < $1.key })")
        print("  only in the DWG: \(dwgOnly.sorted())")

        let expected = try #require(Self.expectations[release])
        #expect(equal == expected.equal)
        #expect(Set(bounded.keys) == expected.bounded)
        #expect(Set(notCompared.keys) == expected.notCompared)
        #expect(pointersEqual == expected.pointersEqual)
        #expect(Set(pointersNotCompared.keys) == expected.pointersNotCompared)
    }

    @Test(
        "an R14 file reads, and agrees with the R2000 DXF of the same drawing where both have a variable",
        .enabled(if: Fixtures.corpus != nil))
    func r14AgainstTheR2000DXF() throws {
        // There is no DXF for the R14 file. The R2000 DXF is AutoCAD's export of the same drawing,
        // from the same session (the script saves every release, then every DXF), so the drawing's
        // own state is in both: the extents, the limits, the units, the styles and their handles,
        // the dimension settings. What cannot be expected to agree is what a release defaults or
        // writes differently, which the checks below name one by one.
        let (input, _) = try HeaderInput.corpus("AC1014", withDXF: false)
        let (_, dxfOrNil) = try HeaderInput.corpus("AC1015")
        let dxf = try #require(dxfOrNil)
        #expect(input.version == .ac1014)
        let header = try input.read()
        var oracle = HeaderOracle(dxf: dxf, release: "AC1015")
        oracle.ignoringCase = true

        var equal = 0
        var bounded = [String: String]()
        var differ = [String: String]()
        var notCompared = [String: String]()
        for (name, value) in header.values where dxf.header[name] != nil {
            switch oracle.compare(name, value) {
            case .matched: equal += 1
            case .bounded(let why): bounded[name] = why
            case .notCompared(let why): notCompared[name] = why
            case .differs(let how): differ[name] = how
            }
        }
        let onlyR14 = Set(header.values.keys).subtracting(dxf.header.keys)
        print(
            "header AC1014 against the AC1015 DXF: \(equal) of \(header.values.count) variables "
                + "equal, \(bounded.count) agree within an allowance, \(differ.count) differ, "
                + "\(onlyR14.count) only in R14")
        print("  allowance: \(bounded.sorted { $0.key < $1.key })")
        print("  differ: \(differ.sorted { $0.key < $1.key })")

        #expect(equal == 143)
        // The next handle and the times a save moves on, which the DXF save moved a second further,
        // and a block name that R14 keeps in capitals.
        #expect(
            Set(bounded.keys) == ["$HANDSEED", "$TDUPDATE", "$TDINDWG", "$TDUSRTIMER", "$DIMBLK"])
        #expect(notCompared.isEmpty)
        // The one difference: R14 has 48 viewports where the R2000 file has 64. The variable is a
        // setting that the release sets, and everything after it in the file agrees, so the read
        // is in step.
        #expect(Set(differ.keys) == ["$MAXACTVP"])
        #expect(header.int("$MAXACTVP") == 48)
        // R14 stores in the drawing what R2000 moved to the registry, and has no ones R2000 added.
        #expect(
            onlyR14 == [
                "$ATTDIA", "$ATTREQ", "$BLIPMODE", "$COORDS", "$DELOBJ", "$DIMFIT", "$DIMSAV",
                "$DIMUNIT", "$DRAGMODE", "$FACETRES", "$ISOLINES", "$OSMODE", "$PELLIPSE",
                "$PICKSTYLE", "$TEXTQLTY",
            ])
        // R14 keeps the local times, which are what the R2000 DXF calls `$TDCREATE`.
        #expect(header.double("$TDUCREATE") == nil)
        #expect(header.double("$TDCREATE") != nil)

        // The handles it names are the ones the R2000 DXF has for the same objects.
        var pointersEqual = 0
        var pointersNotCompared = Set<String>()
        for (name, handle) in header.handles
        where HeaderReader.Parser.variableNames[name] == nil {
            switch oracle.compare(pointer: name, handle) {
            case .matched: pointersEqual += 1
            case .notCompared: pointersNotCompared.insert(name)
            case .bounded, .differs: Issue.record("AC1014 \(name): \(handle) is not in the DXF")
            }
        }
        print("  \(pointersEqual) of the other handles equal the R2000 DXF's")
        #expect(pointersEqual == 17)
        #expect(
            pointersNotCompared == [
                "CURRENT_VIEWPORT_ENTITY_HEADER", "VIEWPORT_ENTITY_HEADER_CONTROL_OBJECT",
            ])
    }

    @Test(
        "the visual style dictionary keeps its handle, and R2013's extra handle is read after it",
        .enabled(if: Fixtures.corpus != nil), arguments: ["AC1027", "AC1032"])
    func visualStyleDictionaryAndTheExtraHandle(release: String) throws {
        let (input, dxfOrNil) = try HeaderInput.corpus(release)
        let dxf = try #require(dxfOrNil)
        let header = try input.read()
        // ACadSharp stores both over the same name, so what it keeps is the second, which is null
        // in these drawings, and the dictionary's handle is lost.
        #expect(header.handles["UNKNOWN_R2013"] != nil)
        #expect(header.handles["DICTIONARY_VISUALSTYLE"] == dxf.rootEntries["ACAD_VISUALSTYLE"])
        #expect(header.handles["DICTIONARY_VISUALSTYLE"] != 0)
    }

    @Test(
        "the current colour, a true colour that DXF cannot hold, is the same in every release",
        .enabled(if: Fixtures.corpus != nil))
    func trueColourIsTheSameInEveryRelease() throws {
        // The drawing is the same in every file, so its current colour is. R2004 reads the colour's
        // names from the main data and R2007 and later from the string stream, so this also shows
        // that the colour is read in step in both.
        var colours = Set<UInt32>()
        for release in ["AC1018", "AC1021", "AC1024", "AC1027", "AC1032"] {
            let (input, _) = try HeaderInput.corpus(release, withDXF: false)
            guard case .color(_, let rgb?) = try input.read().values["$CECOLOR"] else {
                Issue.record("\(release): $CECOLOR is not a true colour")
                continue
            }
            colours.insert(rgb)
        }
        #expect(colours.count == 1)
        // The R2000 file has only an index, which is what its DXF has.
        let (input, dxf) = try HeaderInput.corpus("AC1015")
        #expect(try input.read().int("$CECOLOR") == dxf?.header["$CECOLOR"]?.first?.integer)
    }

    // MARK: Handles against the objects

    /// What an object a header handle names is, in the object stream.
    struct Kind {
        /// The object type code, or `nil` for any object of a class the file defines.
        var type: Int?
        /// Whether a class object is also allowed, as for a dictionary of a class that derives from it.
        var orClass = false
        /// Whether the handle may be null.
        var optional = false
    }

    static let kinds: [String: Kind] = {
        var kinds = [String: Kind]()
        let controls: [String: Int] = [
            "BLOCK_CONTROL_OBJECT": ObjectType.blockControl,
            "LAYER_CONTROL_OBJECT": ObjectType.layerControl,
            "STYLE_CONTROL_OBJECT": ObjectType.styleControl,
            "LINETYPE_CONTROL_OBJECT": ObjectType.lineTypeControl,
            "VIEW_CONTROL_OBJECT": ObjectType.viewControl,
            "UCS_CONTROL_OBJECT": ObjectType.ucsControl,
            "VPORT_CONTROL_OBJECT": ObjectType.viewportControl,
            "APPID_CONTROL_OBJECT": ObjectType.appIDControl,
            "DIMSTYLE_CONTROL_OBJECT": ObjectType.dimensionStyleControl,
            "VIEWPORT_ENTITY_HEADER_CONTROL_OBJECT": ObjectType.viewportEntityControl,
            "CURRENT_VIEWPORT_ENTITY_HEADER": ObjectType.viewportEntityHeader,
            "CLAYER": ObjectType.layer, "TEXTSTYLE": ObjectType.style,
            "CELTYPE": ObjectType.lineType, "DIMSTYLE": ObjectType.dimensionStyle,
            "CMLSTYLE": ObjectType.mlineStyle, "PAPER_SPACE": ObjectType.blockHeader,
            "MODEL_SPACE": ObjectType.blockHeader, "BYLAYER": ObjectType.lineType,
            "BYBLOCK": ObjectType.lineType, "CONTINUOUS": ObjectType.lineType,
        ]
        for (name, type) in controls { kinds[name] = Kind(type: type) }
        let optionals: [String: Int] = [
            "DIMTXSTY": ObjectType.style, "DIMLTYPE": ObjectType.lineType,
            "DIMLTEX1": ObjectType.lineType, "DIMLTEX2": ObjectType.lineType,
            "DIMBLK": ObjectType.blockHeader, "DIMBLK1": ObjectType.blockHeader,
            "DIMBLK2": ObjectType.blockHeader, "DIMLDRBLK": ObjectType.blockHeader,
            "UCSNAME_PSPACE": ObjectType.ucs, "UCSNAME_MSPACE": ObjectType.ucs,
            "PUCSBASE": ObjectType.ucs, "UCSBASE": ObjectType.ucs,
            "PUCSORTHOREF": ObjectType.ucs, "UCSORTHOREF": ObjectType.ucs,
        ]
        for (name, type) in optionals { kinds[name] = Kind(type: type, optional: true) }
        let dictionaries = [
            "DICTIONARY_NAMED_OBJECTS", "DICTIONARY_ACAD_GROUP", "DICTIONARY_ACAD_MLINESTYLE",
            "DICTIONARY_LAYOUTS", "DICTIONARY_PLOTSETTINGS", "DICTIONARY_PLOTSTYLES",
            "DICTIONARY_MATERIALS", "DICTIONARY_COLORS", "DICTIONARY_VISUALSTYLE",
        ]
        for name in dictionaries { kinds[name] = Kind(type: ObjectType.dictionary, orClass: true) }
        // Materials and visual styles are objects of classes the file defines, and these may be null.
        for name in ["CMATERIAL", "INTERFEREOBJVS", "INTERFEREVPVS", "DRAGVS", "UNKNOWN_R2013"] {
            kinds[name] = Kind(type: nil, optional: true)
        }
        kinds["CPSNID"] = Kind(type: nil, optional: true)
        return kinds
    }()

    /// Checks that every handle the header names is an object in the file of the right kind.
    private func expectObjects(_ input: HeaderInput, _ release: String) throws {
        let header = try input.read()
        let store = try ObjectStore(input.container)
        for (name, handle) in header.handles {
            guard let kind = Self.kinds[name] else {
                Issue.record("\(release): no kind for \(name)")
                continue
            }
            if handle == 0 {
                #expect(kind.optional, "\(release) \(name) is null")
                continue
            }
            guard let reader = try store.reader(for: handle) else {
                Issue.record("\(release) \(name) = \(handle) is not an object in the file")
                continue
            }
            let isClass = reader.type >= ObjectType.firstClass
            if let type = kind.type {
                #expect(
                    reader.type == type || (kind.orClass && isClass),
                    "\(release) \(name) is an object of type \(reader.type), not \(type)")
            } else {
                #expect(isClass, "\(release) \(name) is an object of type \(reader.type)")
            }
        }
    }

    @Test(
        "every handle the header names is an object of the right kind in the file",
        .enabled(if: Fixtures.corpus != nil), arguments: HeaderReaderTests.readableReleases)
    func handlesAreObjects(release: String) throws {
        let (input, _) = try HeaderInput.corpus(release, withDXF: false)
        try expectObjects(input, release)
    }

    @Test("the committed AC1032 file's header handles are objects of the right kind")
    func emptyDrawingHandlesAreObjects() throws {
        try expectObjects(try HeaderInput(try Fixtures.data("empty.dwg")), "empty.dwg")
    }

    @Test(
        "R14 and R2000 name the viewport entity header objects, which DXF does not write",
        .enabled(if: Fixtures.corpus != nil), arguments: ["AC1014", "AC1015"])
    func viewportEntityHeaderHandles(release: String) throws {
        let (input, _) = try HeaderInput.corpus(release, withDXF: false)
        let header = try input.read()
        let store = try ObjectStore(input.container)
        let control = try #require(header.handles["VIEWPORT_ENTITY_HEADER_CONTROL_OBJECT"])
        let current = try #require(header.handles["CURRENT_VIEWPORT_ENTITY_HEADER"])
        #expect(try store.reader(for: control)?.type == ObjectType.viewportEntityControl)
        #expect(try store.reader(for: current)?.type == ObjectType.viewportEntityHeader)
        #expect(control != current)
    }
}
