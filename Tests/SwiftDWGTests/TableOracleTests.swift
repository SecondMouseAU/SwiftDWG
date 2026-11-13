import Foundation
import SwiftDXF
import Testing

@testable import SwiftDWG

/// Table records, control objects, dictionaries and layouts read from a DWG, compared with the
/// ones in AutoCAD's own DXF export of the drawing.
///
/// The expected values are the raw groups AutoCAD wrote, keyed by handle, so nothing here is
/// checked against SwiftDWG's own output. A DXF dimension style lists only the variables that
/// differ from AutoCAD's defaults, so for those the default is the expected value.
///
/// The DWG and the DXF of a sample are two saves of one drawing, and AutoCAD creates some objects
/// when it saves (round-trip dictionaries, annotation scale records, the layers and application
/// names that go with them) and gives them different handles in the two files. An object that only
/// one file has under a handle cannot be compared by handle. Table entries of that kind are paired
/// by name instead, and a handle that only one file has is left out of a list of handles before
/// the two lists are compared. Every other record is compared field by field.
struct TableOracle {
    let store: ObjectStore
    let records: [UInt64: DXFRecord]
    let sequence: [DXFSectionRecord]

    /// How many records of each kind were compared.
    var compared: [String: Int] = [:]
    var mismatches: [String] = []
    /// Table records of the DWG that the DXF has under no handle, as `KIND handle`.
    var dwgOnly: [String] = []

    init(dwg: [UInt8], dxf: URL) throws {
        store = try ObjectStore(try Container(dwg))
        records = try DXFGroups.records(in: dxf)
        sequence = try DXFGroups.sequence(in: dxf)
    }

    // MARK: Plumbing

    static func hex(_ handle: UInt64) -> String { String(handle, radix: 16, uppercase: true) }

    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-9 * max(1, abs(b)) }

    static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    mutating func expect(
        _ ok: Bool, _ kind: String, _ handle: UInt64, _ what: @autoclosure () -> String
    ) {
        if !ok { mismatches.append("\(kind) \(Self.hex(handle)): \(what())") }
    }

    mutating func expectNear(
        _ got: Double, _ want: Double, _ kind: String, _ handle: UInt64, _ what: String
    ) {
        expect(Self.near(got, want), kind, handle, "\(what) \(got) is not \(want)")
    }

    mutating func count(_ kind: String) { compared[kind, default: 0] += 1 }

    /// Whether both files have an object under this handle.
    func isShared(_ handle: UInt64) -> Bool { store.map[handle] != nil && records[handle] != nil }

    /// Compares the handles a DWG object lists with the ones the DXF lists, in order, after leaving
    /// out the handles that only one of the files has.
    mutating func expectHandles(
        _ kind: String, _ handle: UInt64, _ what: String, dwg: [UInt64], dxf: [UInt64]
    ) {
        let got = dwg.filter(isShared)
        let want = dxf.filter(isShared)
        compared["\(kind) handles left out"] =
            (compared["\(kind) handles left out"] ?? 0)
            + (dwg.count - got.count) + (dxf.count - want.count)
        expect(
            got == want, kind, handle,
            "\(what): \(got.map(Self.hex)) is not \(want.map(Self.hex))")
    }

    /// The DXF records of one type, in file order.
    func dxfRecords(_ type: String) -> [DXFRecord] {
        sequence.filter { $0.record.type == type }.map(\.record)
    }

    func name(ofLineType handle: UInt64) throws -> String? {
        if case .lineType(let data)? = try store.tableRecord(handle) { return data.entry.name }
        return nil
    }

    /// The colour a DXF layer or style writes: a true colour in 420 when there is one, otherwise
    /// the index in `code`.
    static func expectedColor(_ record: DXFRecord, index: Int, trueColor: Int = 420) -> DWGColor {
        if let rgb = record.int(trueColor) {
            return .rgb(
                red: UInt8((rgb >> 16) & 0xFF), green: UInt8((rgb >> 8) & 0xFF),
                blue: UInt8(rgb & 0xFF))
        }
        return ObjectReader.indexColor(abs(index))
    }

    /// The checks every non-entity object shares: its owner and its extension dictionary.
    mutating func checkObject(
        _ kind: String, _ handle: UInt64, _ object: ObjectReader.ObjectCommon, _ record: DXFRecord
    ) {
        expect(object.handle == handle, kind, handle, "handle \(Self.hex(object.handle))")
        expect(
            object.owner == record.headerHandle(330), kind, handle,
            "owner \(Self.hex(object.owner)) is not \(Self.hex(record.headerHandle(330)))")
        // An extension dictionary that only one file has was made when that file was saved.
        let want =
            record.block("ACAD_XDICTIONARY").first { $0.code == 360 }
            .flatMap { UInt64($0.value, radix: 16) } ?? 0
        let got = object.extensionDictionary
        let made = (want != 0 && !isShared(want)) || (got != 0 && !isShared(got))
        expect(
            got == want || made, kind, handle,
            "extension dictionary \(Self.hex(got)) is not \(Self.hex(want))")
    }

    // MARK: Whole drawing

    mutating func run() throws {
        try compareLayers()
        try compareLineTypes()
        try compareTextStyles()
        try compareDimensionStyles()
        try compareAppIDs()
        try compareBlockRecords()
        try compareBlocks()
        try compareDictionaries()
        try compareLayouts()
        try compareControls()
        try checkUnshared()
    }

    /// The DXF type that goes with a DWG object type, for the objects this file decodes.
    static func dxfType(of type: Int?) -> String? {
        switch type {
        case ObjectType.blockHeader: return "BLOCK_RECORD"
        case ObjectType.layer: return "LAYER"
        case ObjectType.lineType: return "LTYPE"
        case ObjectType.style: return "STYLE"
        case ObjectType.dimensionStyle: return "DIMSTYLE"
        case ObjectType.appID: return "APPID"
        case ObjectType.dictionary: return "DICTIONARY"
        case ObjectType.layout: return "LAYOUT"
        case ObjectType.block: return "BLOCK"
        case ObjectType.endBlock: return "ENDBLK"
        case ObjectType.blockControl, ObjectType.layerControl, ObjectType.styleControl,
            ObjectType.lineTypeControl, ObjectType.viewControl, ObjectType.ucsControl,
            ObjectType.viewportControl, ObjectType.appIDControl, ObjectType.dimensionStyleControl:
            return "TABLE"
        default: return nil
        }
    }

    /// The name a table entry is paired by: the whole name, except for a block that AutoCAD
    /// numbers, which is its `*` and letters.
    static func pairingName(_ name: String) -> String {
        guard name.hasPrefix("*") else { return name }
        return String(name.reversed().drop { $0.isNumber }.reversed())
    }

    /// The kinds of record that are compared one by one, as the DXF names them.
    static let comparedKinds = [
        "LAYER", "LTYPE", "STYLE", "DIMSTYLE", "APPID", "BLOCK_RECORD", "BLOCK", "ENDBLK",
        "DICTIONARY", "LAYOUT",
    ]

    /// Looks at the objects that only one file has under their handle.
    ///
    /// Every table entry the DXF has and the DWG does not must have a DWG entry of the same name
    /// that the DXF does not have. Every table record of the DWG must decode, and has the DXF type
    /// it should have where the DXF has it. The ones with no DXF record are counted.
    mutating func checkUnshared() throws {
        var dwgNames: [String: [String]] = [:]
        for handle in store.handles {
            guard let kind = Self.dxfType(of: try store.reader(for: handle)?.type) else { continue }
            if let record = records[handle] {
                expect(record.type == kind, kind, handle, "the DXF calls it \(record.type)")
                continue
            }
            dwgOnly.append("\(kind) \(Self.hex(handle))")
            compared["\(kind) only in the DWG", default: 0] += 1
            switch try store.tableRecord(handle) {
            case .layer(let data)?: dwgNames["LAYER", default: []].append(data.entry.name)
            case .appID(let data)?: dwgNames["APPID", default: []].append(data.entry.name)
            case .lineType(let data)?: dwgNames["LTYPE", default: []].append(data.entry.name)
            case .textStyle(let data)?: dwgNames["STYLE", default: []].append(data.entry.name)
            case .dimensionStyle(let data)?:
                dwgNames["DIMSTYLE", default: []].append(data.entry.name)
            case .blockHeader(let data)?:
                dwgNames["BLOCK_RECORD", default: []].append(Self.pairingName(data.entry.name))
            default: break
            }
        }
        for kind in Self.comparedKinds {
            for record in dxfRecords(kind) {
                guard let handle = record.handle, store.map[handle] == nil else { continue }
                compared["\(kind) only in the DXF", default: 0] += 1
                guard dwgNames[kind] != nil else { continue }
                let name = Self.pairingName(record.first(2) ?? "")
                if let index = dwgNames[kind]?.firstIndex(of: name) {
                    dwgNames[kind]?.remove(at: index)
                    compared["\(kind) paired by name", default: 0] += 1
                } else {
                    expect(false, kind, handle, "\(name) is only in the DXF")
                }
            }
        }
    }

    // MARK: Layers

    mutating func compareLayers() throws {
        for record in dxfRecords("LAYER") {
            guard let handle = record.handle, store.map[handle] != nil else { continue }
            count("LAYER")
            guard case .layer(let layer)? = try store.tableRecord(handle) else {
                expect(false, "LAYER", handle, "not read as a layer")
                continue
            }
            checkObject("LAYER", handle, layer.entry.object, record)
            let flags = record.int(70) ?? 0
            let colorCode = record.int(62) ?? 7
            expect(layer.entry.name == record.first(2), "LAYER", handle, "name \(layer.entry.name)")
            expect(layer.isFrozen == (flags & 1 != 0), "LAYER", handle, "frozen")
            expect(
                layer.isFrozenInNewViewports == (flags & 2 != 0), "LAYER", handle, "frozen in new")
            expect(layer.isLocked == (flags & 4 != 0), "LAYER", handle, "locked")
            expect(layer.entry.isXrefDependent == (flags & 16 != 0), "LAYER", handle, "xref")
            expect(layer.isOff == (colorCode < 0), "LAYER", handle, "off")
            expect(layer.isPlotted == ((record.int(290) ?? 1) != 0), "LAYER", handle, "plot flag")
            expect(layer.lineWeight == (record.int(370) ?? -3), "LAYER", handle, "weight")
            expect(
                layer.color == Self.expectedColor(record, index: colorCode), "LAYER", handle,
                "colour \(layer.color) for \(colorCode)")
            let lineTypeName = try name(ofLineType: layer.lineType)
            expect(
                lineTypeName == record.first(6), "LAYER", handle, "line type \(lineTypeName ?? "-")"
            )
            expect(layer.plotStyle == record.handleValue(390), "LAYER", handle, "plot style")
            expect(layer.material == record.handleValue(347), "LAYER", handle, "material")
        }
    }

    // MARK: Line types

    /// One element of a DXF line type pattern, from its groups in order.
    struct DXFSegment {
        var length = 0.0
        var flags = 0
        var shape: Int?
        var style: UInt64 = 0
        var scale: Double?
        var rotation: Double?
        var offsetX: Double?
        var offsetY: Double?
        var text: String?
    }

    static func dxfSegments(_ record: DXFRecord) -> [DXFSegment] {
        var out: [DXFSegment] = []
        for (code, value) in record.groups {
            switch code {
            case 49: out.append(DXFSegment(length: Double(value) ?? .nan))
            case 74: out[out.count - 1].flags = Int(value) ?? -1
            case 75: out[out.count - 1].shape = Int(value)
            case 340: out[out.count - 1].style = UInt64(value, radix: 16) ?? 0
            case 46: out[out.count - 1].scale = Double(value)
            case 50: out[out.count - 1].rotation = Double(value)
            case 44: out[out.count - 1].offsetX = Double(value)
            case 45: out[out.count - 1].offsetY = Double(value)
            case 9: out[out.count - 1].text = value
            default: break
            }
        }
        return out
    }

    mutating func compareLineTypes() throws {
        for record in dxfRecords("LTYPE") {
            guard let handle = record.handle, store.map[handle] != nil else { continue }
            count("LTYPE")
            guard case .lineType(let type)? = try store.tableRecord(handle) else {
                expect(false, "LTYPE", handle, "not read as a line type")
                continue
            }
            checkObject("LTYPE", handle, type.entry.object, record)
            expect(type.entry.name == record.first(2), "LTYPE", handle, "name \(type.entry.name)")
            expect(
                type.entry.isXrefDependent == (((record.int(70) ?? 0) & 16) != 0), "LTYPE", handle,
                "xref")
            expect(type.description == (record.first(3) ?? ""), "LTYPE", handle, "description")
            expect(Int(type.alignment) == record.int(72), "LTYPE", handle, "alignment")
            expectNear(type.patternLength, record.double(40) ?? 0, "LTYPE", handle, "length")
            expect(type.segments.count == (record.int(73) ?? 0), "LTYPE", handle, "element count")
            let expected = Self.dxfSegments(record)
            guard expected.count == type.segments.count else {
                expect(
                    false, "LTYPE", handle, "\(type.segments.count) segments for \(expected.count)")
                continue
            }
            for (got, want) in zip(type.segments, expected) {
                count("LTYPE segment")
                expectNear(got.length, want.length, "LTYPE", handle, "dash")
                // The DXF of releases before R2013 leaves out bit 8, which the DWG always has.
                expect(
                    got.flags == want.flags || (want.flags & 8 == 0 && got.flags & 7 == want.flags),
                    "LTYPE", handle, "flags \(got.flags) is not \(want.flags)")
                guard want.flags & 6 != 0 else { continue }
                expect(
                    got.shapeNumber == (want.shape ?? -1), "LTYPE", handle,
                    "shape \(got.shapeNumber)")
                expect(got.style == want.style, "LTYPE", handle, "style")
                expectNear(got.scale, want.scale ?? .nan, "LTYPE", handle, "scale")
                expectNear(
                    Self.degrees(got.rotation), want.rotation ?? .nan, "LTYPE", handle, "rotation")
                expectNear(got.offsetX, want.offsetX ?? .nan, "LTYPE", handle, "offset x")
                expectNear(got.offsetY, want.offsetY ?? .nan, "LTYPE", handle, "offset y")
                if want.flags & 2 != 0 {
                    count("LTYPE text")
                    expect(got.text == want.text, "LTYPE", handle, "text \(got.text ?? "-")")
                } else {
                    expect(got.text == nil, "LTYPE", handle, "text on a shape")
                }
            }
        }
    }

    // MARK: Text styles

    mutating func compareTextStyles() throws {
        for record in dxfRecords("STYLE") {
            guard let handle = record.handle, store.map[handle] != nil else { continue }
            count("STYLE")
            guard case .textStyle(let style)? = try store.tableRecord(handle) else {
                expect(false, "STYLE", handle, "not read as a text style")
                continue
            }
            checkObject("STYLE", handle, style.entry.object, record)
            let flags = record.int(70) ?? 0
            expect(style.entry.name == (record.first(2) ?? ""), "STYLE", handle, "name")
            expect(style.isShapeFile == (flags & 1 != 0), "STYLE", handle, "shape file")
            expect(style.isVertical == (flags & 4 != 0), "STYLE", handle, "vertical")
            expect(style.entry.isXrefDependent == (flags & 16 != 0), "STYLE", handle, "xref")
            expectNear(style.fixedHeight, record.double(40) ?? 0, "STYLE", handle, "height")
            expectNear(style.widthFactor, record.double(41) ?? 1, "STYLE", handle, "width")
            expectNear(
                Self.degrees(style.obliqueAngle), record.double(50) ?? 0, "STYLE", handle, "oblique"
            )
            expect(style.generationFlags == (record.int(71) ?? 0), "STYLE", handle, "generation")
            expectNear(style.lastHeight, record.double(42) ?? 0, "STYLE", handle, "last height")
            expect(
                style.fontFile == (record.first(3) ?? ""), "STYLE", handle, "font \(style.fontFile)"
            )
            expect(style.bigFontFile == (record.first(4) ?? ""), "STYLE", handle, "big font")
        }
    }

    // MARK: Dimension styles

    /// A dimension variable that is a number in the DXF, its group code, its default, and how to
    /// read it from the decoded style.
    struct DimensionVariable {
        var code: Int
        var name: String
        var defaultValue: Double
        var value: (DimensionStyleData) -> Double
    }

    /// AutoCAD's defaults, from the DXF reference, not from `DimensionStyleData`.
    static let dimensionVariables: [DimensionVariable] = {
        func flag(_ value: Bool) -> Double { value ? 1 : 0 }
        func make(
            _ code: Int, _ name: String, _ defaultValue: Double,
            _ value: @escaping (DimensionStyleData) -> Double
        )
            -> DimensionVariable
        { DimensionVariable(code: code, name: name, defaultValue: defaultValue, value: value) }
        return [
            make(40, "DIMSCALE", 1) { $0.scale },
            make(41, "DIMASZ", 0.18) { $0.arrowSize },
            make(42, "DIMEXO", 0.0625) { $0.extensionLineOffset },
            make(43, "DIMDLI", 0.38) { $0.dimensionLineIncrement },
            make(44, "DIMEXE", 0.18) { $0.extensionLineExtension },
            make(45, "DIMRND", 0) { $0.rounding },
            make(46, "DIMDLE", 0) { $0.dimensionLineExtension },
            make(47, "DIMTP", 0) { $0.plusTolerance },
            make(48, "DIMTM", 0) { $0.minusTolerance },
            make(49, "DIMFXL", 1) { $0.fixedExtensionLineLength },
            make(50, "DIMJOGANG", 45) { TableOracle.degrees($0.joggedRadiusAngle) },
            make(69, "DIMTFILL", 0) { Double($0.textBackgroundFill) },
            make(71, "DIMTOL", 0) { flag($0.generateTolerances) },
            make(72, "DIMLIM", 0) { flag($0.limitsGeneration) },
            make(73, "DIMTIH", 1) { flag($0.textInsideHorizontal) },
            make(74, "DIMTOH", 1) { flag($0.textOutsideHorizontal) },
            make(75, "DIMSE1", 0) { flag($0.suppressExtensionLine1) },
            make(76, "DIMSE2", 0) { flag($0.suppressExtensionLine2) },
            make(77, "DIMTAD", 0) { Double($0.textVerticalPosition) },
            make(78, "DIMZIN", 0) { Double($0.zeroSuppression) },
            make(79, "DIMAZIN", 0) { Double($0.angularZeroSuppression) },
            make(90, "DIMARCSYM", 0) { Double($0.arcLengthSymbol) },
            make(140, "DIMTXT", 0.18) { $0.textHeight },
            make(141, "DIMCEN", 0.09) { $0.centerMarkSize },
            make(142, "DIMTSZ", 0) { $0.tickSize },
            make(143, "DIMALTF", 25.4) { $0.alternateScale },
            make(144, "DIMLFAC", 1) { $0.linearScale },
            make(145, "DIMTVP", 0) { $0.textVerticalOffset },
            make(146, "DIMTFAC", 1) { $0.toleranceScale },
            make(147, "DIMGAP", 0.09) { $0.lineGap },
            make(148, "DIMALTRND", 0) { $0.alternateRounding },
            make(170, "DIMALT", 0) { flag($0.alternateUnits) },
            make(171, "DIMALTD", 2) { Double($0.alternateDecimals) },
            make(172, "DIMTOFL", 0) { flag($0.textOutsideExtensions) },
            make(173, "DIMSAH", 0) { flag($0.separateArrowBlocks) },
            make(174, "DIMTIX", 0) { flag($0.textInsideExtensions) },
            make(175, "DIMSOXD", 0) { flag($0.suppressOutsideExtensions) },
            make(179, "DIMADEC", 0) { Double($0.angularDecimals) },
            make(271, "DIMDEC", 4) { Double($0.decimals) },
            make(272, "DIMTDEC", 4) { Double($0.toleranceDecimals) },
            make(273, "DIMALTU", 2) { Double($0.alternateUnitFormat) },
            make(274, "DIMALTTD", 2) { Double($0.alternateToleranceDecimals) },
            make(275, "DIMAUNIT", 0) { Double($0.angularUnitFormat) },
            make(276, "DIMFRAC", 0) { Double($0.fractionFormat) },
            make(277, "DIMLUNIT", 2) { Double($0.linearUnitFormat) },
            make(278, "DIMDSEP", 46) { Double($0.decimalSeparator) },
            make(279, "DIMTMOVE", 0) { Double($0.textMovement) },
            make(280, "DIMJUST", 0) { Double($0.textJustification) },
            make(281, "DIMSD1", 0) { flag($0.suppressDimensionLine1) },
            make(282, "DIMSD2", 0) { flag($0.suppressDimensionLine2) },
            make(283, "DIMTOLJ", 1) { Double($0.toleranceJustification) },
            make(284, "DIMTZIN", 0) { Double($0.toleranceZeroSuppression) },
            make(285, "DIMALTZ", 0) { Double($0.alternateZeroSuppression) },
            make(286, "DIMALTTZ", 0) { Double($0.alternateToleranceZeroSuppression) },
            make(288, "DIMUPT", 0) { flag($0.cursorUpdate) },
            make(289, "DIMATFIT", 3) { Double($0.fit) },
            make(290, "DIMFXLON", 0) { flag($0.isExtensionLineLengthFixed) },
            make(295, "DIMTXTDIRECTION", 0) { flag($0.textRightToLeft) },
            make(371, "DIMLWD", -2) { Double($0.dimensionLineWeight) },
            make(372, "DIMLWE", -2) { Double($0.extensionLineWeight) },
        ]
    }()

    /// The variables a release stores.
    ///
    /// DXF output of R2000 and later has the others too, but a release that does not store one
    /// leaves it at the default in the decoded style.
    static func stores(_ variable: DimensionVariable, in version: DWG.Version) -> Bool {
        switch variable.code {
        case 49, 50, 69, 90, 290: return version >= .ac1021
        case 295: return version >= .ac1024
        default: return true
        }
    }

    mutating func compareDimensionStyles() throws {
        let version = store.container.version
        for record in dxfRecords("DIMSTYLE") {
            guard let handle = record.handle, store.map[handle] != nil else { continue }
            count("DIMSTYLE")
            guard case .dimensionStyle(let style)? = try store.tableRecord(handle) else {
                expect(false, "DIMSTYLE", handle, "not read as a dimension style")
                continue
            }
            checkObject("DIMSTYLE", handle, style.entry.object, record)
            let flags = record.int(70) ?? 0
            expect(style.entry.name == record.first(2), "DIMSTYLE", handle, "name")
            expect(style.entry.isXrefDependent == (flags & 16 != 0), "DIMSTYLE", handle, "xref")
            expect(style.unknownFlag == (flags & 1 != 0), "DIMSTYLE", handle, "bit 1")
            for variable in Self.dimensionVariables where Self.stores(variable, in: version) {
                // Group 70 is the flags and, a second time, the text background colour, so the
                // numbers of 70 are not read through `double`.
                let want = record.double(variable.code) ?? variable.defaultValue
                let got = variable.value(style)
                expect(
                    Self.near(got, want), "DIMSTYLE", handle,
                    "\(variable.name) \(got) is not \(want)")
                count("DIMSTYLE variable")
            }
            expect(style.postfix == (record.first(3) ?? ""), "DIMSTYLE", handle, "DIMPOST")
            expect(
                style.alternatePostfix == (record.first(4) ?? ""), "DIMSTYLE", handle, "DIMAPOST")
            let colors: [(Int, DWGColor)] = [
                (176, style.dimensionLineColor), (177, style.extensionLineColor),
                (178, style.textColor),
            ]
            for (code, got) in colors {
                expectDimensionColor(got, index: record.int(code) ?? 0, handle, "DIMCLR \(code)")
            }
            if version >= .ac1021 {
                let fill = record.all(70).count > 1 ? Int(record.all(70)[1]) ?? 0 : 0
                expectDimensionColor(style.textBackgroundColor, index: fill, handle, "DIMTFILLCLR")
            }
            let handles: [(Int, UInt64)] = [
                (340, style.textStyle), (341, style.leaderArrow), (342, style.arrowBlock),
                (343, style.arrowBlock1), (344, style.arrowBlock2),
            ]
            for (code, got) in handles {
                expect(got == record.handleValue(code), "DIMSTYLE", handle, "handle \(code)")
            }
            if version >= .ac1021 {
                expect(
                    style.dimensionLineType == record.handleValue(345), "DIMSTYLE", handle, "345")
                expect(
                    style.extensionLine1Type == record.handleValue(346), "DIMSTYLE", handle, "346")
                expect(
                    style.extensionLine2Type == record.handleValue(347), "DIMSTYLE", handle, "347")
            }
        }
    }

    /// The DXF holds a dimension style's colour as an index only.
    ///
    /// A true colour in the DWG is written there as an index near it, so for a true colour all that
    /// is checked is that the DXF has an index that is not by block.
    mutating func expectDimensionColor(
        _ got: DWGColor, index: Int, _ handle: UInt64, _ what: String
    ) {
        if case .rgb = got {
            count("DIMSTYLE true colour")
            expect(index != 0, "DIMSTYLE", handle, "\(what) is a true colour for index \(index)")
        } else {
            expect(
                got == ObjectReader.indexColor(index), "DIMSTYLE", handle,
                "\(what) \(got) is not \(index)")
        }
    }

    // MARK: Application names

    mutating func compareAppIDs() throws {
        for record in dxfRecords("APPID") {
            guard let handle = record.handle, store.map[handle] != nil else { continue }
            count("APPID")
            guard case .appID(let app)? = try store.tableRecord(handle) else {
                expect(false, "APPID", handle, "not read as an application name")
                continue
            }
            checkObject("APPID", handle, app.entry.object, record)
            expect(app.entry.name == record.first(2), "APPID", handle, "name \(app.entry.name)")
            let flags = record.int(70) ?? 0
            expect(app.entry.isXrefDependent == (flags & 16 != 0), "APPID", handle, "xref")
        }
    }

    // MARK: Block records and blocks

    /// The DXF records of each block's own BLOCK ...
    ///
    /// ENDBLK run, by the BLOCK's handle, and the entities of the ENTITIES section by owner. The
    /// DXF keeps model space, and the paper space that is active, in ENTITIES.
    func dxfBlockContents() -> (byBlock: [UInt64: [DXFRecord]], byOwner: [UInt64: [DXFRecord]]) {
        var byBlock: [UInt64: [DXFRecord]] = [:]
        var byOwner: [UInt64: [DXFRecord]] = [:]
        var open: UInt64?
        for item in sequence {
            if item.section == "BLOCKS" {
                if item.record.type == "BLOCK" {
                    open = item.record.handle
                    if let open { byBlock[open] = [] }
                } else if item.record.type == "ENDBLK" {
                    open = nil
                } else if let open {
                    byBlock[open, default: []].append(item.record)
                }
            } else if item.section == "ENTITIES" {
                byOwner[item.record.headerHandle(330), default: []].append(item.record)
            }
        }
        return (byBlock, byOwner)
    }

    /// Entities that belong to another entity and are not in a block record's own list.
    static let childTypes: Set<String> = ["VERTEX", "SEQEND", "ATTRIB"]

    mutating func compareBlockRecords() throws {
        let contents = dxfBlockContents()
        let version = store.container.version
        for record in dxfRecords("BLOCK_RECORD") {
            guard let handle = record.handle, store.map[handle] != nil else { continue }
            count("BLOCK_RECORD")
            guard case .blockHeader(let header)? = try store.tableRecord(handle) else {
                expect(false, "BLOCK_RECORD", handle, "not read as a block record")
                continue
            }
            checkObject("BLOCK_RECORD", handle, header.entry.object, record)
            let dxfName = record.first(2) ?? ""
            // The record of an anonymous block, or of a paper space, is written as `*` and a name
            // with no number. The BLOCK entity has the whole name, but AutoCAD numbers anonymous
            // blocks again when it writes the DXF, so only the part without the number is common.
            let numbered = dxfName.hasPrefix("*")
            if numbered {
                expect(
                    header.entry.name == Self.pairingName(dxfName), "BLOCK_RECORD", handle,
                    "numbered name \(header.entry.name) is not \(dxfName)")
                count("BLOCK_RECORD numbered")
            } else {
                expect(
                    header.entry.name == dxfName, "BLOCK_RECORD", handle,
                    "name \(header.entry.name)")
            }
            expect(header.layout == record.handleValue(340), "BLOCK_RECORD", handle, "layout")
            if version >= .ac1021 {
                expect(header.insertUnits == (record.int(70) ?? 0), "BLOCK_RECORD", handle, "units")
                expect(
                    header.isExplodable == ((record.int(280) ?? 0) != 0), "BLOCK_RECORD", handle,
                    "explodable")
                expect(
                    header.canScale == ((record.int(281) ?? 0) != 0), "BLOCK_RECORD", handle,
                    "scalable")
            }
            // The references to the block. The DXF leaves out some that the DWG has, which are
            // erased or held by other objects, so the references the two files have in common must
            // be the same and the others must be plausible.
            let refs = record.block("BLKREFS").filter { $0.code == 331 }
                .compactMap { UInt64($0.value, radix: 16) }
            expectHandles("BLOCK_RECORD", handle, "inserts", dwg: header.inserts, dxf: refs)
            expect(
                header.insertCount == header.inserts.count, "BLOCK_RECORD", handle, "insert count")
            for insert in header.inserts {
                // Something that refers to the block: an insert, or an entity of a class of the
                // file such as a table. A handle with no object is an entity that was erased.
                let type = try store.reader(for: insert)?.type
                let refers =
                    type == nil || type == ObjectType.insert || type == ObjectType.minsert
                    || (type ?? 0) >= ObjectType.firstClass
                expect(
                    refers, "BLOCK_RECORD", handle,
                    "insert \(Self.hex(insert)) is type \(type ?? -1)")
            }
            // The preview: the DXF holds it as hex text in groups 310.
            let preview = record.all(310).joined()
            let previewBytes = stride(from: 0, to: preview.count, by: 2).compactMap {
                offset -> UInt8? in
                let start = preview.index(preview.startIndex, offsetBy: offset)
                return UInt8(preview[start..<preview.index(start, offsetBy: 2)], radix: 16)
            }
            expect(
                header.preview == previewBytes, "BLOCK_RECORD", handle,
                "preview \(header.preview.count) bytes")

            // The BLOCK and ENDBLK entities.
            guard let block = records[header.blockEntity], block.type == "BLOCK" else {
                expect(
                    false, "BLOCK_RECORD", handle, "BLOCK entity \(Self.hex(header.blockEntity))")
                continue
            }
            expect(
                records[header.endBlockEntity]?.type == "ENDBLK", "BLOCK_RECORD", handle,
                "ENDBLK entity")
            expect(
                block.first(2) == dxfName, "BLOCK_RECORD", handle,
                "the BLOCK entity is called \(block.first(2) ?? "-")")
            let blockFlags = block.int(70) ?? 0
            expect(
                header.isAnonymous == (blockFlags & 1 != 0), "BLOCK_RECORD", handle, "anonymous bit"
            )
            expect(
                header.hasAttributeDefinitions == (blockFlags & 2 != 0), "BLOCK_RECORD", handle,
                "attdef bit")
            expect(header.isXRef == (blockFlags & 4 != 0), "BLOCK_RECORD", handle, "xref bit")
            expect(
                header.isXRefOverlay == (blockFlags & 8 != 0), "BLOCK_RECORD", handle, "overlay bit"
            )
            if let base = block.point(10, 20, 30) {
                expect(
                    Self.near(header.basePoint.x, base.x) && Self.near(header.basePoint.y, base.y)
                        && Self.near(header.basePoint.z, base.z), "BLOCK_RECORD", handle,
                    "base point")
            }
            expect(header.xrefPath == (block.first(1) ?? ""), "BLOCK_RECORD", handle, "xref path")
            expect(
                header.description == (block.first(4) ?? ""), "BLOCK_RECORD", handle, "description")

            // The entities the block owns are the ones the DXF has between BLOCK and ENDBLK, or,
            // for the spaces the DXF keeps in ENTITIES, the entities that name the block record as
            // their owner.
            if version >= .ac1018, !header.isXRef, !header.isXRefOverlay {
                let inBlock = contents.byBlock[header.blockEntity] ?? []
                let inEntities = contents.byOwner[handle] ?? []
                let expected = (inBlock + inEntities).filter { !Self.childTypes.contains($0.type) }
                    .compactMap(\.handle)
                expectHandles(
                    "BLOCK_RECORD", handle, "owned entities", dwg: header.ownedEntities,
                    dxf: expected)
                count("BLOCK_RECORD owned entities", by: header.ownedEntities.count)
            }
        }
    }

    mutating func count(_ kind: String, by amount: Int) { compared[kind, default: 0] += amount }

    mutating func compareBlocks() throws {
        for kind in ["BLOCK", "ENDBLK"] {
            for record in dxfRecords(kind) {
                guard let handle = record.handle, store.map[handle] != nil else { continue }
                count(kind)
                guard let entity = try store.entity(handle) else {
                    expect(false, kind, handle, "not read as an entity")
                    continue
                }
                switch entity.geometry {
                case .block(let block):
                    expect(kind == "BLOCK", kind, handle, "read as BLOCK")
                    // AutoCAD numbers anonymous blocks again in the DXF.
                    // One AutoCAD 2004 file also keeps the name of the dynamic block an anonymous
                    // block came from in the BLOCK entity, so for those only the `*` is common.
                    let want = record.first(2) ?? ""
                    if want.hasPrefix("*") {
                        let same = Self.pairingName(block.name) == Self.pairingName(want)
                        if !same { count("BLOCK anonymous name not comparable") }
                        expect(
                            same || block.name.hasPrefix("*") == false, kind, handle,
                            "name \(block.name) is not \(want)")
                    } else {
                        expect(
                            block.name == want, kind, handle, "name \(block.name) is not \(want)")
                    }
                case .endBlock:
                    expect(kind == "ENDBLK", kind, handle, "read as ENDBLK")
                default:
                    expect(false, kind, handle, "read as something else")
                }
                expect(entity.common.handle == handle, kind, handle, "handle")
            }
        }
    }

    // MARK: Dictionaries

    mutating func compareDictionaries() throws {
        for record in dxfRecords("DICTIONARY") {
            guard let handle = record.handle, store.map[handle] != nil else { continue }
            count("DICTIONARY")
            guard case .dictionary(let dictionary)? = try store.tableRecord(handle) else {
                expect(false, "DICTIONARY", handle, "not read as a dictionary")
                continue
            }
            checkObject("DICTIONARY", handle, dictionary.object, record)
            expect(
                dictionary.isHardOwner == ((record.int(280) ?? 0) == 1), "DICTIONARY", handle,
                "hard owner")
            expect(
                dictionary.cloningFlags == (record.int(281) ?? 0), "DICTIONARY", handle, "cloning")
            var expected: [DictionaryEntry] = []
            var pending: String?
            for (code, value) in record.plain {
                if code == 3 {
                    pending = value
                } else if code == 350 || code == 360, let name = pending {
                    expected.append(
                        DictionaryEntry(name: name, handle: UInt64(value, radix: 16) ?? 0))
                    pending = nil
                }
            }
            // Entries for objects that only one file has are left out, as in other handle lists.
            let got = dictionary.entries.filter { isShared($0.handle) }
            let want = expected.filter { isShared($0.handle) }
            expect(got == want, "DICTIONARY", handle, "entries \(got) are not \(want)")
            count("DICTIONARY entries", by: dictionary.entries.count)
            count("DICTIONARY entries compared", by: got.count)
        }
    }

    // MARK: Layouts

    mutating func compareLayouts() throws {
        for record in dxfRecords("LAYOUT") {
            guard let handle = record.handle, store.map[handle] != nil else { continue }
            count("LAYOUT")
            guard case .layout(let layout)? = try store.tableRecord(handle) else {
                expect(false, "LAYOUT", handle, "not read as a layout")
                continue
            }
            checkObject("LAYOUT", handle, layout.object, record)
            let plot = record.subclass("AcDbPlotSettings")
            let part = record.subclass("AcDbLayout")
            comparePlotSettings(layout.plot, plot, handle)

            expect(layout.name == part.first(1), "LAYOUT", handle, "name \(layout.name)")
            expect(layout.flags == part.int(70), "LAYOUT", handle, "flags")
            expect(layout.tabOrder == part.int(71), "LAYOUT", handle, "tab order")
            expect(layout.orthographicType == (part.int(76) ?? 0), "LAYOUT", handle, "ortho type")
            expectNear(layout.elevation, part.double(146) ?? 0, "LAYOUT", handle, "elevation")
            let pairs: [(String, (x: Double, y: Double), Int, Int)] = [
                ("limits min", layout.limitsMin, 10, 20), ("limits max", layout.limitsMax, 11, 21),
            ]
            for (label, got, x, y) in pairs {
                expectNear(got.x, part.double(x) ?? .nan, "LAYOUT", handle, "\(label) x")
                expectNear(got.y, part.double(y) ?? .nan, "LAYOUT", handle, "\(label) y")
            }
            let triples: [(String, DXF.Point, Int)] = [
                ("insertion base", layout.insertionBase, 12),
                ("extents min", layout.extentsMin, 14),
                ("extents max", layout.extentsMax, 15), ("ucs origin", layout.ucsOrigin, 13),
                ("ucs x", layout.ucsXAxis, 16), ("ucs y", layout.ucsYAxis, 17),
            ]
            for (label, got, code) in triples {
                if let want = part.point(code, code + 10, code + 20) {
                    expectNear(got.x, want.x, "LAYOUT", handle, "\(label) x")
                    expectNear(got.y, want.y, "LAYOUT", handle, "\(label) y")
                    expectNear(got.z, want.z, "LAYOUT", handle, "\(label) z")
                } else {
                    expect(false, "LAYOUT", handle, "\(label) missing in the DXF")
                }
            }
            expect(
                layout.paperSpaceBlock == part.handleValue(330), "LAYOUT", handle, "block record")
            expect(
                layout.lastActiveViewport == part.handleValue(331), "LAYOUT", handle,
                "active viewport")
            expect(layout.baseUCS == part.handleValue(346), "LAYOUT", handle, "base ucs")
            expect(layout.namedUCS == part.handleValue(345), "LAYOUT", handle, "named ucs")
            // The viewport that was active last is one of the layout's viewports, when it has any.
            if !layout.viewports.isEmpty, layout.lastActiveViewport != 0 {
                expect(
                    layout.viewports.contains(layout.lastActiveViewport), "LAYOUT", handle,
                    "viewports")
            }
            count("LAYOUT viewports", by: layout.viewports.count)
        }
    }

    mutating func comparePlotSettings(
        _ plot: PlotSettingsData, _ record: DXFRecord, _ handle: UInt64
    ) {
        let kind = "LAYOUT"
        expect(plot.pageSetupName == (record.first(1) ?? ""), kind, handle, "page setup name")
        expect(plot.printerName == (record.first(2) ?? ""), kind, handle, "printer")
        expect(plot.paperSize == (record.first(4) ?? ""), kind, handle, "paper size")
        expect(plot.styleSheet == (record.first(7) ?? ""), kind, handle, "style sheet")
        expect(plot.flags == record.int(70), kind, handle, "plot flags \(plot.flags)")
        expect(plot.paperUnits == record.int(72), kind, handle, "paper units")
        expect(plot.rotation == record.int(73), kind, handle, "rotation")
        expect(plot.plotType == record.int(74), kind, handle, "plot type")
        expect(plot.scaleType == record.int(75), kind, handle, "scale type")
        expect(plot.shadePlotMode == record.int(76), kind, handle, "shade plot mode")
        expect(plot.shadePlotResolution == record.int(77), kind, handle, "shade plot resolution")
        expect(plot.shadePlotDPI == record.int(78), kind, handle, "shade plot dpi")
        let numbers: [(String, Double, Int)] = [
            ("left margin", plot.leftMargin, 40), ("bottom margin", plot.bottomMargin, 41),
            ("right margin", plot.rightMargin, 42), ("top margin", plot.topMargin, 43),
            ("paper width", plot.paperWidth, 44), ("paper height", plot.paperHeight, 45),
            ("origin x", plot.plotOriginX, 46), ("origin y", plot.plotOriginY, 47),
            ("window min x", plot.windowMin.x, 48), ("window min y", plot.windowMin.y, 49),
            ("window max x", plot.windowMax.x, 140), ("window max y", plot.windowMax.y, 141),
            ("numerator", plot.scaleNumerator, 142), ("denominator", plot.scaleDenominator, 143),
            ("scale factor", plot.scaleFactor, 147),
            ("image origin x", plot.paperImageOrigin.x, 148),
            ("image origin y", plot.paperImageOrigin.y, 149),
        ]
        for (label, got, code) in numbers {
            expectNear(got, record.double(code) ?? .nan, kind, handle, label)
        }
    }

    // MARK: Control objects

    /// The type code of the control object of each table, by the table's name in the DXF.
    static let controlTypes: [String: Int] = [
        "BLOCK_RECORD": ObjectType.blockControl, "LAYER": ObjectType.layerControl,
        "STYLE": ObjectType.styleControl, "LTYPE": ObjectType.lineTypeControl,
        "VIEW": ObjectType.viewControl, "UCS": ObjectType.ucsControl,
        "VPORT": ObjectType.viewportControl, "APPID": ObjectType.appIDControl,
        "DIMSTYLE": ObjectType.dimensionStyleControl,
    ]

    mutating func compareControls() throws {
        for item in sequence where item.record.type == "TABLE" {
            guard let handle = item.record.handle, let table = item.record.first(2),
                let type = Self.controlTypes[table]
            else { continue }
            count("TABLE")
            count("TABLE \(table)")
            guard case .control(let got, let control)? = try store.tableRecord(handle) else {
                expect(false, "TABLE", handle, "\(table) is not read as a control object")
                continue
            }
            checkObject("TABLE", handle, control.object, item.record)
            expect(got == type, "TABLE", handle, "\(table) read as type \(got)")
            // A removed entry is a null handle in the list.
            var found = control.entries.filter { $0 != 0 }
            if table == "BLOCK_RECORD" { found += [control.modelSpace, control.paperSpace] }
            if table == "LTYPE" { found += [control.byLayer, control.byBlock] }
            let expected = sequence.filter { $0.section == "TABLES" && $0.record.type == table }
                .compactMap(\.record.handle)
            expect(
                found.count == Set(found).count, "TABLE", handle, "\(table) lists a handle twice")
            expect(
                Set(found.filter(isShared)) == Set(expected.filter(isShared)), "TABLE", handle,
                "\(table) lists \(found.count) entries for \(expected.count)")
            count("TABLE entries", by: found.count)
            count("TABLE entries compared", by: found.filter(isShared).count)
            if table == "BLOCK_RECORD" {
                let names = Dictionary(
                    uniqueKeysWithValues: dxfRecords("BLOCK_RECORD").compactMap { record in
                        record.handle.map { ($0, record.first(2) ?? "") }
                    })
                expect(names[control.modelSpace] == "*Model_Space", "TABLE", handle, "model space")
                expect(names[control.paperSpace] == "*Paper_Space", "TABLE", handle, "paper space")
            }
            if table == "LTYPE" {
                expect(
                    try name(ofLineType: control.byLayer) == "ByLayer", "TABLE", handle, "BYLAYER")
                expect(
                    try name(ofLineType: control.byBlock) == "ByBlock", "TABLE", handle, "BYBLOCK")
            }
        }
    }
}

@Suite("Table records against AutoCAD's DXF")
struct TableOracleTests {
    /// What a finished comparison must show for a drawing: no difference, and every record the DXF
    /// has either compared or accounted for as one that only the DXF has.
    func check(_ oracle: TableOracle, _ name: String, only expected: [String: Int]) {
        #expect(oracle.mismatches.isEmpty, "\(name): \(oracle.mismatches.prefix(20))")
        for kind in TableOracle.comparedKinds {
            let dxf = oracle.dxfRecords(kind).count
            let seen =
                (oracle.compared[kind] ?? 0) + (oracle.compared["\(kind) only in the DXF"] ?? 0)
            #expect(seen == dxf, "\(name) \(kind): \(seen) of \(dxf) DXF records")
        }
        let tables = oracle.sequence.filter { $0.record.type == "TABLE" }.count
        #expect(oracle.compared["TABLE"] == tables, "\(name) tables")
        for kind in ["LAYER", "APPID", "BLOCK_RECORD"] {
            #expect(
                oracle.compared["\(kind) paired by name"]
                    == oracle.compared["\(kind) only in the DXF"],
                "\(name) \(kind) pairs")
        }
        let unshared = oracle.compared.filter { $0.key.contains(" only in the ") }
        #expect(unshared == expected, "\(name): \(unshared.sorted { $0.key < $1.key })")
    }

    @Test("the small AutoCAD drawing's tables equal those in its DXF export")
    func smallDrawing() throws {
        var oracle = try TableOracle(
            dwg: try Fixtures.data("BLOCKPOINTPARAMETER.dwg"),
            dxf: Fixtures.directory.appendingPathComponent("BLOCKPOINTPARAMETER.dxf"))
        try oracle.run()
        check(oracle, "BLOCKPOINTPARAMETER", only: [:])
        #expect(oracle.compared["LAYER"] == 1)
        #expect(oracle.compared["LTYPE"] == 3)
        #expect(oracle.compared["STYLE"] == 3)
        #expect(oracle.compared["DIMSTYLE"] == 2)
        #expect(oracle.compared["APPID"] == 12)
        #expect(oracle.compared["BLOCK_RECORD"] == 6)
        #expect(oracle.compared["DICTIONARY"] == 34)
        #expect(oracle.compared["LAYOUT"] == 3)
        #expect(oracle.compared["TABLE"] == 9)
    }

    /// The counts of objects that only one file of a sample has, by kind.
    ///
    /// AutoCAD made these when it saved the two files, so the numbers are what each pair of files
    /// has. Every record of a table that the DXF alone has is paired with one of the DWG's by name.
    static let unshared: [String: [String: Int]] = [
        "sample_AC1018": [
            "APPID only in the DWG": 8, "APPID only in the DXF": 7,
            "BLOCK only in the DWG": 1, "BLOCK only in the DXF": 1,
            "BLOCK_RECORD only in the DWG": 1, "BLOCK_RECORD only in the DXF": 1,
            "DICTIONARY only in the DWG": 47, "DICTIONARY only in the DXF": 45,
            "ENDBLK only in the DWG": 1, "ENDBLK only in the DXF": 1,
            "LAYER only in the DWG": 2, "LAYER only in the DXF": 2,
        ],
        "sample_AC1024": [
            "APPID only in the DWG": 2, "APPID only in the DXF": 1,
            "BLOCK only in the DWG": 1, "BLOCK only in the DXF": 1,
            "BLOCK_RECORD only in the DWG": 1, "BLOCK_RECORD only in the DXF": 1,
            "DICTIONARY only in the DWG": 38, "DICTIONARY only in the DXF": 36,
            "ENDBLK only in the DWG": 1, "ENDBLK only in the DXF": 1,
        ],
        "sample_AC1027": [
            "BLOCK only in the DWG": 1, "BLOCK only in the DXF": 1,
            "BLOCK_RECORD only in the DWG": 1, "BLOCK_RECORD only in the DXF": 1,
            "DICTIONARY only in the DWG": 11, "DICTIONARY only in the DXF": 11,
            "ENDBLK only in the DWG": 1, "ENDBLK only in the DXF": 1,
        ],
        "sample_AC1032": [
            "BLOCK only in the DWG": 1, "BLOCK only in the DXF": 1,
            "BLOCK_RECORD only in the DWG": 1, "BLOCK_RECORD only in the DXF": 1,
            "DICTIONARY only in the DWG": 2, "DICTIONARY only in the DXF": 2,
            "ENDBLK only in the DWG": 1, "ENDBLK only in the DXF": 1,
        ],
    ]

    @Test("every AutoCAD sample from R2004 to R2018 has the tables its DXF has")
    func corpus() throws {
        guard let corpus = Fixtures.corpus else { return }  // needs DWG_CORPUS: skipped without it
        for name in Fixtures.corpusNames {
            let data = [UInt8](try Data(contentsOf: corpus.appendingPathComponent("\(name).dwg")))
            var oracle = try TableOracle(
                dwg: data, dxf: corpus.appendingPathComponent("\(name)_ascii.dxf"))
            try oracle.run()
            check(oracle, name, only: Self.unshared[name] ?? [:])
        }
    }
}
