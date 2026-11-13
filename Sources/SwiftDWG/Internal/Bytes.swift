/// Reads of little-endian numbers at a byte offset, which throw when the data is too short.
extension Array where Element == UInt8 {
    func uint16(at offset: Int) throws -> UInt16 {
        UInt16(try littleEndian(at: offset, size: 2))
    }

    func uint32(at offset: Int) throws -> UInt32 {
        UInt32(try littleEndian(at: offset, size: 4))
    }

    func int32(at offset: Int) throws -> Int32 {
        Int32(bitPattern: try uint32(at: offset))
    }

    func uint64(at offset: Int) throws -> UInt64 {
        try littleEndian(at: offset, size: 8)
    }

    private func littleEndian(at offset: Int, size: Int) throws -> UInt64 {
        guard offset >= 0, offset + size <= count else {
            throw DWG.Error.truncated("a \(size * 8)-bit value at offset \(offset)")
        }
        var value: UInt64 = 0
        for index in 0..<size { value |= UInt64(self[offset + index]) << UInt64(8 * index) }
        return value
    }
}
