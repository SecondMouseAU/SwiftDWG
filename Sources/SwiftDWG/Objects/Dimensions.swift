// To be ported from ACadSharp (MIT): DwgObjectReader.cs (readCommonDimensionData and the readDim* functions)
// The header must say so, as in Geometry.swift. See NOTICE.md.

import SwiftDXF

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct DimensionData {}

extension ObjectReader {
    mutating func readDimension() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Dimension")
    }
}
