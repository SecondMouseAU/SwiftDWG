// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgHeaderReader.cs, the part
// of it that reads the dimension variables. See NOTICE.md.
//
// A dimension variable that R13 and R14 kept as a bit or a byte, R2000 moved to a place of its own
// and widened to a bit short. The release decides which of the two blocks below a file has.

import Foundation

extension HeaderReader.Parser {
    /// Reads the dimension variables, and the handles of the objects a dimension style points at.
    mutating func readDimensionVariables() throws {
        if r13to14 { try readOldDimensionBlock() }
        let scales = [
            "$DIMSCALE", "$DIMASZ", "$DIMEXO", "$DIMDLI", "$DIMEXE", "$DIMRND", "$DIMDLE", "$DIMTP",
            "$DIMTM",
        ]
        for name in scales { try real(name) }
        if r2007Plus {
            try real("$DIMFXL")
            try real("$DIMJOGANG")
            try short("$DIMTFILL")
            try color("$DIMTFILLCLR")
        }
        if r2000Plus {
            for name in ["$DIMTOL", "$DIMLIM", "$DIMTIH", "$DIMTOH", "$DIMSE1", "$DIMSE2"] {
                try flag(name)
            }
            for name in ["$DIMTAD", "$DIMZIN", "$DIMAZIN"] { try short(name) }
        }
        if r2007Plus { try short("$DIMARCSYM") }
        let sizes = [
            "$DIMTXT", "$DIMCEN", "$DIMTSZ", "$DIMALTF", "$DIMLFAC", "$DIMTVP", "$DIMTFAC",
            "$DIMGAP",
        ]
        for name in sizes { try real(name) }
        if r13to14 {
            for name in ["$DIMPOST", "$DIMAPOST", "$DIMBLK", "$DIMBLK1", "$DIMBLK2"] {
                try string(name)
            }
        }
        if r2000Plus {
            try real("$DIMALTRND")
            try flag("$DIMALT")
            try short("$DIMALTD")
            for name in ["$DIMTOFL", "$DIMSAH", "$DIMTIX", "$DIMSOXD"] { try flag(name) }
        }
        for name in ["$DIMCLRD", "$DIMCLRE", "$DIMCLRT"] { try color(name) }
        if r2000Plus {
            try readNewDimensionBlock()
            for name in ["DIMTXSTY", "DIMLDRBLK", "DIMBLK", "DIMBLK1", "DIMBLK2"] {
                try handle(name)
            }
        }
        if r2007Plus {
            for name in ["DIMLTYPE", "DIMLTEX1", "DIMLTEX2"] { try handle(name) }
        }
        if r2000Plus {
            try short("$DIMLWD")
            try short("$DIMLWE")
        }
    }

    /// The dimension variables R13 and R14 have as bits and bytes.
    private mutating func readOldDimensionBlock() throws {
        let switches = [
            "$DIMTOL", "$DIMLIM", "$DIMTIH", "$DIMTOH", "$DIMSE1", "$DIMSE2", "$DIMALT", "$DIMTOFL",
            "$DIMSAH", "$DIMTIX", "$DIMSOXD",
        ]
        for name in switches { try flag(name) }
        try byte("$DIMALTD")
        try byte("$DIMZIN")
        try flag("$DIMSD1")
        try flag("$DIMSD2")
        try byte("$DIMTOLJ")
        try byte("$DIMJUST")
        try byte("$DIMFIT")
        try flag("$DIMUPT")
        for name in ["$DIMTZIN", "$DIMALTZ", "$DIMALTTZ", "$DIMTAD"] { try byte(name) }
        for name in ["$DIMUNIT", "$DIMAUNIT", "$DIMDEC", "$DIMTDEC", "$DIMALTU", "$DIMALTTD"] {
            try short(name)
        }
        try handle("DIMTXSTY")
    }

    /// The dimension variables from R2000 that follow the three dimension colours.
    private mutating func readNewDimensionBlock() throws {
        let shorts = [
            "$DIMADEC", "$DIMDEC", "$DIMTDEC", "$DIMALTU", "$DIMALTTD", "$DIMAUNIT", "$DIMFRAC",
            "$DIMLUNIT", "$DIMDSEP", "$DIMTMOVE", "$DIMJUST",
        ]
        for name in shorts { try short(name) }
        try flag("$DIMSD1")
        try flag("$DIMSD2")
        for name in ["$DIMTOLJ", "$DIMTZIN", "$DIMALTZ", "$DIMALTTZ"] { try short(name) }
        try flag("$DIMUPT")
        try short("$DIMATFIT")
        if r2007Plus { try flag("$DIMFXLON") }
        if r2010Plus {
            try flag("$DIMTXTDIRECTION")
            try real("$DIMALTMZF")
            try string("$DIMALTMZS")
            try real("$DIMMZF")
            try string("$DIMMZS")
        }
    }
}
