// Derived from ACadSharp (MIT), src/ACadSharp/IO/DWG/DwgStreamReaders/DwgLZ77AC21Decompressor.cs.
// See NOTICE.md. The opcodes and the order the literal bytes are stored in are the format's own,
// from the Open Design Specification for .dwg files. The table of piece copies below is this
// package's, written from the sizes and offsets of the 31 copy routines in that file.

/// The LZ77 variant that R2007 files use for their pages.
///
/// Literal runs are stored with their bytes regrouped: whole 32-byte blocks have their 8-byte words
/// in reverse order, and the remainder of 1 to 31 bytes is cut into pieces of 1, 2, 3, 4, 8 and 16
/// bytes that are laid out back to front.
enum LZ77AC21 {
    /// Decompresses `length` bytes of `source` from `offset`, into a buffer of `outputSize`.
    static func decompress(
        _ source: [UInt8], offset: Int, length: Int, outputSize: Int
    ) throws -> [UInt8] {
        guard offset >= 0, length >= 0, offset + length <= source.count, outputSize >= 0,
            outputSize <= 1 << 28
        else { throw DWG.Error.invalid("R2007 page with a size that is not valid") }
        var state = State(source: source, index: offset, end: offset + length)
        var output = [UInt8](repeating: 0, count: outputSize)
        var destination = 0

        guard state.index < state.end else { return output }
        state.opcode = Int(source[state.index])
        state.index += 1
        guard state.index < state.end else { return output }
        if state.opcode & 0xF0 == 0x20 {
            state.index += 3
            guard state.index <= source.count else { throw DWG.Error.truncated("R2007 page") }
            state.length = Int(source[state.index - 1]) & 7
        }
        while state.index < state.end {
            try copyLiteral(&state, &output, &destination)
            if state.index >= state.end { break }
            try copyMatches(&state, &output, &destination)
        }
        return output
    }

    private struct State {
        let source: [UInt8]
        var index: Int
        let end: Int
        var length = 0
        var opcode = 0
        var matchOffset = 0

        mutating func next() throws -> Int {
            guard index < source.count else { throw DWG.Error.truncated("R2007 page") }
            defer { index += 1 }
            return Int(source[index])
        }
    }

    private static func copyLiteral(
        _ state: inout State, _ output: inout [UInt8], _ destination: inout Int
    ) throws {
        if state.length == 0 { try readLiteralLength(&state) }
        try copyBlocks(state, &output, destination)
        state.index += state.length
        destination += state.length
    }

    private static func readLiteralLength(_ state: inout State) throws {
        state.length = state.opcode + 8
        if state.length == 0x17 {
            var n = try state.next()
            state.length += n
            if n == 0xFF {
                repeat {
                    n = try state.next()
                    n |= try state.next() << 8
                    state.length += n
                } while n == 0xFFFF
            }
        }
    }

    private static func copyMatches(
        _ state: inout State, _ output: inout [UInt8], _ destination: inout Int
    ) throws {
        state.length = 0
        state.opcode = try state.next()
        try readInstruction(&state)
        while true {
            try copyBack(state, &output, destination)
            destination += state.length
            state.length = state.opcode & 0x07
            if state.length != 0 || state.index >= state.end { break }
            state.opcode = try state.next()
            if state.opcode >> 4 == 0 { break }
            if state.opcode >> 4 == 15 { state.opcode &= 15 }
            try readInstruction(&state)
        }
    }

    private static func readInstruction(_ state: inout State) throws {
        switch state.opcode >> 4 {
        case 0:
            state.length = (state.opcode & 0xF) + 0x13
            state.matchOffset = try state.next()
            state.opcode = try state.next()
            state.length = ((state.opcode >> 3) & 0x10) + state.length
            state.matchOffset = ((state.opcode & 0x78) << 5) + 1 + state.matchOffset
        case 1:
            state.length = (state.opcode & 0xF) + 3
            state.matchOffset = try state.next()
            state.opcode = try state.next()
            state.matchOffset = ((state.opcode & 0xF8) << 5) + 1 + state.matchOffset
        case 2:
            state.matchOffset = try state.next()
            state.matchOffset = ((try state.next() << 8) & 0xFF00) | state.matchOffset
            state.length = state.opcode & 7
            if state.opcode & 8 == 0 {
                state.opcode = try state.next()
                state.length = (state.opcode & 0xF8) + state.length
            } else {
                state.matchOffset += 1
                state.length = (try state.next() << 3) + state.length
                state.opcode = try state.next()
                state.length = ((state.opcode & 0xF8) << 8) + state.length + 0x100
            }
        default:
            state.length = state.opcode >> 4
            state.matchOffset = state.opcode & 15
            state.opcode = try state.next()
            state.matchOffset = ((state.opcode & 0xF8) << 1) + state.matchOffset + 1
        }
    }

    /// Copies earlier output forward, one byte at a time since the source can overlap.
    private static func copyBack(
        _ state: State, _ output: inout [UInt8], _ destination: Int
    ) throws {
        let offset = state.matchOffset
        guard state.length >= 0, destination + state.length <= output.count else {
            throw DWG.Error.invalid("R2007 match past the end of the page")
        }
        guard state.length == 0 || (offset > 0 && destination - offset >= 0) else {
            throw DWG.Error.invalid("R2007 back reference outside the data")
        }
        for index in 0..<state.length {
            output[destination + index] = output[destination - offset + index]
        }
    }

    /// Copies a literal run: 32-byte blocks with their 8-byte words reversed, then the remainder.
    private static func copyBlocks(
        _ state: State, _ output: inout [UInt8], _ destination: Int
    ) throws {
        let source = state.source
        var length = state.length
        guard length >= 0, state.index + length <= source.count,
            destination + length <= output.count
        else { throw DWG.Error.truncated("R2007 literal run") }
        var from = state.index
        var to = destination
        while length >= 32 {
            for word in 0..<4 {
                for byte in 0..<8 {
                    output[to + word * 8 + byte] = source[from + (3 - word) * 8 + byte]
                }
            }
            from += 32
            to += 32
            length -= 32
        }
        guard length > 0 else { return }
        for (size, sourceOffset, destinationOffset) in remainder[length] {
            copyPiece(size, source, from + sourceOffset, &output, to + destinationOffset)
        }
    }

    /// Copies one piece.
    ///
    /// Pieces of 2 and 3 bytes are reversed, and one of 16 has its two halves swapped.
    private static func copyPiece(
        _ size: Int, _ source: [UInt8], _ from: Int, _ output: inout [UInt8], _ to: Int
    ) {
        switch size {
        case 2, 3:
            for index in 0..<size { output[to + index] = source[from + size - 1 - index] }
        case 16:
            for index in 0..<8 {
                output[to + index] = source[from + 8 + index]
                output[to + 8 + index] = source[from + index]
            }
        default:
            for index in 0..<size { output[to + index] = source[from + index] }
        }
    }

    /// For a remainder of 1 to 31 bytes: its pieces, each as size, source offset, destination
    /// offset.
    private static let remainder: [[(Int, Int, Int)]] = [
        [],
        [(1, 0, 0)],
        [(2, 0, 0)],
        [(3, 0, 0)],
        [(4, 0, 0)],
        [(1, 4, 0), (4, 0, 1)],
        [(1, 5, 0), (4, 1, 1), (1, 0, 5)],
        [(2, 5, 0), (4, 1, 2), (1, 0, 6)],
        [(8, 0, 0)],
        [(1, 8, 0), (8, 0, 1)],
        [(1, 9, 0), (8, 1, 1), (1, 0, 9)],
        [(2, 9, 0), (8, 1, 2), (1, 0, 10)],
        [(4, 8, 0), (8, 0, 4)],
        [(1, 12, 0), (4, 8, 1), (8, 0, 5)],
        [(1, 13, 0), (4, 9, 1), (8, 1, 5), (1, 0, 13)],
        [(2, 13, 0), (4, 9, 2), (8, 1, 6), (1, 0, 14)],
        [(16, 0, 0)],
        [(8, 9, 0), (1, 8, 8), (8, 0, 9)],
        [(1, 17, 0), (16, 1, 1), (1, 0, 17)],
        [(3, 16, 0), (16, 0, 3)],
        [(4, 16, 0), (8, 8, 4), (8, 0, 12)],
        [(1, 20, 0), (4, 16, 1), (8, 8, 5), (8, 0, 13)],
        [(2, 20, 0), (4, 16, 2), (8, 8, 6), (8, 0, 14)],
        [(3, 20, 0), (4, 16, 3), (8, 8, 7), (8, 0, 15)],
        [(8, 16, 0), (16, 0, 8)],
        [(8, 17, 0), (1, 16, 8), (16, 0, 9)],
        [(1, 25, 0), (8, 17, 1), (1, 16, 9), (16, 0, 10)],
        [(2, 25, 0), (8, 17, 2), (1, 16, 10), (16, 0, 11)],
        [(4, 24, 0), (8, 16, 4), (8, 8, 12), (8, 0, 20)],
        [(1, 28, 0), (4, 24, 1), (8, 16, 5), (8, 8, 13), (8, 0, 21)],
        [(2, 28, 0), (4, 24, 2), (8, 16, 6), (8, 8, 14), (8, 0, 22)],
        [(1, 30, 0), (4, 26, 1), (8, 18, 5), (8, 10, 13), (8, 2, 21), (2, 0, 29)],
    ]
}
