// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgStreamReaderAC18.cs and
// DwgMergedReader.cs (ReadCmColor). See NOTICE.md. The layout is the format's own, from the Open
// Design Specification for .dwg files.

extension ObjectReader {
    /// Reads the colour a table entry or a style holds (code `CMC`).
    ///
    /// Up to R2000 it is a colour index. From R2004 it is an index word that is always zero, a
    /// long that says which kind of colour follows, and a byte that says whether a colour name and
    /// a colour book name follow. From R2007 those two names are in the string stream, which
    /// `readText()` reads from. The names are read and dropped.
    mutating func readCmColor() throws -> DWGColor {
        guard version >= .ac1018 else { return Self.indexColor(Int(try main.readBitShort())) }
        _ = try main.readBitShort()
        let word = UInt32(bitPattern: try main.readBitLong())
        let color: DWGColor
        if word == 0xC000_0000 {
            color = .byLayer
        } else if word & 0x0100_0000 != 0 {
            color = Self.indexColor(Int(word & 0xFF))
        } else {
            color = .rgb(
                red: UInt8(truncatingIfNeeded: word >> 16),
                green: UInt8(truncatingIfNeeded: word >> 8),
                blue: UInt8(truncatingIfNeeded: word))
        }
        let names = try main.readByte()
        if names & 1 != 0 { _ = try readText() as String }
        if names & 2 != 0 { _ = try readText() as String }
        return color
    }

    /// Reads a colour that is only an index (the R13 and R14 form of the dimension colours).
    mutating func readColorIndex() throws -> DWGColor {
        Self.indexColor(Int(try main.readBitShort()))
    }
}
