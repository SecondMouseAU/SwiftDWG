// Shared by Dimensions.swift, Leader.swift and Hatch.swift. Nothing here is ported from a single
// ACadSharp function: it is the guard those decoders use so that a count read from the file cannot
// make them loop past the object.

/// Helpers for the decoders of dimensions, leaders and hatches.
enum DimensionsSupport {
    /// Which of an object's streams a counted run of values is read from.
    enum Stream {
        /// The numbers and flags.
        case main
        /// The handle references.
        case handles
    }

    /// Checks a count read from the object against the bits the object has left, so that a
    /// corrupt count throws at once and does not walk into the next object.
    ///
    /// `bitsEach` is the fewest bits one element can take. The main data of an object ends before
    /// its handle stream starts, so the handle reader's position is a safe upper bound for it.
    ///
    /// - Throws: `DWG.Error.invalid` when the count is negative or cannot fit.
    static func boundedCount(
        _ count: Int32, bitsEach: Int, stream: Stream = .main, in reader: ObjectReader,
        what: String
    ) throws -> Int {
        let bitsLeft: Int
        switch stream {
        case .main: bitsLeft = reader.handles.position - reader.main.position
        case .handles: bitsLeft = reader.handles.bitCount - reader.handles.position
        }
        guard count >= 0, bitsLeft >= 0, bitsEach > 0, Int(count) <= bitsLeft / bitsEach else {
            throw DWG.Error.invalid(
                "\(count) \(what) in an object with \(max(bitsLeft, 0)) bits left")
        }
        return Int(count)
    }
}
