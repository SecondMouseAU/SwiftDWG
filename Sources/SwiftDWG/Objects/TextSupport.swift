// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgStreamReaderAC18.cs and
// DwgMergedReader.cs (ReadCmColor). See NOTICE.md. The layout is the format's own, from the Open
// Design Specification for .dwg files. The count check is this package's own.

extension ObjectReader {
    /// Reads a colour in the CMC form some objects use, which is longer than an entity's colour.
    ///
    /// From R2004 it is an index word that is always 0, a word holding an index or an RGB value,
    /// and a flags byte that says whether a colour name and a colour book name follow. The names
    /// are read, because they sit in the data, and dropped. Before R2004 it is one index word.
    mutating func readCmColor() throws -> DWGColor {
        guard version >= .ac1018 else {
            return Self.indexColor(Int(try main.readBitShort()))
        }
        _ = try main.readBitShort()
        let word = UInt32(bitPattern: try main.readBitLong())
        let flags = try main.readByte()
        if flags & 1 != 0 { let _: String = try readText() }
        if flags & 2 != 0 { let _: String = try readText() }
        if word == 0xC000_0000 { return .byLayer }
        if word & 0x0100_0000 != 0 { return Self.indexColor(Int(word & 0xFF)) }
        return .rgb(
            red: UInt8(truncatingIfNeeded: word >> 16),
            green: UInt8(truncatingIfNeeded: word >> 8),
            blue: UInt8(truncatingIfNeeded: word))
    }

    /// Checks a count read from the file before it is used to size a loop.
    ///
    /// A count is rejected when it is negative, when it is more than a drawing can hold, or when
    /// the items it counts could not fit in the bits that are left.
    ///
    /// - Parameters:
    ///   - count: The count as stored.
    ///   - bitsPerItem: The fewest bits one item takes.
    ///   - bitsLeft: The bits still to read in the stream the items are in.
    ///   - what: What is counted, for the error.
    /// - Returns: The count as an `Int`.
    /// - Throws: `DWG.Error.invalid` when the count is not credible.
    static func checkedCount(
        _ count: Int32, bitsPerItem: Int, bitsLeft: Int, what: String
    ) throws -> Int {
        guard count >= 0, count <= 1 << 20, Int(count) * bitsPerItem <= bitsLeft else {
            throw DWG.Error.invalid("\(count) \(what)")
        }
        return Int(count)
    }
}
