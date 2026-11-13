import Foundation
import Testing

@testable import SwiftDWG

/// Bytes from a string of `0` and `1`, ignoring spaces and padding the last byte with zeros.
private func bits(_ text: String) -> [UInt8] {
    let digits = text.filter { $0 == "0" || $0 == "1" }
    var out = [UInt8]()
    var index = digits.startIndex
    while index < digits.endIndex {
        let end = digits.index(index, offsetBy: 8, limitedBy: digits.endIndex) ?? digits.endIndex
        var chunk = String(digits[index..<end])
        while chunk.count < 8 { chunk += "0" }
        out.append(UInt8(chunk, radix: 2) ?? 0)
        index = end
    }
    return out
}

private func reader(_ text: String, _ version: DWG.Version = .ac1032) -> BitReader {
    BitReader(bits(text), version: version)
}

@Suite("Bit reader")
struct BitReaderTests {
    @Test("bits come out most significant first, across byte boundaries")
    func rawBits() throws {
        var r = reader("1 01 110 0011 0101 1")
        #expect(try r.readBit() == true)
        #expect(try r.read2Bits() == 1)
        #expect(try r.read3Bits() == 6)
        #expect(try r.readBits(4) == 3)
        #expect(try r.readBits(5) == 0b01011)
        #expect(r.position == 15)
    }

    @Test("reading past the end throws instead of trapping")
    func truncation() {
        var r = reader("1")
        #expect(throws: DWG.Error.self) { _ = try r.readBits(9) }
        var empty = BitReader([], version: .ac1032)
        #expect(throws: DWG.Error.self) { _ = try empty.readBit() }
        #expect(throws: DWG.Error.self) { _ = try empty.readByte() }
    }

    @Test("raw little-endian numbers, aligned and not")
    func rawNumbers() throws {
        var r = reader("00110100 00010010 11111111 11111111 11111111 11111111")
        #expect(try r.readUShort() == 0x1234)
        #expect(try r.readRawLong() == -1)
        var shifted = reader("1 00110100 00010010")
        _ = try shifted.readBit()
        #expect(try shifted.readUShort() == 0x1234)
        var d = BitReader(
            withUnsafeBytes(of: (1.5).bitPattern.littleEndian) { Array($0) }, version: .ac1032)
        #expect(try d.readRawDouble() == 1.5)
    }

    @Test("bit short: raw, byte, zero and 256")
    func bitShort() throws {
        var r = reader("00 00110100 00010010  01 01111011  10  11")
        #expect(try r.readBitShort() == 0x1234)
        #expect(try r.readBitShort() == 123)
        #expect(try r.readBitShort() == 0)
        #expect(try r.readBitShort() == 256)
    }

    @Test("bit long: raw, byte and zero, and the unused code")
    func bitLong() throws {
        var r = reader("00 11111111 11111111 11111111 11111111  01 00000111  10  11")
        #expect(try r.readBitLong() == -1)
        #expect(try r.readBitLong() == 7)
        #expect(try r.readBitLong() == 0)
        #expect(throws: DWG.Error.self) { _ = try r.readBitLong() }
    }

    @Test("bit long long: a length, then that many bytes")
    func bitLongLong() throws {
        var r = reader("010 00000001 00000010  000")
        #expect(try r.readBitLongLong() == 0x0201)
        #expect(try r.readBitLongLong() == 0)
    }

    @Test("bit double: one, zero and a full double")
    func bitDouble() throws {
        let raw = withUnsafeBytes(of: (-2.25).bitPattern.littleEndian) { Array($0) }
        let text = "01 10 00 " + raw.map { String($0, radix: 2).leftPad(8) }.joined(separator: " ")
        var r = reader(text)
        #expect(try r.readBitDouble() == 1.0)
        #expect(try r.readBitDouble() == 0.0)
        #expect(try r.readBitDouble() == -2.25)
        var bad = reader("11")
        #expect(throws: DWG.Error.self) { _ = try bad.readBitDouble() }
    }

    @Test("bit double with default patches the low bytes into the default")
    func bitDoubleWithDefault() throws {
        // 1.0 is 0x3FF0_0000_0000_0000.
        var keep = reader("00")
        #expect(try keep.readBitDouble(default: 1.0) == 1.0)

        var four = reader("01 00000001 00000000 00000000 00000000")
        #expect(try four.readBitDouble(default: 1.0).bitPattern == 0x3FF0_0000_0000_0001)

        // Six bytes: the first two replace bytes 4 and 5, the last four replace bytes 0 to 3.
        var six = reader("10 00110100 00010010 00000001 00000000 00000000 00000000")
        #expect(try six.readBitDouble(default: 1.0).bitPattern == 0x3FF0_1234_0000_0001)

        let raw = withUnsafeBytes(of: (7.5).bitPattern.littleEndian) { Array($0) }
        let digits = raw.map { String($0, radix: 2).leftPad(8) }.joined(separator: " ")
        var full = reader("11 " + digits)
        #expect(try full.readBitDouble(default: 1.0) == 7.5)
    }

    @Test("an extrusion is one bit from R2000, a 3BD before")
    func extrusion() throws {
        var modern = reader("1")
        let z = try modern.readBitExtrusion()
        #expect(z.x == 0 && z.y == 0 && z.z == 1)

        var explicit = reader("0  10 10 01")
        let e = try explicit.readBitExtrusion()
        #expect(e.x == 0 && e.y == 0 && e.z == 1)

        var legacy = reader("10 10 01", .ac1014)
        let l = try legacy.readBitExtrusion()
        #expect(l.x == 0 && l.y == 0 && l.z == 1)
    }

    @Test("a thickness is one bit from R2000, a BD before")
    func thickness() throws {
        var modern = reader("1")
        #expect(try modern.readBitThickness() == 0)
        var explicit = reader("0 01")
        #expect(try explicit.readBitThickness() == 1)
        var legacy = reader("01", .ac1014)
        #expect(try legacy.readBitThickness() == 1)
    }

    @Test("modular char: unsigned and signed")
    func modularChar() throws {
        var r = reader("10000001 00000001  10000010 00000001  00000101")
        #expect(try r.readModularChar() == 129)
        #expect(try r.readModularChar() == 130)
        #expect(try r.readModularChar() == 5)

        var s = reader("01000001  00000011  10000010 01000001")
        #expect(try s.readSignedModularChar() == -1)
        #expect(try s.readSignedModularChar() == 3)
        // 0x82 gives 2 and a continuation; 0x41 is 1 with the sign, shifted by 7: -(2 + 128).
        #expect(try s.readSignedModularChar() == -130)
    }

    @Test("modular short: 15 bits a word")
    func modularShort() throws {
        var r = reader("00110100 00010010  00000001 10000000 00000001 00000000")
        #expect(try r.readModularShort() == 0x1234)
        #expect(try r.readModularShort() == 1 | (1 << 15))
    }

    @Test("a handle reference: absolute, and relative to the object's own handle")
    func handles() throws {
        var r = reader(
            "0101 0001 00000101  0110 0000  1000 0000  1010 0001 00000010  1100 0001 00000010")
        let absolute = try r.readHandleReference()
        #expect(absolute.code == 5 && absolute.value == 5)
        #expect(try r.readHandle(relativeTo: 100) == 101)
        #expect(try r.readHandle(relativeTo: 100) == 99)
        #expect(try r.readHandle(relativeTo: 100) == 102)
        #expect(try r.readHandle(relativeTo: 100) == 98)

        var long = reader("0100 0010 00000001 00000010")
        #expect(try long.readHandle() == 0x0102)
        var bad = reader("1111 0000")
        #expect(throws: DWG.Error.self) { _ = try bad.readHandleReference() }
    }

    @Test("variable text: a count of bytes before R2007, of UTF-16 characters from R2007")
    func variableText() throws {
        var old = reader("01 00000011 01001000 01101001 00000000", .ac1018)
        #expect(try old.readVariableText() == "Hi")

        var modern = reader("01 00000010 01001000 00000000 01101001 00000000", .ac1032)
        #expect(try modern.readVariableText() == "Hi")

        var empty = reader("10")
        #expect(try empty.readVariableText() == "")
    }

    @Test("seeking and aligning")
    func seeking() throws {
        var r = reader("11110000 10101010")
        try r.seek(toBit: 3)
        #expect(try r.readBit() == true)
        r.alignToByte()
        #expect(r.position == 8)
        #expect(try r.readByte() == 0xAA)
        #expect(throws: DWG.Error.self) { try r.seek(toBit: 17) }
    }
}

extension String {
    fileprivate func leftPad(_ width: Int) -> String {
        String(repeating: "0", count: max(0, width - count)) + self
    }
}
