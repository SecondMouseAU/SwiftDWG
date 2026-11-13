// Derived from ACadSharp (MIT), src/ACadSharp/Header/CadHeader.cs (which variables there are and
// what DXF calls them) and src/ACadSharp/IO/DWG/DwgHeaderHandlesCollection.cs (the handle names).
// See NOTICE.md.

import Foundation

/// What the header variables section of a drawing holds: the system variables, and the handles of
/// the objects the header points at.
struct HeaderVariables: Equatable {
    /// One header variable's value.
    enum Value: Equatable {
        /// A short or long integer, and the numbers a byte holds.
        case int(Int)
        /// A real number. A date is a Julian date, and a length of time a number of days, in both
        /// with the time of day as the fraction.
        case double(Double)
        /// A text.
        case string(String)
        /// A single bit in the file.
        case bool(Bool)
        /// A 2D point.
        case point2(x: Double, y: Double)
        /// A 3D point.
        case point3(x: Double, y: Double, z: Double)
        /// The handle of an object, for a variable the drawing keeps by reference (such as the
        /// current layer). DXF writes the name of the object where the DWG keeps its handle.
        case handle(UInt64)
        /// A colour: its index (0 is by block, 256 is by layer) and, when the drawing gives one,
        /// the true colour as `0xRRGGBB`. The index of a true colour is the leading short the file
        /// has for it, which was 0 in every drawing seen.
        case color(index: Int, rgb: UInt32?)
    }

    /// The variables, keyed by the name DXF gives them in its HEADER section, such as `$INSUNITS`,
    /// `$EXTMIN`, `$LTSCALE` and `$DIMSCALE`.
    ///
    /// A variable the release does not store is absent. The creation and last save times are
    /// `$TDCREATE` and `$TDUPDATE` (local time) in R13 and R14, and `$TDUCREATE` and `$TDUUPDATE`
    /// (universal time) from R2000. The variables that DXF writes as an object
    /// name (`$CLAYER`, `$TEXTSTYLE`, `$DIMSTYLE` and so on) are here as a `.handle`, and are in
    /// `handles` as well.
    var values: [String: Value] = [:]

    /// The handles of the objects the header points at, keyed by ACadSharp's names for them.
    ///
    /// The names are the ones in `DwgHeaderHandlesCollection`. A name is absent when the release
    /// does not store that handle. A handle of 0 is the null handle: the variable points at
    /// nothing.
    ///
    /// - Current settings: `CLAYER`, `TEXTSTYLE`, `CELTYPE`, `CMATERIAL` (R2007 and later),
    ///   `DIMSTYLE`, `CMLSTYLE`, and the dimension style's own `DIMTXSTY`, `DIMLDRBLK`, `DIMBLK`,
    ///   `DIMBLK1`, `DIMBLK2` and, from R2007, `DIMLTYPE`, `DIMLTEX1`, `DIMLTEX2`.
    /// - The user coordinate systems: `UCSNAME_PSPACE`, `PUCSORTHOREF`, `PUCSBASE` for paper space
    ///   and `UCSNAME_MSPACE`, `UCSORTHOREF`, `UCSBASE` for model space (the ones with `ORTHOREF`
    ///   and `BASE` from R2000).
    /// - The table control objects: `BLOCK_CONTROL_OBJECT`, `LAYER_CONTROL_OBJECT`,
    ///   `STYLE_CONTROL_OBJECT`, `LINETYPE_CONTROL_OBJECT`, `VIEW_CONTROL_OBJECT`,
    ///   `UCS_CONTROL_OBJECT`, `VPORT_CONTROL_OBJECT`, `APPID_CONTROL_OBJECT`,
    ///   `DIMSTYLE_CONTROL_OBJECT`, and `VIEWPORT_ENTITY_HEADER_CONTROL_OBJECT` (R13 to R2000).
    /// - Dictionaries: `DICTIONARY_NAMED_OBJECTS` (the root), `DICTIONARY_ACAD_GROUP`,
    ///   `DICTIONARY_ACAD_MLINESTYLE`, and from R2000 `DICTIONARY_LAYOUTS`,
    ///   `DICTIONARY_PLOTSETTINGS`, `DICTIONARY_PLOTSTYLES`, from R2004 `DICTIONARY_MATERIALS` and
    ///   `DICTIONARY_COLORS`, from R2007 `DICTIONARY_VISUALSTYLE`.
    /// - The built-in block records and line types: `PAPER_SPACE`, `MODEL_SPACE`, `BYLAYER`,
    ///   `BYBLOCK`, `CONTINUOUS`.
    /// - Other: `CPSNID` (only when `$CEPSNTYPE` is 3), `INTERFEREOBJVS`, `INTERFEREVPVS`,
    ///   `DRAGVS` (R2007 and later).
    /// - Not in ACadSharp's collection: `CURRENT_VIEWPORT_ENTITY_HEADER` (before R2004) and
    ///   `UNKNOWN_R2013`, the extra handle that R2013 and later write after the visual style
    ///   dictionary. ACadSharp stores it over `DICTIONARY_VISUALSTYLE`, which loses that handle.
    var handles: [String: UInt64] = [:]

    /// The integer value of a variable.
    ///
    /// A bit is 0 or 1, and a colour is its index.
    func int(_ name: String) -> Int? {
        switch values[name] {
        case .int(let value): return value
        case .bool(let value): return value ? 1 : 0
        case .color(let index, _): return index
        default: return nil
        }
    }

    /// The real value of a variable.
    func double(_ name: String) -> Double? {
        if case .double(let value) = values[name] { return value }
        return nil
    }

    /// The text value of a variable.
    func string(_ name: String) -> String? {
        if case .string(let value) = values[name] { return value }
        return nil
    }

    /// The bit value of a variable.
    func bool(_ name: String) -> Bool? {
        if case .bool(let value) = values[name] { return value }
        return nil
    }

    /// The 2D point value of a variable.
    func point2(_ name: String) -> (x: Double, y: Double)? {
        if case .point2(let x, let y) = values[name] { return (x, y) }
        return nil
    }

    /// The 3D point value of a variable.
    func point3(_ name: String) -> (x: Double, y: Double, z: Double)? {
        if case .point3(let x, let y, let z) = values[name] { return (x, y, z) }
        return nil
    }

    /// The handle value of a variable.
    func handle(_ name: String) -> UInt64? {
        if case .handle(let value) = values[name] { return value }
        return nil
    }
}
