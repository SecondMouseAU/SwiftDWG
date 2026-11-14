import Foundation
import Testing

@testable import SwiftDWG

/// A corrupt file must end in an error, or in a drawing that counts what it lost.
///
/// It must not stop the process with a trap, or never return.
@Suite("Corrupt input")
struct CorruptInputTests {
    @Test("an LZ77 match with an opcode below 0x10 throws instead of trapping on a length of -1")
    func negativeMatchLength() {
        // One literal, four more literals, then an opcode of 0x05 where a match opcode must be 0x10
        // or more. It gave a length of (0x05 >> 4) - 1, which is -1.
        let stream: [UInt8] = [0x12, 0x41, 0x01, 0x42, 0x42, 0x42, 0x42, 0x05, 0x00, 0x11]
        #expect(throws: DWG.Error.invalid("LZ77 match with a negative length")) {
            _ = try LZ77.decompressAC18(stream, from: 0, limit: 100)
        }
    }

    /// Reads `bytes` with the byte at `offset` inverted.
    ///
    /// It records an issue if the read ends in an error that is not a `DWG.Error`. Returning is the
    /// other thing it checks: a trap ends the test run.
    private func read(_ bytes: [UInt8], inverting offset: Int, in name: String) {
        var damaged = bytes
        damaged[offset] ^= 0xFF
        do {
            _ = try DWG.read(data: Data(damaged))
        } catch is DWG.Error {
        } catch {
            Issue.record("\(name), byte \(offset): \(error) is not a DWG.Error")
        }
    }

    @Test(
        "files with a byte inverted end in an error or a drawing, for both of the fixtures",
        .timeLimit(.minutes(1)), arguments: ["BLOCKPOINTPARAMETER.dwg", "empty.dwg"])
    func invertedBytes(_ name: String) throws {
        let bytes = try Fixtures.data(name)
        // Every byte of the file header, where a corrupt value steers the reader; then one byte in
        // 1,009 of the remainder, which is prime so it does not keep to a page boundary. The bytes
        // that trapped or never returned are in as well. The whole file is read for each, so this
        // keeps the count down: the same sweep over the AutoCAD samples is run by hand, one process
        // for each byte.
        var offsets = Set(0..<min(bytes.count, 0x100))
        offsets.formUnion(stride(from: 0, to: bytes.count, by: 1009))
        offsets.formUnion([840, 7209, 30248, 35333].filter { $0 < bytes.count })
        for offset in offsets.sorted() { read(bytes, inverting: offset, in: name) }
    }
}
