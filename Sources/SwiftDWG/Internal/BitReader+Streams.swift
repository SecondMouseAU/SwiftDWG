// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgStreamReaderBase.cs
// (SetPositionByFlag) and DwgStreamReaderAC24.cs (ReadObjectType). See NOTICE.md.

extension BitReader {
    /// Finds where the string stream of an object or a section starts.
    ///
    /// From R2007 an object's, or a section's, text is kept in a stream of its own at the end of
    /// the data that comes before the handles.
    ///
    /// `flagBit` is the position of the last bit of that data, the bit that says whether a string
    /// stream is there. The size of the stream is written just before that bit, as 15 bits, and
    /// when the top bit of that word is set, as 15 more bits in the word before it.
    ///
    /// - Returns: The bit position the string stream starts at, or `nil` when there is none.
    func stringStreamStart(flagBit: Int) throws -> Int? {
        var probe = self
        try probe.seek(toBit: flagBit)
        guard try probe.readBit() else { return nil }

        var end = flagBit - 16
        try probe.seek(toBit: end)
        var size = Int(try probe.readUShort())
        if size & 0x8000 != 0 {
            end -= 16
            try probe.seek(toBit: end)
            size &= 0x7FFF
            size += Int(try probe.readUShort()) << 15
        }
        guard size >= 0, end - size >= 0 else {
            throw DWG.Error.invalid("string stream of \(size) bits")
        }
        return end - size
    }

    /// Reads an object's type code: a bit short up to R2007, and from R2010 a two-bit form that
    /// holds a byte, a byte past 0x1F0, or a short.
    mutating func readObjectType() throws -> Int {
        guard version >= .ac1024 else { return Int(try readBitShort()) }
        switch try read2Bits() {
        case 0: return Int(try readByte())
        case 1: return 0x1F0 + Int(try readByte())
        default: return Int(try readUShort())
        }
    }
}
