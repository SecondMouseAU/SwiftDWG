// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgStreamReaderBase.cs and
// its version subclasses. See NOTICE.md. The bit codes are the format's own, from the Open Design
// Specification for .dwg files; the position model (bits over a byte array) is this package's.

import Foundation

/// A reader of the bit-coded values a DWG is made of, at any bit position.
///
/// Bits are taken most significant first. Every read that runs past the end throws
/// `DWG.Error.truncated`, so malformed data cannot trap.
struct BitReader {
    /// The bytes being read.
    let bytes: [UInt8]
    /// The release that decides how some values are coded.
    let version: DWG.Version
    /// The next bit to read, counted from the start of `bytes`.
    private(set) var position: Int
    /// The text encoding of single-byte strings, from the file's code page.
    var textEncoding: String.Encoding = .windowsCP1252

    init(_ bytes: [UInt8], version: DWG.Version, position: Int = 0) {
        self.bytes = bytes
        self.version = version
        self.position = position
    }

    /// The total number of bits.
    var bitCount: Int { bytes.count * 8 }

    /// Whether every bit has been read.
    var isAtEnd: Bool { position >= bitCount }

    /// Moves to a bit position, which may be the end but not beyond it.
    mutating func seek(toBit bit: Int) throws {
        guard bit >= 0, bit <= bitCount else { throw DWG.Error.truncated("a position") }
        position = bit
    }

    /// Moves to the start of the byte containing, or following, the current bit.
    mutating func alignToByte() {
        position = (position + 7) & ~7
    }

    // MARK: Raw bits and bytes

    /// Reads one bit.
    mutating func readBit() throws -> Bool {
        guard position < bitCount else { throw DWG.Error.truncated("a bit") }
        let bit = (bytes[position >> 3] >> UInt8(7 - (position & 7))) & 1
        position += 1
        return bit == 1
    }

    /// Reads `count` bits, 0 to 64, as an unsigned number with the first bit most significant.
    mutating func readBits(_ count: Int) throws -> UInt64 {
        guard count >= 0, count <= 64, position + count <= bitCount else {
            throw DWG.Error.truncated("\(count) bits")
        }
        var remaining = count
        var value: UInt64 = 0
        while remaining > 0 {
            let offset = position & 7
            let available = 8 - offset
            let take = min(available, remaining)
            let byte = UInt64(bytes[position >> 3])
            let chunk = (byte >> UInt64(available - take)) & ((1 << UInt64(take)) - 1)
            value = take == 64 ? chunk : (value << UInt64(take)) | chunk
            position += take
            remaining -= take
        }
        return value
    }

    /// Reads two bits (code `BB`).
    mutating func read2Bits() throws -> Int { Int(try readBits(2)) }

    /// Reads three bits (code `3B`).
    mutating func read3Bits() throws -> Int { Int(try readBits(3)) }

    /// Reads one byte (code `RC`).
    mutating func readByte() throws -> UInt8 { UInt8(try readBits(8)) }

    /// Reads `count` bytes.
    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, position + count * 8 <= bitCount else {
            throw DWG.Error.truncated("\(count) bytes")
        }
        if position & 7 == 0 {
            let start = position >> 3
            position += count * 8
            return Array(bytes[start..<(start + count)])
        }
        var out = [UInt8]()
        out.reserveCapacity(count)
        for _ in 0..<count { out.append(try readByte()) }
        return out
    }

    /// Reads a little-endian integer of `size` bytes.
    private mutating func readLittleEndian(_ size: Int) throws -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<size { value |= UInt64(try readByte()) << UInt64(8 * index) }
        return value
    }

    /// Reads a raw unsigned 16-bit value, little endian (code `RS`).
    mutating func readUShort() throws -> UInt16 { UInt16(try readLittleEndian(2)) }

    /// Reads a raw signed 16-bit value, little endian (code `RS`).
    mutating func readShort() throws -> Int16 { Int16(bitPattern: try readUShort()) }

    /// Reads a raw unsigned 32-bit value, little endian (code `RL`).
    mutating func readRawULong() throws -> UInt32 { UInt32(try readLittleEndian(4)) }

    /// Reads a raw signed 32-bit value, little endian (code `RL`).
    mutating func readRawLong() throws -> Int32 { Int32(bitPattern: try readRawULong()) }

    /// Reads a raw unsigned 64-bit value, little endian.
    mutating func readRawULongLong() throws -> UInt64 { try readLittleEndian(8) }

    /// Reads a raw double, little endian (code `RD`).
    mutating func readRawDouble() throws -> Double {
        Double(bitPattern: try readRawULongLong())
    }

    // MARK: Bit-coded numbers

    /// Reads a bit short (code `BS`): a 16-bit value in as few as two bits.
    mutating func readBitShort() throws -> Int16 {
        switch try read2Bits() {
        case 0: return try readShort()
        case 1: return Int16(try readByte())
        case 2: return 0
        default: return 256
        }
    }

    /// Reads a bit long (code `BL`): a 32-bit value in as few as two bits.
    mutating func readBitLong() throws -> Int32 {
        switch try read2Bits() {
        case 0: return try readRawLong()
        case 1: return Int32(try readByte())
        case 2: return 0
        default: throw DWG.Error.invalid("bit long with the unused code 3")
        }
    }

    /// Reads a bit long long (code `BLL`): a length of 0 to 7 bytes, then that many bytes.
    mutating func readBitLongLong() throws -> Int64 {
        let size = try read3Bits()
        var value: UInt64 = 0
        for index in 0..<size { value |= UInt64(try readByte()) << UInt64(8 * index) }
        return Int64(bitPattern: value)
    }

    /// Reads a bit double (code `BD`): 0.0 or 1.0 in two bits, otherwise a raw double.
    mutating func readBitDouble() throws -> Double {
        switch try read2Bits() {
        case 0: return try readRawDouble()
        case 1: return 1.0
        case 2: return 0.0
        default: throw DWG.Error.invalid("bit double with the unused code 3")
        }
    }

    /// Reads a bit double with default (code `DD`): the default, with the low bytes patched in.
    mutating func readBitDouble(default value: Double) throws -> Double {
        var raw = withUnsafeBytes(of: value.bitPattern.littleEndian) { Array($0) }
        switch try read2Bits() {
        case 0:
            return value
        case 1:
            for index in 0..<4 { raw[index] = try readByte() }
        case 2:
            raw[4] = try readByte()
            raw[5] = try readByte()
            for index in 0..<4 { raw[index] = try readByte() }
        default:
            return try readRawDouble()
        }
        var bits: UInt64 = 0
        for index in 0..<8 { bits |= UInt64(raw[index]) << UInt64(8 * index) }
        return Double(bitPattern: bits)
    }

    /// Reads a 2D point of bit doubles (code `2BD`).
    mutating func read2BitDouble() throws -> (x: Double, y: Double) {
        (try readBitDouble(), try readBitDouble())
    }

    /// Reads a 3D point of bit doubles (code `3BD`).
    mutating func read3BitDouble() throws -> (x: Double, y: Double, z: Double) {
        (try readBitDouble(), try readBitDouble(), try readBitDouble())
    }

    /// Reads a 2D point of raw doubles (code `2RD`).
    mutating func read2RawDouble() throws -> (x: Double, y: Double) {
        (try readRawDouble(), try readRawDouble())
    }

    /// Reads a 3D point of raw doubles (code `3RD`).
    mutating func read3RawDouble() throws -> (x: Double, y: Double, z: Double) {
        (try readRawDouble(), try readRawDouble(), try readRawDouble())
    }

    /// Reads a 2D point of bit doubles with defaults (code `2DD`).
    mutating func read2BitDouble(
        default point: (x: Double, y: Double)
    ) throws -> (x: Double, y: Double) {
        (try readBitDouble(default: point.x), try readBitDouble(default: point.y))
    }

    /// Reads a 3D point of bit doubles with defaults (code `3DD`).
    mutating func read3BitDouble(
        default point: (x: Double, y: Double, z: Double)
    ) throws -> (x: Double, y: Double, z: Double) {
        (
            try readBitDouble(default: point.x), try readBitDouble(default: point.y),
            try readBitDouble(default: point.z)
        )
    }

    /// Reads an extrusion (code `BE`): R13 and R14 write a `3BD`; R2000 and later write one bit,
    /// which is set for the usual (0, 0, 1), and the `3BD` only when it is clear.
    mutating func readBitExtrusion() throws -> (x: Double, y: Double, z: Double) {
        if version >= .ac1015, try readBit() { return (0, 0, 1) }
        return try read3BitDouble()
    }

    /// Reads a thickness (code `BT`): a `BD` in R13 and R14; from R2000 one bit, set for 0.0, and
    /// a `BD` only when it is clear.
    mutating func readBitThickness() throws -> Double {
        if version >= .ac1015, try readBit() { return 0.0 }
        return try readBitDouble()
    }

    // MARK: Modular numbers

    /// Reads an unsigned modular char (code `MC`): seven bits a byte, low group first.
    mutating func readModularChar() throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let byte = try readByte()
            guard shift < 64 else { throw DWG.Error.invalid("modular char longer than 64 bits") }
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
    }

    /// Reads a signed modular char: like `readModularChar`, but bit 6 of the last byte is the sign
    /// and only six bits of it are value.
    mutating func readSignedModularChar() throws -> Int64 {
        var value: Int64 = 0
        var shift: Int64 = 0
        while true {
            let byte = try readByte()
            guard shift < 63 else { throw DWG.Error.invalid("modular char longer than 63 bits") }
            if byte & 0x80 == 0 {
                value |= Int64(byte & 0x3F) << shift
                return byte & 0x40 != 0 ? -value : value
            }
            value |= Int64(byte & 0x7F) << shift
            shift += 7
        }
    }

    /// Reads a modular short (code `MS`): fifteen bits per 16-bit word, low word first.
    mutating func readModularShort() throws -> Int {
        var value = 0
        var shift = 0
        while true {
            let low = Int(try readByte())
            let high = Int(try readByte())
            guard shift < 48 else { throw DWG.Error.invalid("modular short longer than 48 bits") }
            value |= (low | (high & 0x7F) << 8) << shift
            if high & 0x80 == 0 { return value }
            shift += 15
        }
    }

    // MARK: Handles

    /// A handle reference as read: how it is coded, and the handle it resolves to.
    struct HandleReference: Equatable {
        /// The reference code, `2` to `5` for an absolute handle and `6`, `8`, `10`, `12` for one
        /// relative to the object's own handle.
        var code: Int
        /// The handle.
        var value: UInt64
    }

    /// Reads a handle reference (code `H`). `relativeTo` is the handle the relative codes count
    /// from, usually the handle of the object being read.
    mutating func readHandleReference(relativeTo reference: UInt64 = 0) throws -> HandleReference {
        let form = try readByte()
        let code = Int(form >> 4)
        let counter = Int(form & 0x0F)
        let value: UInt64
        switch code {
        case 0...5:
            value = try readHandleBytes(counter)
        case 6:
            value = reference &+ 1
        case 8:
            value = reference &- 1
        case 0xA:
            value = reference &+ (try readHandleBytes(counter))
        case 0xC:
            value = reference &- (try readHandleBytes(counter))
        default:
            throw DWG.Error.invalid("handle reference code \(code)")
        }
        return HandleReference(code: code, value: value)
    }

    /// Reads a handle and returns only its value.
    mutating func readHandle(relativeTo reference: UInt64 = 0) throws -> UInt64 {
        try readHandleReference(relativeTo: reference).value
    }

    /// Reads `count` bytes as a big-endian number.
    private mutating func readHandleBytes(_ count: Int) throws -> UInt64 {
        guard count <= 8 else { throw DWG.Error.invalid("handle of \(count) bytes") }
        var value: UInt64 = 0
        for _ in 0..<count { value = (value << 8) | UInt64(try readByte()) }
        return value
    }

    // MARK: Text

    /// Reads a variable text (code `T`): from R2007 on a count of UTF-16 characters and the
    /// characters, before that a count of bytes and the bytes in the drawing's code page.
    mutating func readVariableText() throws -> String {
        let length = Int(try readBitShort())
        guard length > 0 else { return "" }
        if version >= .ac1021 { return try readUTF16(length) }
        return decodeSingleByte(try readBytes(length))
    }

    /// Reads a unicode text (code `TU`): a count of UTF-16 characters and the characters.
    mutating func readUnicodeText() throws -> String {
        let length = Int(try readBitShort())
        guard length > 0 else { return "" }
        return try readUTF16(length)
    }

    /// Reads a raw string of `count` single-byte characters, with no length prefix.
    mutating func readString(byteCount count: Int) throws -> String {
        decodeSingleByte(try readBytes(count))
    }

    private mutating func readUTF16(_ characters: Int) throws -> String {
        var units = [UInt16]()
        units.reserveCapacity(characters)
        for _ in 0..<characters { units.append(try readUShort()) }
        return String(decoding: units, as: UTF16.self).replacingOccurrences(of: "\0", with: "")
    }

    private func decodeSingleByte(_ raw: [UInt8]) -> String {
        let trimmed = raw.prefix { $0 != 0 }
        return String(bytes: trimmed, encoding: textEncoding)
            ?? String(decoding: trimmed, as: UTF8.self)
    }
}
