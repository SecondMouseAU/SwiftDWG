// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgHandleReader.cs. See
// NOTICE.md. The layout is the format's own, from the Open Design Specification for .dwg files.

/// Reads the `AcDb:Handles` section, the map from an object's handle to where it is.
enum ObjectMapReader {
    /// The offset of each object in the `AcDb:AcDbObjects` section, by handle.
    static func read(_ section: [UInt8], version: DWG.Version) throws -> [UInt64: Int] {
        var reader = BitReader(section, version: version)
        var map: [UInt64: Int] = [:]

        // Runs of at most 2032 bytes, each with a big-endian size that counts its own two bytes
        // and ends with a two-byte CRC. A run of size 2 has no data and ends the section.
        while !reader.isAtEnd {
            let size = Int(try reader.readBits(16))
            if size <= 2 { break }
            let dataEnd = reader.position + min(size - 2, 2032) * 8
            var handle: UInt64 = 0
            var location = 0
            while reader.position < dataEnd {
                // Each pair is the step from the last handle, and the step from the last offset,
                // which can be negative.
                let step = try reader.readModularChar()
                handle &+= step
                location += Int(try reader.readSignedModularChar())
                if step > 0 { map[handle] = location }
            }
            _ = try reader.readBits(16)
        }
        return map
    }
}
