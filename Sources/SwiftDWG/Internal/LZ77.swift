// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgLZ77AC18Decompressor.cs.
// See NOTICE.md. The opcode layout is the format's own, from the Open Design Specification for
// .dwg files; the buffer handling is this package's.

/// The LZ77 variant that DWG files from R2004 on use for their pages.
enum LZ77 {
    /// Decompresses from `start` to the terminating opcode.
    ///
    /// `limit` caps the output, so a corrupt or hostile stream cannot grow without bound.
    static func decompressAC18(_ source: [UInt8], from start: Int, limit: Int) throws -> [UInt8] {
        var input = Input(bytes: source, position: start)
        var output = [UInt8]()
        output.reserveCapacity(min(limit, 1 << 20))

        var opcode = try input.next()
        if opcode > 0x11 {
            opcode = try copyLiteral(opcode - 17, &input, &output, limit)
        }
        if opcode & 0xF0 == 0 {
            opcode = try copyLiteral(try literalCount(opcode, &input) + 3, &input, &output, limit)
        }

        // 0x11 ends the stream.
        while opcode != 0x11 {
            var offset = 0
            var length = 0
            if opcode < 0x10 || opcode >= 0x40 {
                length = (opcode >> 4) - 1
                let second = try input.next()
                offset = ((opcode >> 2) & 3 | second << 2) + 1
            } else if opcode < 0x20 {
                length = try matchLength(opcode, validBits: 0b0111, &input)
                offset = (opcode & 8) << 11
                opcode = try twoByteOffset(&offset, added: 0x4000, &input)
            } else {
                length = try matchLength(opcode, validBits: 0b0001_1111, &input)
                opcode = try twoByteOffset(&offset, added: 1, &input)
            }

            guard offset > 0, offset <= output.count else {
                throw DWG.Error.invalid("LZ77 back reference outside the data")
            }
            guard output.count + length <= limit else {
                throw DWG.Error.invalid("LZ77 output past its declared size")
            }
            // The source may overlap the bytes being written, so copy one at a time.
            for _ in 0..<length { output.append(output[output.count - offset]) }

            var literals = opcode & 3
            if literals == 0 {
                opcode = try input.next()
                if opcode & 0xF0 == 0 { literals = try literalCount(opcode, &input) + 3 }
            }
            if literals > 0 {
                opcode = try copyLiteral(literals, &input, &output, limit)
            }
        }
        return output
    }

    private struct Input {
        let bytes: [UInt8]
        var position: Int

        mutating func next() throws -> Int {
            guard position < bytes.count else { throw DWG.Error.truncated("LZ77 data") }
            defer { position += 1 }
            return Int(bytes[position])
        }

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, position + count <= bytes.count else {
                throw DWG.Error.truncated("LZ77 literals")
            }
            defer { position += count }
            return bytes[position..<(position + count)]
        }
    }

    /// Copies `count` literal bytes and returns the opcode that follows them.
    private static func copyLiteral(
        _ count: Int, _ input: inout Input, _ output: inout [UInt8], _ limit: Int
    ) throws -> Int {
        guard output.count + count <= limit else {
            throw DWG.Error.invalid("LZ77 output past its declared size")
        }
        output.append(contentsOf: try input.take(count))
        return try input.next()
    }

    private static func literalCount(_ code: Int, _ input: inout Input) throws -> Int {
        var count = code & 0x0F
        if count == 0 {
            var byte = try input.next()
            while byte == 0 {
                count += 0xFF
                byte = try input.next()
            }
            count += 0x0F + byte
        }
        return count
    }

    private static func matchLength(
        _ opcode: Int, validBits: Int, _ input: inout Input
    ) throws -> Int {
        var length = opcode & validBits
        if length == 0 {
            var byte = try input.next()
            while byte == 0 {
                length += 0xFF
                byte = try input.next()
            }
            length += byte + validBits
        }
        return length + 2
    }

    private static func twoByteOffset(
        _ offset: inout Int, added: Int, _ input: inout Input
    ) throws -> Int {
        let first = try input.next()
        offset |= first >> 2
        offset |= try input.next() << 6
        offset += added
        return first
    }
}
