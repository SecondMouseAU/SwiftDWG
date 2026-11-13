// The count check below is this package's own. The CMC colour reader these entities use is in
// TablesColor.swift.

extension ObjectReader {
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
