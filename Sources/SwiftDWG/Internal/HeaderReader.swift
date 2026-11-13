// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgHeaderReader.cs, with the
// merged text, handle and data streams of DwgMergedReader.cs. See NOTICE.md. The order of the
// variables is the format's own, from the Open Design Specification for .dwg files. The names are
// the ones DXF gives its HEADER variables, so that the result can be checked against a DXF export.
//
// Every release from R14 to R2018 is checked against AutoCAD's own drawings: AC1015 and later
// against its DXF export of the same drawing, AC1014 against the AC1015 export and the objects in
// the file. R13 (AC1012) shares the R14 code and has no file to run on.

import Foundation

/// Reads the `AcDb:Header` section: the system variables of a drawing, and the handles of the
/// objects the header points at.
enum HeaderReader {
    /// The 16 bytes that start the section.
    static let startSentinel: [UInt8] = [
        0xCF, 0x7B, 0x1F, 0x23, 0xFD, 0xDE, 0x38, 0xA9, 0x5F, 0x7C, 0x68, 0xB8, 0x4E, 0x6D, 0x33,
        0x5F,
    ]

    /// Reads the variables of a header section.
    ///
    /// - Parameters:
    ///   - section: The bytes of `AcDb:Header`, from its start sentinel.
    ///   - version: The release the file was saved as. R13 and later are read.
    ///   - maintenanceVersion: The AutoCAD maintenance release that wrote the file, from the file
    ///     header. From R2010 a value above 3 adds four bytes before the data.
    ///   - codePage: The code page number in the file header, which decides how single-byte text
    ///     is decoded. Text from R2007 is UTF-16 and ignores it.
    /// - Returns: The variables and handles the section holds.
    /// - Throws: `DWG.Error` when the section is cut short or does not add up.
    static func read(
        _ section: [UInt8], version: DWG.Version, maintenanceVersion: Int, codePage: Int
    ) throws -> HeaderVariables {
        guard version >= .ac1012 else { throw DWG.Error.unsupportedVersion(version.code) }
        var parser = try Parser(
            section, version: version, maintenanceVersion: maintenanceVersion,
            codePage: codePage)
        try parser.readVariables()
        return parser.result
    }

    /// The state of a read: one reader for the main data and, from R2007, one each for the text and
    /// the handles, which that release keeps in separate runs of bits.
    struct Parser {
        let version: DWG.Version
        /// The main data: everything that is not text or a handle.
        var main: BitReader
        /// The string stream, from R2007. `nil` when the drawing has none, and then every text is
        /// empty.
        var text: BitReader?
        /// The handle stream, from R2007.
        var references: BitReader
        /// Whether text and handles are in streams of their own.
        let isMerged: Bool
        var result = HeaderVariables()

        let r13to14: Bool
        let r13to15: Bool
        let r2000Plus: Bool
        let before2004: Bool
        let r2004Plus: Bool
        let r2007Plus: Bool
        let r2010Plus: Bool
        let r2013Plus: Bool

        init(_ section: [UInt8], version: DWG.Version, maintenanceVersion: Int, codePage: Int)
            throws
        {
            self.version = version
            r13to14 = version == .ac1012 || version == .ac1014
            r13to15 = version >= .ac1012 && version <= .ac1015
            r2000Plus = version >= .ac1015
            before2004 = version < .ac1018
            r2004Plus = version >= .ac1018
            r2007Plus = version >= .ac1021
            r2010Plus = version >= .ac1024
            r2013Plus = version >= .ac1027
            isMerged = r2007Plus

            var main = BitReader(section, version: version)
            if let encoding = CodePage.encoding(for: codePage) { main.textEncoding = encoding }
            guard try main.readBytes(16) == HeaderReader.startSentinel else {
                throw DWG.Error.invalid("the header variables do not start with their sentinel")
            }
            // RL: the size of the data. From R2010 with a maintenance release above 3, and from
            // R2018, four more bytes follow, which are not understood and not needed.
            let size = Int(try main.readRawLong())
            if (r2010Plus && maintenanceVersion > 3) || version >= .ac1032 {
                _ = try main.readRawLong()
            }
            let start = main.position
            guard size >= 0, start / 8 + size <= section.count else {
                throw DWG.Error.truncated("the header variables")
            }

            var references = main
            var text: BitReader?
            if r2007Plus {
                // RL: the size of the data in bits, which ends with the flag for the string stream.
                let sizeInBits = Int(try main.readRawLong())
                let flagBit = start + sizeInBits - 1
                guard sizeInBits >= 1, flagBit < main.bitCount else {
                    throw DWG.Error.invalid("header data of \(sizeInBits) bits")
                }
                text = try Self.openStringStream(section, version: version, flagBit: flagBit)
                text?.textEncoding = main.textEncoding
                references = BitReader(section, version: version)
                try references.seek(toBit: flagBit + 1)
            }
            self.main = main
            self.text = text
            self.references = references
        }

        /// The reader of the string stream, or `nil` when the drawing has none.
        ///
        /// A flag at the end of the data says whether there is one. The stream ends just before the
        /// flag, with its size in the 16 bits before that (and a second 16 bits when the first has
        /// its top bit set).
        private static func openStringStream(
            _ section: [UInt8], version: DWG.Version, flagBit: Int
        ) throws -> BitReader? {
            var reader = BitReader(section, version: version)
            try reader.seek(toBit: flagBit)
            guard try reader.readBit() else { return nil }
            var end = flagBit - 16
            try reader.seek(toBit: end)
            var size = Int(try reader.readUShort())
            if size & 0x8000 != 0 {
                end -= 16
                try reader.seek(toBit: end)
                size &= 0x7FFF
                size += Int(try reader.readUShort()) << 15
            }
            try reader.seek(toBit: end - size)
            return reader
        }

        // MARK: Reads of one kind of value

        /// Reads a text from where this release keeps it.
        mutating func readText() throws -> String {
            guard isMerged else { return try main.readVariableText() }
            guard var stream = text else { return "" }
            let value = try stream.readVariableText()
            text = stream
            return value
        }

        /// Reads a handle from where this release keeps it, and returns its value.
        mutating func readReference() throws -> UInt64 {
            isMerged ? try references.readHandle() : try main.readHandle()
        }

        /// Reads a colour (code `CMC`): an index before R2004, and after it an index, an RGB value
        /// and a flag byte saying whether a colour name and a book name follow.
        mutating func readColor() throws -> HeaderVariables.Value {
            let index = Int(try main.readBitShort())
            guard r2004Plus else { return .color(index: index, rgb: nil) }
            let rgb = UInt32(bitPattern: try main.readBitLong())
            let names = try main.readByte()
            if names & 1 != 0 { _ = try readText() }
            if names & 2 != 0 { _ = try readText() }
            if rgb == 0xC000_0000 { return .color(index: 256, rgb: nil) }
            if rgb & 0x0100_0000 != 0 { return .color(index: Int(rgb & 0xFF), rgb: nil) }
            return .color(index: index, rgb: rgb & 0x00FF_FFFF)
        }

        /// Reads a date or a length of time as a real, the way DXF writes it.
        ///
        /// It is two bit longs, a number of days and the milliseconds into the next. A date is a
        /// Julian date.
        mutating func readDays() throws -> Double {
            let day = Double(try main.readBitLong())
            let milliseconds = Double(try main.readBitLong())
            return day + milliseconds / 86_400_000
        }

        // MARK: Reads into a named variable

        /// Reads a bit.
        mutating func flag(_ name: String) throws {
            result.values[name] = .bool(try main.readBit())
        }

        /// Reads a bit that stands for the number 0 or 1.
        mutating func flagAsInt(_ name: String) throws {
            result.values[name] = .int(try main.readBit() ? 1 : 0)
        }

        /// Reads a bit short.
        mutating func short(_ name: String) throws {
            result.values[name] = .int(Int(try main.readBitShort()))
        }

        /// Reads a bit long.
        mutating func long(_ name: String) throws {
            result.values[name] = .int(Int(try main.readBitLong()))
        }

        /// Reads a raw byte.
        mutating func byte(_ name: String) throws {
            result.values[name] = .int(Int(try main.readByte()))
        }

        /// Reads a bit double.
        mutating func real(_ name: String) throws {
            result.values[name] = .double(try main.readBitDouble())
        }

        /// Reads a text.
        mutating func string(_ name: String) throws {
            result.values[name] = .string(try readText())
        }

        /// Reads a 3D point of bit doubles.
        mutating func point3(_ name: String) throws {
            let point = try main.read3BitDouble()
            result.values[name] = .point3(x: point.x, y: point.y, z: point.z)
        }

        /// Reads a 2D point of raw doubles.
        mutating func point2(_ name: String) throws {
            let point = try main.read2RawDouble()
            result.values[name] = .point2(x: point.x, y: point.y)
        }

        /// Reads a colour.
        mutating func color(_ name: String) throws {
            result.values[name] = try readColor()
        }

        /// Reads a date or a length of time, as a number of days.
        mutating func days(_ name: String) throws {
            result.values[name] = .double(try readDays())
        }

        /// Reads a handle, and keeps it under the name ACadSharp gives it and, when DXF has a
        /// variable for it, under that too.
        mutating func handle(_ name: String) throws {
            let value = try readReference()
            result.handles[name] = value
            if let variable = Self.variableNames[name] { result.values[variable] = .handle(value) }
        }

        /// Reads `count` values of a kind the format has no use for, and drops them.
        mutating func skip(bits: Int = 0, shorts: Int = 0, longs: Int = 0, reals: Int = 0) throws {
            for _ in 0..<bits { _ = try main.readBit() }
            for _ in 0..<shorts { _ = try main.readBitShort() }
            for _ in 0..<longs { _ = try main.readBitLong() }
            for _ in 0..<reals { _ = try main.readBitDouble() }
        }

        /// The DXF variable for each handle that has one.
        static let variableNames: [String: String] = [
            "CLAYER": "$CLAYER", "TEXTSTYLE": "$TEXTSTYLE", "CELTYPE": "$CELTYPE",
            "CMATERIAL": "$CMATERIAL", "DIMSTYLE": "$DIMSTYLE", "CMLSTYLE": "$CMLSTYLE",
            "UCSNAME_PSPACE": "$PUCSNAME", "PUCSORTHOREF": "$PUCSORTHOREF",
            "PUCSBASE": "$PUCSBASE", "UCSNAME_MSPACE": "$UCSNAME", "UCSORTHOREF": "$UCSORTHOREF",
            "UCSBASE": "$UCSBASE", "DIMTXSTY": "$DIMTXSTY", "DIMLDRBLK": "$DIMLDRBLK",
            "DIMBLK": "$DIMBLK", "DIMBLK1": "$DIMBLK1", "DIMBLK2": "$DIMBLK2",
            "DIMLTYPE": "$DIMLTYPE", "DIMLTEX1": "$DIMLTEX1", "DIMLTEX2": "$DIMLTEX2",
            "INTERFEREOBJVS": "$INTERFEREOBJVS", "INTERFEREVPVS": "$INTERFEREVPVS",
            "DRAGVS": "$DRAGVS",
        ]

        // MARK: The section, in the order the file has it

        /// Reads every variable and handle.
        mutating func readVariables() throws {
            try readPreamble()
            try readSwitches()
            try readSettings()
            try readTimesAndCurrents()
            try readSpace(paper: true)
            try readSpace(paper: false)
            try readDimensionVariables()
            try readObjectPointers()
            try readFlagsAndDefaults()
            if r2007Plus { try readVisualSettings() }
        }

        /// The values at the start that are not variables: constants the format carries.
        private mutating func readPreamble() throws {
            if r2013Plus {
                result.values["$REQUIREDVERSIONS"] = .int(Int(try main.readBitLongLong()))
            }
            // Four reals, four texts and two longs, with the same default in every file.
            try skip(reals: 4)
            for _ in 0..<4 { _ = try readText() }
            try skip(longs: 2)
            if r13to14 { try skip(shorts: 1) }
            if before2004 { try handle("CURRENT_VIEWPORT_ENTITY_HEADER") }
        }

        /// The on and off switches, then the small integers.
        private mutating func readSwitches() throws {
            try flag("$DIMASO")
            try flag("$DIMSHO")
            if r13to14 { try flag("$DIMSAV") }
            try flag("$PLINEGEN")
            try flag("$ORTHOMODE")
            try flag("$REGENMODE")
            try flag("$FILLMODE")
            try flag("$QTEXTMODE")
            try flag("$PSLTSCALE")
            try flag("$LIMCHECK")
            if r13to14 { try flag("$BLIPMODE") }
            if r2004Plus { try skip(bits: 1) }
            try flag("$USRTIMER")
            try flag("$SKPOLY")
            try flagAsInt("$ANGDIR")
            try flag("$SPLFRAME")
            if r13to14 {
                try flag("$ATTREQ")
                try flag("$ATTDIA")
            }
            try flag("$MIRRTEXT")
            try flag("$WORLDVIEW")
            if r13to14 { try skip(bits: 1) }
            try flag("$TILEMODE")
            try flag("$PLIMCHECK")
            try flag("$VISRETAIN")
            if r13to14 { try flag("$DELOBJ") }
            try flag("$DISPSILH")
            try flag("$PELLIPSE")
            try short("$PROXYGRAPHICS")
            if r13to14 { try short("$DRAGMODE") }
            for name in ["$TREEDEPTH", "$LUNITS", "$LUPREC", "$AUNITS", "$AUPREC"] {
                try short(name)
            }
            if r13to14 { try short("$OSMODE") }
            try short("$ATTMODE")
            if r13to14 { try short("$COORDS") }
            try short("$PDMODE")
            if r13to14 { try short("$PICKSTYLE") }
            if r2004Plus { try skip(longs: 3) }
            for name in ["$USERI1", "$USERI2", "$USERI3", "$USERI4", "$USERI5"] {
                try short(name)
            }
        }

        /// The modelling and drawing settings, as shorts and then reals.
        private mutating func readSettings() throws {
            let shorts = [
                "$SPLINESEGS", "$SURFU", "$SURFV", "$SURFTYPE", "$SURFTAB1", "$SURFTAB2",
                "$SPLINETYPE", "$SHADEDGE", "$SHADEDIF", "$UNITMODE", "$MAXACTVP", "$ISOLINES",
                "$CMLJUST", "$TEXTQLTY",
            ]
            for name in shorts { try short(name) }
            let reals = [
                "$LTSCALE", "$TEXTSIZE", "$TRACEWID", "$SKETCHINC", "$FILLETRAD", "$THICKNESS",
                "$ANGBASE", "$PDSIZE", "$PLINEWID", "$USERR1", "$USERR2", "$USERR3", "$USERR4",
                "$USERR5", "$CHAMFERA", "$CHAMFERB", "$CHAMFERC", "$CHAMFERD", "$FACETRES",
                "$CMLSCALE", "$CELTSCALE",
            ]
            for name in reals { try real(name) }
            try string("$MENU")
        }

        /// The dates, the current colour, the next handle and the current styles.
        private mutating func readTimesAndCurrents() throws {
            // The specification and ACadSharp call these two TDCREATE and TDUPDATE. R14 keeps the
            // local times, as DXF names them. From R2000 they are the universal times, which DXF
            // calls `$TDUCREATE` and `$TDUUPDATE`, and the local ones are not in the file.
            try days(r2000Plus ? "$TDUCREATE" : "$TDCREATE")
            try days(r2000Plus ? "$TDUUPDATE" : "$TDUPDATE")
            if r2004Plus { try skip(longs: 3) }
            try days("$TDINDWG")
            try days("$TDUSRTIMER")
            try color("$CECOLOR")
            // The next handle is always in the main data, even where handles are not.
            result.values["$HANDSEED"] = .handle(try main.readHandle())
            try handle("CLAYER")
            try handle("TEXTSTYLE")
            try handle("CELTYPE")
            if r2007Plus { try handle("CMATERIAL") }
            try handle("DIMSTYLE")
            try handle("CMLSTYLE")
            if r2000Plus { try real("$PSVPSCALE") }
        }

        /// Reads the variables of one space.
        ///
        /// They are the extents, the limits, the elevation and the user coordinate system. Paper
        /// space names them with a `P` after the `$`.
        private mutating func readSpace(paper: Bool) throws {
            let prefix = paper ? "$P" : "$"
            try point3("\(prefix)INSBASE")
            try point3("\(prefix)EXTMIN")
            try point3("\(prefix)EXTMAX")
            try point2("\(prefix)LIMMIN")
            try point2("\(prefix)LIMMAX")
            try real(paper ? "$PELEVATION" : "$ELEVATION")
            try point3("\(prefix)UCSORG")
            try point3("\(prefix)UCSXDIR")
            try point3("\(prefix)UCSYDIR")
            try handle(paper ? "UCSNAME_PSPACE" : "UCSNAME_MSPACE")
            if r2000Plus {
                try handle(paper ? "PUCSORTHOREF" : "UCSORTHOREF")
                try short("\(prefix)UCSORTHOVIEW")
                try handle(paper ? "PUCSBASE" : "UCSBASE")
                for side in ["TOP", "BOTTOM", "LEFT", "RIGHT", "FRONT", "BACK"] {
                    try point3("\(prefix)UCSORG\(side)")
                }
            }
            if r2000Plus && !paper {
                try string("$DIMPOST")
                try string("$DIMAPOST")
            }
        }

        /// The handles of the table control objects and the dictionaries.
        private mutating func readObjectPointers() throws {
            for name in [
                "BLOCK_CONTROL_OBJECT", "LAYER_CONTROL_OBJECT", "STYLE_CONTROL_OBJECT",
                "LINETYPE_CONTROL_OBJECT", "VIEW_CONTROL_OBJECT", "UCS_CONTROL_OBJECT",
                "VPORT_CONTROL_OBJECT", "APPID_CONTROL_OBJECT", "DIMSTYLE_CONTROL_OBJECT",
            ] {
                try handle(name)
            }
            if r13to15 { try handle("VIEWPORT_ENTITY_HEADER_CONTROL_OBJECT") }
            try handle("DICTIONARY_ACAD_GROUP")
            try handle("DICTIONARY_ACAD_MLINESTYLE")
            try handle("DICTIONARY_NAMED_OBJECTS")
            if r2000Plus {
                try short("$TSTACKALIGN")
                try short("$TSTACKSIZE")
                try string("$HYPERLINKBASE")
                try string("$STYLESHEET")
                try handle("DICTIONARY_LAYOUTS")
                try handle("DICTIONARY_PLOTSETTINGS")
                try handle("DICTIONARY_PLOTSTYLES")
            }
            if r2004Plus {
                try handle("DICTIONARY_MATERIALS")
                try handle("DICTIONARY_COLORS")
            }
            if r2007Plus {
                try handle("DICTIONARY_VISUALSTYLE")
                if r2013Plus { try handle("UNKNOWN_R2013") }
            }
        }

        /// The flag word, the units, the plot style, and the settings that follow them.
        private mutating func readFlagsAndDefaults() throws {
            if r2000Plus {
                try readFlagWord()
                try short("$INSUNITS")
                try short("$CEPSNTYPE")
                if result.int("$CEPSNTYPE") == 3 { try handle("CPSNID") }
                try string("$FINGERPRINTGUID")
                try string("$VERSIONGUID")
            }
            if r2004Plus {
                for name in [
                    "$SORTENTS", "$INDEXCTL", "$HIDETEXT", "$XCLIPFRAME", "$DIMASSOC", "$HALOGAP",
                ] {
                    try byte(name)
                }
                try short("$OBSCOLOR")
                try short("$INTERSECTIONCOLOR")
                try byte("$OBSLTYPE")
                try byte("$INTERSECTIONDISPLAY")
                try string("$PROJECTNAME")
            }
            for name in ["PAPER_SPACE", "MODEL_SPACE", "BYLAYER", "BYBLOCK", "CONTINUOUS"] {
                try handle(name)
            }
        }

        /// The bit long that packs the line weight, the line ends and several switches.
        private mutating func readFlagWord() throws {
            let flags = Int(try main.readBitLong())
            result.values["$CELWEIGHT"] = .int(Self.lineWeight(index: flags & 0x1F))
            result.values["$ENDCAPS"] = .int((flags & 0x60) >> 5)
            result.values["$JOINSTYLE"] = .int((flags & 0x180) >> 7)
            // These two are stored inverted.
            result.values["$LWDISPLAY"] = .bool(flags & 0x200 == 0)
            result.values["$XEDIT"] = .bool(flags & 0x400 == 0)
            result.values["$EXTNAMES"] = .bool(flags & 0x800 != 0)
            result.values["$PSTYLEMODE"] = .bool(flags & 0x2000 != 0)
            result.values["$OLESTARTUP"] = .bool(flags & 0x4000 != 0)
        }

        /// The lineweight, in hundredths of a millimetre, that a header index stands for, or the
        /// negative codes DXF uses for by layer (-1), by block (-2) and the default (-3).
        static func lineWeight(index: Int) -> Int {
            let weights = [
                0, 5, 9, 13, 15, 18, 20, 25, 30, 35, 40, 50, 53, 60, 70, 80, 90, 100, 106, 120, 140,
                158, 200, 211,
            ]
            switch index {
            case 28, 29: return -1
            case 30: return -2
            case 31: return -3
            default: return weights.indices.contains(index) ? weights[index] : -3
            }
        }

        /// The settings R2007 added: the camera, the solid modelling defaults, the location and
        /// the shadows.
        private mutating func readVisualSettings() throws {
            try flag("$CAMERADISPLAY")
            try skip(longs: 2, reals: 1)
            for name in ["$STEPSPERSEC", "$STEPSIZE", "$3DDWFPREC", "$LENSLENGTH", "$CAMERAHEIGHT"]
            {
                try real(name)
            }
            try byte("$SOLIDHIST")
            try byte("$SHOWHIST")
            for name in [
                "$PSOLWIDTH", "$PSOLHEIGHT", "$LOFTANG1", "$LOFTANG2", "$LOFTMAG1", "$LOFTMAG2",
            ] {
                try real(name)
            }
            try short("$LOFTPARAM")
            try byte("$LOFTNORMALS")
            for name in ["$LATITUDE", "$LONGITUDE", "$NORTHDIRECTION"] { try real(name) }
            try long("$TIMEZONE")
            try byte("$LIGHTGLYPHDISPLAY")
            try byte("$TILEMODELIGHTSYNCH")
            try byte("$DWFFRAME")
            try byte("$DGNFRAME")
            try skip(bits: 1)
            try color("$INTERFERECOLOR")
            try handle("INTERFEREOBJVS")
            try handle("INTERFEREVPVS")
            try handle("DRAGVS")
            try byte("$CSHADOW")
            try real("$SHADOWPLANELOCATION")
        }
    }
}
