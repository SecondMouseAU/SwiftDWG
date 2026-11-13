// To be ported from ACadSharp (MIT): DwgObjectReader.cs (readHatch)
// The header must say so, as in Geometry.swift. See NOTICE.md.

import SwiftDXF

/// The fields of the entity.
///
/// In the file's own terms. To be defined.
struct HatchData {}

extension ObjectReader {
    mutating func readHatch() throws -> DecodedEntity {
        throw NotDecodedYet(what: "Hatch")
    }
}
