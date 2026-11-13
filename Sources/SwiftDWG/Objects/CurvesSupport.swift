// Helpers shared by Curves.swift, Polylines.swift and Surfaces.swift. Nothing here comes from
// ACadSharp: the count checks are this package's own, so that a count read from a damaged file
// cannot ask for more elements than the object has data for.

import SwiftDXF

extension DXF.Point {
    /// A point from the triple a bit reader returns.
    init(fromBits triple: (x: Double, y: Double, z: Double)) {
        self.init(triple.x, triple.y, triple.z)
    }
}

extension ObjectReader {
    /// Checks a count of elements read from the object against the data it has left.
    ///
    /// The object's numbers end where its handles begin, and `handles` is already there once the
    /// data every entity starts with has been read. Each element takes at least `bitsEach` bits of
    /// them, so a count above that share of what is left is not a count this object can hold.
    ///
    /// - Throws: `DWG.Error.invalid` for a negative count or one that does not fit.
    func checkedElementCount(_ count: Int32, bitsEach: Int, _ what: String) throws -> Int {
        let left = max(0, handles.position - main.position)
        guard count >= 0, Int(count) <= left / max(1, bitsEach) else {
            throw DWG.Error.invalid("\(count) \(what) in an object with \(left) bits of data")
        }
        return Int(count)
    }

    /// Checks a count of handle references read from the object against the bytes that are left.
    ///
    /// Each reference takes at least one byte, so a count above the bytes after the handles read
    /// so far is not a count this object can hold.
    ///
    /// - Throws: `DWG.Error.invalid` for a negative count or one that does not fit.
    func checkedHandleCount(_ count: Int32, _ what: String) throws -> Int {
        let left = max(0, handles.bitCount - handles.position)
        guard count >= 0, Int(count) <= left / 8 else {
            throw DWG.Error.invalid("\(count) \(what) in a file with \(left / 8) bytes after them")
        }
        return Int(count)
    }

    /// Reads a bit short as the unsigned 16-bit flags word it holds.
    mutating func readFlagsWord() throws -> Int {
        Int(UInt16(bitPattern: try main.readBitShort()))
    }
}
