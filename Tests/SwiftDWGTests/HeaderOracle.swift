import Foundation

@testable import SwiftDWG

/// Compares what `HeaderReader` read with AutoCAD's own DXF export of the same drawing.
struct HeaderOracle {
    /// What came of comparing one variable.
    enum Outcome: Equatable {
        /// The DWG value equals AutoCAD's.
        case matched
        /// The two differ: the DWG value and AutoCAD's, as text.
        case differs(String)
        /// The two agree within an allowance the text states, such as a second between two saves.
        case bounded(String)
        /// The variable could not be compared, and why.
        case notCompared(String)
    }

    /// One seconds, as a part of a day.
    static let second = 1.0 / 86_400.0

    let dxf: DXFReference
    /// The release, which a few variables depend on.
    let release: String
    /// Whether a text that differs from the DXF's only in case counts as agreeing, as for an R14
    /// file read against the DXF of the same drawing saved as R2000.
    var ignoringCase = false

    /// The DXF table that holds the object a handle variable points at, or `nil` when the variable
    /// is a handle written as one.
    private static let tableOfName: [String: String] = [
        "$CLAYER": "LAYER", "$TEXTSTYLE": "STYLE", "$DIMTXSTY": "STYLE", "$CELTYPE": "LTYPE",
        "$DIMLTYPE": "LTYPE", "$DIMLTEX1": "LTYPE", "$DIMLTEX2": "LTYPE",
        "$DIMSTYLE": "DIMSTYLE", "$DIMBLK": "BLOCK_RECORD", "$DIMBLK1": "BLOCK_RECORD",
        "$DIMBLK2": "BLOCK_RECORD", "$DIMLDRBLK": "BLOCK_RECORD", "$UCSNAME": "UCS",
        "$PUCSNAME": "UCS", "$UCSBASE": "UCS", "$PUCSBASE": "UCS", "$UCSORTHOREF": "UCS",
        "$PUCSORTHOREF": "UCS",
    ]

    /// The table a control object handle belongs to.
    static let controlObjects: [String: String] = [
        "BLOCK_CONTROL_OBJECT": "BLOCK_RECORD", "LAYER_CONTROL_OBJECT": "LAYER",
        "STYLE_CONTROL_OBJECT": "STYLE", "LINETYPE_CONTROL_OBJECT": "LTYPE",
        "VIEW_CONTROL_OBJECT": "VIEW", "UCS_CONTROL_OBJECT": "UCS",
        "VPORT_CONTROL_OBJECT": "VPORT", "APPID_CONTROL_OBJECT": "APPID",
        "DIMSTYLE_CONTROL_OBJECT": "DIMSTYLE",
    ]

    /// The root dictionary entry that each dictionary handle is.
    static let dictionaries: [String: String] = [
        "DICTIONARY_ACAD_GROUP": "ACAD_GROUP", "DICTIONARY_ACAD_MLINESTYLE": "ACAD_MLINESTYLE",
        "DICTIONARY_LAYOUTS": "ACAD_LAYOUT", "DICTIONARY_PLOTSETTINGS": "ACAD_PLOTSETTINGS",
        "DICTIONARY_PLOTSTYLES": "ACAD_PLOTSTYLENAME", "DICTIONARY_MATERIALS": "ACAD_MATERIAL",
        "DICTIONARY_COLORS": "ACAD_COLOR", "DICTIONARY_VISUALSTYLE": "ACAD_VISUALSTYLE",
    ]

    /// The variables that AutoCAD wrote a second or so after the DWG, because saving updates them.
    private static let updatedBySaving: Set<String> = [
        "$TDUPDATE", "$TDUUPDATE", "$TDINDWG", "$TDUSRTIMER",
    ]

    /// The dates and lengths of time.
    ///
    /// DXF writes them with 9 or 10 decimals of a day, so they are compared to 1e-9 of a day (about
    /// 0.1 ms), and not to a relative 1e-9 of a Julian date, which is a matter of minutes.
    private static let times: Set<String> = [
        "$TDCREATE", "$TDUCREATE", "$TDUPDATE", "$TDUUPDATE", "$TDINDWG", "$TDUSRTIMER",
    ]
    private static let timeTolerance = 1e-9

    /// Compares a variable the DWG has with the DXF's.
    func compare(_ name: String, _ value: HeaderVariables.Value) -> Outcome {
        guard let tags = dxf.header[name] else { return .notCompared("not in the DXF HEADER") }
        guard let first = tags.first else { return .notCompared("the DXF gives no value") }
        switch value {
        case .int(let read):
            guard let expected = first.integer else { return .differs("DXF \(first.value)") }
            if name == "$XCLIPFRAME", ["AC1018", "AC1021"].contains(release), read == 2,
                expected == 0
            {
                return .notCompared(
                    "the DXF says 0 and the DWG 2; ACadSharp notes that before R2010 the value is "
                        + "0 or 1 only, which is not confirmed")
            }
            return read == expected ? .matched : .differs("\(read) against \(expected)")
        case .bool(let read):
            guard let expected = first.integer else { return .differs("DXF \(first.value)") }
            return read == (expected != 0) ? .matched : .differs("\(read) against \(expected)")
        case .double(let read):
            return compare(name, double: read, first)
        case .string(let read):
            if name == "$VERSIONGUID" { return compareVersionGUID(read, first.value) }
            if read == first.value { return .matched }
            if ignoringCase, read.lowercased() == first.value.lowercased() {
                return .bounded("equal but for case: \(read) and \(first.value)")
            }
            return .differs("\"\(read)\" against \"\(first.value)\"")
        case .point2(let x, let y):
            return comparePoint([x, y], tags)
        case .point3(let x, let y, let z):
            return comparePoint([x, y, z], tags)
        case .handle(let read):
            return compare(name, handle: read, first)
        case .color(let index, let rgb):
            if rgb != nil {
                return .notCompared("a true colour, where DXF writes the nearest palette index")
            }
            return first.integer == index ? .matched : .differs("\(index) against \(first.value)")
        }
    }

    private func compare(_ name: String, double read: Double, _ tag: DXFReference.Tag) -> Outcome {
        guard let expected = tag.number else { return .differs("DXF \(tag.value)") }
        if Self.times.contains(name) {
            let delta = expected - read
            if abs(delta) <= Self.timeTolerance { return .matched }
            // AutoCAD saved the DXF after the DWG, which moved these on by about a second.
            if Self.updatedBySaving.contains(name), delta > 0, delta <= 5 * Self.second {
                return .bounded("the DXF is \(String(format: "%.1f", delta / Self.second)) s later")
            }
            return .differs("\(read) against \(expected)")
        }
        return Self.close(read, expected) ? .matched : .differs("\(read) against \(expected)")
    }

    private func comparePoint(_ read: [Double], _ tags: [DXFReference.Tag]) -> Outcome {
        let expected = tags.compactMap(\.number)
        guard expected.count == read.count else {
            return .differs("DXF has \(expected.count) numbers")
        }
        return zip(read, expected).allSatisfy { Self.close($0, $1) }
            ? .matched : .differs("\(read) against \(expected)")
    }

    /// AutoCAD makes a new version GUID each time it saves, so the DXF has another one: the
    /// reference can only say that the DWG's has the shape of a GUID.
    private func compareVersionGUID(_ read: String, _ expected: String) -> Outcome {
        let parts = read.dropFirst().dropLast().split(
            separator: "-", omittingEmptySubsequences: false)
        let isGUID =
            read.hasPrefix("{") && read.hasSuffix("}") && parts.map(\.count) == [8, 4, 4, 4, 12]
            && parts.allSatisfy { $0.allSatisfy(\.isHexDigit) }
        guard isGUID else { return .differs("\"\(read)\" is not a GUID") }
        return read == expected ? .matched : .notCompared("AutoCAD makes a new GUID at each save")
    }

    /// Compares a handle variable, which DXF writes as the name of the object or as a handle.
    private func compare(_ name: String, handle read: UInt64, _ tag: DXFReference.Tag) -> Outcome {
        if name == "$HANDSEED" {
            guard let expected = tag.handle else { return .differs("DXF \(tag.value)") }
            // The DXF came from the drawing after it was saved to DWG, and more handles are used.
            return read <= expected
                ? .bounded("the DXF seed is \(expected), the DWG's \(read)")
                : .differs("\(read) is above the DXF's \(expected)")
        }
        if name == "$CMLSTYLE" {
            return Self.expect(read, dxf.mlineStyle(tag.value), "MLINESTYLE \(tag.value)")
        }
        guard let table = Self.tableOfName[name] else {
            guard let expected = tag.handle else { return .differs("DXF \(tag.value)") }
            return read == expected ? .matched : .differs("\(read) against \(expected)")
        }
        let objectName = tag.value
        if objectName.isEmpty {
            return read == 0 ? .matched : .differs("\(read) where the DXF names nothing")
        }
        // DXF writes the built-in arrowheads without the underscore their blocks are named with.
        guard let expected = dxf.entry(table, objectName) ?? dxf.entry(table, "_" + objectName)
        else {
            return .notCompared("\(objectName) is not in the DXF's \(table) table")
        }
        return read == expected ? .matched : .differs("\(read) against \(expected) (\(objectName))")
    }

    /// Compares a handle the header points at, by name, with where the DXF has that object.
    func compare(pointer name: String, _ read: UInt64) -> Outcome {
        if let table = Self.controlObjects[name] {
            return Self.expect(read, dxf.tableHandles[table], "the \(table) table")
        }
        if let entry = Self.dictionaries[name] {
            return Self.expect(read, dxf.rootEntries[entry], "root entry \(entry)")
        }
        switch name {
        case "DICTIONARY_NAMED_OBJECTS":
            return Self.expect(read, dxf.rootDictionary, "the root dictionary")
        case "PAPER_SPACE":
            return Self.expect(read, dxf.entry("BLOCK_RECORD", "*Paper_Space"), name)
        case "MODEL_SPACE":
            return Self.expect(read, dxf.entry("BLOCK_RECORD", "*Model_Space"), name)
        case "BYLAYER":
            return Self.expect(read, dxf.entry("LTYPE", "ByLayer"), name)
        case "BYBLOCK":
            return Self.expect(read, dxf.entry("LTYPE", "ByBlock"), name)
        case "CONTINUOUS":
            return Self.expect(read, dxf.entry("LTYPE", "Continuous"), name)
        default:
            return .notCompared("no DXF counterpart")
        }
    }

    private static func expect(_ read: UInt64, _ expected: UInt64?, _ what: String) -> Outcome {
        guard let expected else { return .notCompared("\(what) is not in the DXF") }
        return read == expected ? .matched : .differs("\(read) against \(expected) (\(what))")
    }

    /// Whether two reals agree to 1e-9 of their size.
    static func close(_ lhs: Double, _ rhs: Double) -> Bool {
        lhs == rhs || abs(lhs - rhs) <= 1e-9 * max(abs(lhs), abs(rhs))
    }
}
