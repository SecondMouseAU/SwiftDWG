// The order of the variables, and the group codes, are AutoCAD's own: they were read off the HEADER
// section of its DXF exports of the same drawing (see Tests/SwiftDWGTests/HeaderTextTests.swift).
// The names are the ones `HeaderReader` gives its variables, which are DXF's.

/// The HEADER section of the DXF text, variable by variable: the order AutoCAD writes them in, and
/// the group code or codes each is written with.
///
/// A variable is written when the release stores it, so the list is the same for every release and
/// a release has the part of it that it keeps. Where AutoCAD's order is the same in every release
/// it has a sample for, this is that order. The variables R14 keeps and R2000 moved to the
/// registry (`$DRAGMODE`, `$OSMODE`, `$BLIPMODE`, `$COORDS`, `$ATTDIA`, `$ATTREQ`) are placed where
/// AutoCAD's DXF of an R12 drawing has them, which is the only DXF of an older release there is.
enum HeaderLayout {
    /// The table that a handle is the name of an entry in, for a variable DXF writes as a name.
    enum Table {
        case layer
        case textStyle
        case lineType
        case dimensionStyle
        case mlineStyle
        case block
        case ucs
    }

    /// What a variable is, and so how it is written.
    enum Kind {
        /// An integer, or a bit, in one group.
        case integer(Int)
        /// A real number in one group.
        case real(Int)
        /// A text in one group.
        case text(Int)
        /// Two reals, in groups 10 and 20.
        case point2
        /// Three reals, in groups 10, 20 and 30.
        case point3
        /// A colour, written as its palette index.
        case color(Int)
        /// The name of the entry a handle points at, in one group. A handle that is null, or that
        /// names nothing the file holds, leaves the variable out.
        case name(Int, Table)
        /// The same, but a null handle is written as an empty name, as AutoCAD does for a
        /// variable that may be unset.
        case nameOrEmpty(Int, Table)
        /// A handle, written as upper-case hexadecimal.
        case handle(Int)
        /// `$XCLIPFRAME`, which the format kept as a bit until R2010 and AutoCAD wrote in group 290
        /// to R2007 and in 280 from R2010.
        case clipFrame
    }

    /// One variable of the HEADER section.
    struct Entry {
        let name: String
        let kind: Kind

        static func integer(_ name: String, _ code: Int) -> Entry {
            Entry(name: name, kind: .integer(code))
        }
        static func real(_ name: String, _ code: Int) -> Entry {
            Entry(name: name, kind: .real(code))
        }
        static func text(_ name: String, _ code: Int) -> Entry {
            Entry(name: name, kind: .text(code))
        }
        static func point2(_ name: String) -> Entry { Entry(name: name, kind: .point2) }
        static func point3(_ name: String) -> Entry { Entry(name: name, kind: .point3) }
        static func color(_ name: String, _ code: Int) -> Entry {
            Entry(name: name, kind: .color(code))
        }
        static func name(_ name: String, _ code: Int, _ table: Table) -> Entry {
            Entry(name: name, kind: .name(code, table))
        }
        static func nameOrEmpty(_ name: String, _ code: Int, _ table: Table) -> Entry {
            Entry(name: name, kind: .nameOrEmpty(code, table))
        }
        static func handle(_ name: String, _ code: Int) -> Entry {
            Entry(name: name, kind: .handle(code))
        }
        static func clipFrame() -> Entry { Entry(name: "$XCLIPFRAME", kind: .clipFrame) }
    }

    /// Every variable that is written, in the order AutoCAD writes them.
    ///
    /// `$ACADVER` and `$DWGCODEPAGE` come from the file header and `$MEASUREMENT` from the template
    /// section, and the writer puts them among the decoded values.
    static let entries: [Entry] = [
        .text("$ACADVER", 1),
        .text("$DWGCODEPAGE", 3),
        .integer("$REQUIREDVERSIONS", 160),
        .point3("$INSBASE"),
        .point3("$EXTMIN"),
        .point3("$EXTMAX"),
        .point2("$LIMMIN"),
        .point2("$LIMMAX"),
        .integer("$ORTHOMODE", 70),
        .integer("$REGENMODE", 70),
        .integer("$FILLMODE", 70),
        .integer("$QTEXTMODE", 70),
        .integer("$MIRRTEXT", 70),
        .integer("$DRAGMODE", 70),  // R14 only
        .real("$LTSCALE", 40),
        .integer("$OSMODE", 70),  // R14 only
        .integer("$ATTMODE", 70),
        .real("$TEXTSIZE", 40),
        .real("$TRACEWID", 40),
        .name("$TEXTSTYLE", 7, .textStyle),
        .name("$CLAYER", 8, .layer),
        .name("$CELTYPE", 6, .lineType),
        .color("$CECOLOR", 62),
        .real("$CELTSCALE", 40),
        .integer("$DISPSILH", 70),
        .real("$DIMSCALE", 40),
        .real("$DIMASZ", 40),
        .real("$DIMEXO", 40),
        .real("$DIMDLI", 40),
        .real("$DIMRND", 40),
        .real("$DIMDLE", 40),
        .real("$DIMEXE", 40),
        .real("$DIMTP", 40),
        .real("$DIMTM", 40),
        .real("$DIMTXT", 40),
        .real("$DIMCEN", 40),
        .real("$DIMTSZ", 40),
        .integer("$DIMTOL", 70),
        .integer("$DIMLIM", 70),
        .integer("$DIMTIH", 70),
        .integer("$DIMTOH", 70),
        .integer("$DIMSE1", 70),
        .integer("$DIMSE2", 70),
        .integer("$DIMTAD", 70),
        .integer("$DIMZIN", 70),
        .nameOrEmpty("$DIMBLK", 1, .block),
        .integer("$DIMASO", 70),
        .integer("$DIMSHO", 70),
        .text("$DIMPOST", 1),
        .text("$DIMAPOST", 1),
        .integer("$DIMALT", 70),
        .integer("$DIMALTD", 70),
        .real("$DIMALTF", 40),
        .real("$DIMLFAC", 40),
        .integer("$DIMTOFL", 70),
        .real("$DIMTVP", 40),
        .integer("$DIMTIX", 70),
        .integer("$DIMSOXD", 70),
        .integer("$DIMSAH", 70),
        .nameOrEmpty("$DIMBLK1", 1, .block),
        .nameOrEmpty("$DIMBLK2", 1, .block),
        .name("$DIMSTYLE", 2, .dimensionStyle),
        .color("$DIMCLRD", 70),
        .color("$DIMCLRE", 70),
        .color("$DIMCLRT", 70),
        .real("$DIMTFAC", 40),
        .real("$DIMGAP", 40),
        .integer("$DIMJUST", 70),
        .integer("$DIMSD1", 70),
        .integer("$DIMSD2", 70),
        .integer("$DIMTOLJ", 70),
        .integer("$DIMTZIN", 70),
        .integer("$DIMALTZ", 70),
        .integer("$DIMALTTZ", 70),
        .integer("$DIMUPT", 70),
        .integer("$DIMDEC", 70),
        .integer("$DIMTDEC", 70),
        .integer("$DIMALTU", 70),
        .integer("$DIMALTTD", 70),
        .name("$DIMTXSTY", 7, .textStyle),
        .integer("$DIMAUNIT", 70),
        .integer("$DIMADEC", 70),
        .real("$DIMALTRND", 40),
        .integer("$DIMAZIN", 70),
        .integer("$DIMDSEP", 70),
        .integer("$DIMATFIT", 70),
        .integer("$DIMFRAC", 70),
        .nameOrEmpty("$DIMLDRBLK", 1, .block),
        .integer("$DIMLUNIT", 70),
        .integer("$DIMLWD", 70),
        .integer("$DIMLWE", 70),
        .integer("$DIMTMOVE", 70),
        .real("$DIMFXL", 40),
        .integer("$DIMFXLON", 70),
        .real("$DIMJOGANG", 40),
        .integer("$DIMTFILL", 70),
        .color("$DIMTFILLCLR", 70),
        .integer("$DIMARCSYM", 70),
        .nameOrEmpty("$DIMLTYPE", 6, .lineType),
        .nameOrEmpty("$DIMLTEX1", 6, .lineType),
        .nameOrEmpty("$DIMLTEX2", 6, .lineType),
        .integer("$DIMTXTDIRECTION", 70),
        .integer("$LUNITS", 70),
        .integer("$LUPREC", 70),
        .real("$SKETCHINC", 40),
        .real("$FILLETRAD", 40),
        .integer("$AUNITS", 70),
        .integer("$AUPREC", 70),
        .text("$MENU", 1),
        .real("$ELEVATION", 40),
        .real("$PELEVATION", 40),
        .real("$THICKNESS", 40),
        .integer("$LIMCHECK", 70),
        .integer("$BLIPMODE", 70),  // R14 only
        .real("$CHAMFERA", 40),
        .real("$CHAMFERB", 40),
        .real("$CHAMFERC", 40),
        .real("$CHAMFERD", 40),
        .integer("$SKPOLY", 70),
        .real("$TDCREATE", 40),
        .real("$TDUCREATE", 40),
        .real("$TDUPDATE", 40),
        .real("$TDUUPDATE", 40),
        .real("$TDINDWG", 40),
        .real("$TDUSRTIMER", 40),
        .integer("$USRTIMER", 70),
        .real("$ANGBASE", 50),
        .integer("$ANGDIR", 70),
        .integer("$PDMODE", 70),
        .real("$PDSIZE", 40),
        .real("$PLINEWID", 40),
        .integer("$COORDS", 70),  // R14 only
        .integer("$SPLFRAME", 70),
        .integer("$SPLINETYPE", 70),
        .integer("$SPLINESEGS", 70),
        .integer("$ATTDIA", 70),  // R14 only
        .integer("$ATTREQ", 70),  // R14 only
        .handle("$HANDSEED", 5),
        .integer("$SURFTAB1", 70),
        .integer("$SURFTAB2", 70),
        .integer("$SURFTYPE", 70),
        .integer("$SURFU", 70),
        .integer("$SURFV", 70),
        .nameOrEmpty("$UCSBASE", 2, .ucs),
        .nameOrEmpty("$UCSNAME", 2, .ucs),
        .point3("$UCSORG"),
        .point3("$UCSXDIR"),
        .point3("$UCSYDIR"),
        .nameOrEmpty("$UCSORTHOREF", 2, .ucs),
        .integer("$UCSORTHOVIEW", 70),
        .point3("$UCSORGTOP"),
        .point3("$UCSORGBOTTOM"),
        .point3("$UCSORGLEFT"),
        .point3("$UCSORGRIGHT"),
        .point3("$UCSORGFRONT"),
        .point3("$UCSORGBACK"),
        .nameOrEmpty("$PUCSBASE", 2, .ucs),
        .nameOrEmpty("$PUCSNAME", 2, .ucs),
        .point3("$PUCSORG"),
        .point3("$PUCSXDIR"),
        .point3("$PUCSYDIR"),
        .nameOrEmpty("$PUCSORTHOREF", 2, .ucs),
        .integer("$PUCSORTHOVIEW", 70),
        .point3("$PUCSORGTOP"),
        .point3("$PUCSORGBOTTOM"),
        .point3("$PUCSORGLEFT"),
        .point3("$PUCSORGRIGHT"),
        .point3("$PUCSORGFRONT"),
        .point3("$PUCSORGBACK"),
        .integer("$USERI1", 70),
        .integer("$USERI2", 70),
        .integer("$USERI3", 70),
        .integer("$USERI4", 70),
        .integer("$USERI5", 70),
        .real("$USERR1", 40),
        .real("$USERR2", 40),
        .real("$USERR3", 40),
        .real("$USERR4", 40),
        .real("$USERR5", 40),
        .integer("$WORLDVIEW", 70),
        .integer("$SHADEDGE", 70),
        .integer("$SHADEDIF", 70),
        .integer("$TILEMODE", 70),
        .integer("$MAXACTVP", 70),
        .point3("$PINSBASE"),
        .integer("$PLIMCHECK", 70),
        .point3("$PEXTMIN"),
        .point3("$PEXTMAX"),
        .point2("$PLIMMIN"),
        .point2("$PLIMMAX"),
        .integer("$UNITMODE", 70),
        .integer("$VISRETAIN", 70),
        .integer("$PLINEGEN", 70),
        .integer("$PSLTSCALE", 70),
        .integer("$TREEDEPTH", 70),
        .name("$CMLSTYLE", 2, .mlineStyle),
        .integer("$CMLJUST", 70),
        .real("$CMLSCALE", 40),
        .integer("$PROXYGRAPHICS", 70),
        .integer("$MEASUREMENT", 70),
        .integer("$CELWEIGHT", 370),
        .integer("$ENDCAPS", 280),
        .integer("$JOINSTYLE", 280),
        .integer("$LWDISPLAY", 290),
        .integer("$INSUNITS", 70),
        .text("$HYPERLINKBASE", 1),
        .text("$STYLESHEET", 1),
        .integer("$XEDIT", 290),
        .integer("$CEPSNTYPE", 380),
        .integer("$PSTYLEMODE", 290),
        .text("$FINGERPRINTGUID", 2),
        .text("$VERSIONGUID", 2),
        .integer("$EXTNAMES", 290),
        .real("$PSVPSCALE", 40),
        .integer("$OLESTARTUP", 290),
        .integer("$SORTENTS", 280),
        .integer("$INDEXCTL", 280),
        .integer("$HIDETEXT", 280),
        .clipFrame(),
        .integer("$HALOGAP", 280),
        .integer("$OBSCOLOR", 70),
        .integer("$OBSLTYPE", 280),
        .integer("$INTERSECTIONDISPLAY", 280),
        .integer("$INTERSECTIONCOLOR", 70),
        .integer("$DIMASSOC", 280),
        .text("$PROJECTNAME", 1),
        .integer("$CAMERADISPLAY", 290),
        .real("$LENSLENGTH", 40),
        .real("$CAMERAHEIGHT", 40),
        .real("$STEPSPERSEC", 40),
        .real("$STEPSIZE", 40),
        .real("$3DDWFPREC", 40),
        .real("$PSOLWIDTH", 40),
        .real("$PSOLHEIGHT", 40),
        .real("$LOFTANG1", 40),
        .real("$LOFTANG2", 40),
        .real("$LOFTMAG1", 40),
        .real("$LOFTMAG2", 40),
        .integer("$LOFTPARAM", 70),
        .integer("$LOFTNORMALS", 280),
        .real("$LATITUDE", 40),
        .real("$LONGITUDE", 40),
        .real("$NORTHDIRECTION", 40),
        .integer("$TIMEZONE", 70),
        .integer("$LIGHTGLYPHDISPLAY", 280),
        .integer("$TILEMODELIGHTSYNCH", 280),
        .handle("$CMATERIAL", 347),
        .integer("$SOLIDHIST", 280),
        .integer("$SHOWHIST", 280),
        .integer("$DWFFRAME", 280),
        .integer("$DGNFRAME", 280),
        .color("$INTERFERECOLOR", 62),
        .handle("$INTERFEREOBJVS", 345),
        .handle("$INTERFEREVPVS", 346),
        .integer("$CSHADOW", 280),
        .real("$SHADOWPLANELOCATION", 40),
    ]
}
